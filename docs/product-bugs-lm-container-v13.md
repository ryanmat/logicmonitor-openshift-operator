# lm-container Helm Chart v13.0.0 Product Bugs

Discovered 2026-03-24 during operator v0.3.0 validation on ARO 4.20.15.
These require changes to the upstream lm-container Helm chart (argus/collectorset-controller).

All three bugs share a common root cause: the chart assumes a manual `helm install`/`helm upgrade`
workflow driven by a human operator. Any automated reconciler (Helm-based operator, ArgoCD, Flux)
triggers different failure modes. These are the same class of issues found during the SMBC ArgoCD
engagement (15 findings) -- different symptoms, same architectural gap.

---

## Bug 1: Post-Install Hooks Cause Infinite Reconciliation Loop

### Impact
Any external reconciler (Helm-based operator, ArgoCD, Flux, Rancher Fleet) enters an
infinite upgrade loop. Pods never stabilize. Observed 41 Helm revisions in 15 minutes on
a fresh install.

### Root Cause
The `argus-props-patch` and `csc-props-patch` jobs are Helm **post-upgrade** hooks (not
just post-install). They run on every reconciliation cycle and:

1. Patch the deployment with env vars from userDefinedSecret (line ~268 in post-install.yaml)
2. Call `kubectl scale deployment ... --replicas=N` (line ~271 in post-install.yaml)

The `kubectl scale` command modifies the deployment spec (sets replicas explicitly), which
the reconciler detects as drift from the desired state, triggering another upgrade. This
creates the loop: reconcile -> upgrade -> hook patches+scales -> drift detected -> reconcile.

Additionally, both deployment templates hardcode `replicas: 0` and rely on the hooks to
scale them up. This design means hooks are not optional -- they are required for the chart
to function at all.

### Evidence
```
# Helm release count after 15 minutes of operation:
$ oc get secrets -n logicmonitor -l name=lm-container,owner=helm | tail -2
sh.helm.release.v1.lm-container.v37   helm.sh/release.v1   1      16s
sh.helm.release.v1.lm-container.v38   helm.sh/release.v1   1      3s

# Post-install job output showing the scale command:
Applying deployment patch...
deployment.apps/lm-container-argus patched (no change)
deployment.apps/lm-container-argus scaled

# Pods never reached Ready state until operator was manually scaled to 0.
```

### Customer Impact
Customers using ArgoCD and similar GitOps tools report the same symptom. The post-install
hooks conflict with any controller that enforces desired state on managed resources.

### Suggested Fix (Upstream)
1. Remove the `kubectl scale` call from post-install hooks. The deployment replicas are
   already set by the Helm chart values -- scaling is redundant and destructive.
2. Consider making the env var patching declarative (in the chart templates) rather than
   imperative (in post-install hooks). The hooks exist to work around the fact that
   userDefinedSecret env vars are not rendered directly in the deployment template when
   userDefinedSecret is set.
3. If hooks must remain, use `helm.sh/hook: post-install` only (not post-upgrade) and
   make them idempotent (no-op if already patched).
4. Change deployment templates from `replicas: 0` to `replicas: {{ .Values.replicas }}`
   so deployments start with the correct replica count without needing hooks.

### Workaround Applied in v0.3.1

Two-part fix in the bundled chart:

**Part A -- Deployment replicas:** Changed `replicas: 0` to the correct value in both
deployment templates so they start with the right replica count.
- `charts/argus/templates/deployment.yaml` line 13: `replicas: {{ .Values.replicas }}`
- `charts/collectorset-controller/templates/deployment.yaml` line 13: `replicas: 1`

**Part B -- Hook annotation:** Changed `post-install,post-upgrade` to `post-install` in
both hook templates so they only run on initial install.
- `charts/argus/templates/post-install.yaml`
- `charts/collectorset-controller/templates/post-install.yaml`

**Part C -- Removed redundant scale calls:** With deployment templates now setting the
correct replica count (Part A), the `kubectl scale` calls in post-install hooks are no-ops.
Removed to eliminate dead code and any residual drift risk if hook timing races with the
reconciler.
- `charts/argus/templates/post-install.yaml`: removed `kubectl scale` call
- `charts/collectorset-controller/templates/post-install.yaml`: removed `kubectl scale` call

### Affected Templates
- `charts/argus/templates/post-install.yaml`
- `charts/collectorset-controller/templates/post-install.yaml`
- `charts/argus/templates/deployment.yaml`
- `charts/collectorset-controller/templates/deployment.yaml`

---

## Bug 2: CollectorSet Controller Does Not Auto-Create Collector Groups

### Impact
Fresh deployments hang indefinitely. CSC retries GET for the collector group every 60
seconds but never creates it. Requires manual collector group creation via the LM REST API
before collectors can be provisioned.

### Root Cause
When CSC starts, it looks up the collector group by name ("Kubernetes Cluster: <clusterName>").
If the group does not exist, CSC logs the error and retries but does not attempt to create
the group. The expected behavior is GET -> not found -> CREATE -> proceed.

### Evidence
```
time="2026-03-24T16:15:35Z" level=info msg="Account domain is: lmryanmatuszewski.logicmonitor.com"
time="2026-03-24T16:15:35Z" level=info msg="Starting to create collectorset: lm-container-argus"
time="2026-03-24T16:15:35Z" level=info msg="Group name is Kubernetes Cluster: aro-operator-dev"
time="2026-03-24T16:15:35Z" level=info msg="Collector group does not exist"
time="2026-03-24T16:15:35Z" level=info msg="Collector group does not exist"
time="2026-03-24T16:15:35Z" level=error msg="Attempt 1: error getting collector group. Retrying in 1 minute..."
# ... repeats every 60 seconds indefinitely

# Manual fix: created collector group via REST API
$ curl -X POST ".../setting/collector/groups" -d '{"name":"Kubernetes Cluster: aro-operator-dev"}'
# CSC immediately picked up the group and provisioned collectors.
```

### Suggested Fix (Upstream)
CSC should create the collector group when it does not exist, the same way it creates
collectors. This was likely the intended behavior but may have regressed or may require a
specific API permission that is not documented.

### Workaround Applied in v0.3.1

Added collector group auto-creation to the argus post-install hook. After credential
extraction, the hook calls the LM REST API to POST-create "Kubernetes Cluster: <clusterName>".
Uses LMv1 HMAC-SHA256 auth with the credentials from userDefinedSecret.

Uses POST-first approach (attempt creation, handle "already exists" gracefully) rather than
GET-then-POST. This avoids LM API filter syntax issues with the colon character in the
group name "Kubernetes Cluster: ..." and provides clear diagnostic logging for every
failure mode (auth errors, network issues, duplicate groups).

CSC starts in parallel and retries every 60s. The hook completes within seconds, so CSC
finds the group on its next retry cycle.

### Affected Component
- collectorset-controller v13.4.0 (app v13.4.0)
- Workaround in: `charts/argus/templates/post-install.yaml`

---

## Bug 3: Operator RBAC Too Narrow for Child Component Delegation

### Impact
Operator cannot deploy the Helm chart. Child component ClusterRoles (argus, CSC, KSM)
require cluster-scoped permissions that the operator SA does not hold. Kubernetes RBAC
escalation prevention blocks the operator from creating ClusterRoles that grant permissions
it does not itself have.

### Root Cause
The operator bundle's ClusterRole was designed for the operator's own needs (managing
LMContainer CRs, basic Helm release resources) but did not account for the permissions that
the Helm chart's child ClusterRoles delegate. The child charts use aggregationRules and
grant broad cluster-scoped access (nodes, PVs, componentstatuses, CRDs, etc.).

### Evidence
```
# Error from operator logs:
clusterroles.rbac.authorization.k8s.io "lm-container-collectorset-controller-child" is forbidden:
user "system:serviceaccount:logicmonitor:logicmonitor-openshift-operator-controller-manager"
is attempting to grant RBAC permissions not currently held

# Required manual cluster-admin grant to proceed:
$ oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:logicmonitor:...
```

### Fix Applied in v0.3.1

Expanded `config/rbac/role.yaml` to include all permissions required by child component
ClusterRoles. Added API groups: `logicmonitor.com`, `apiextensions.k8s.io`, `storage.k8s.io`,
`scheduling.k8s.io`, `cert-manager.io`, `extensions`. Added missing core API resources
(nodes, componentstatuses, persistentvolumes, etc.) and non-resource URLs.

CSC wildcard `"*"` verbs expanded to explicit verb lists (no wildcards in operator ClusterRole).

### Affected Files
- `config/rbac/role.yaml`
- `bundle/manifests/logicmonitor-openshift-operator.clusterserviceversion.yaml` (generated)

---

## Bug 4: lm-logs Subchart Incompatible with userDefinedSecret

### Impact
Enabling `lm-logs.enabled: true` when credentials are provided via `global.userDefinedSecret`
causes the Helm release to fail. The operator enters a reconciliation error loop and the
lm-logs DaemonSet never deploys. Existing components (argus, CSC, KSM) continue running
but no new reconciliation changes are applied until lm-logs is disabled.

### Root Cause
The lm-logs subchart templates read credentials as plain Helm values (`lm_company_name`,
`lm_access_id`, `lm_access_key`) directly in `configmap.yaml`. When credentials are
provided via `userDefinedSecret`, these values are empty. The template contains a hard
`fail` directive that aborts rendering when the secret lookup fails.

The argus and CSC subcharts handle `userDefinedSecret` through post-install hooks that
extract credentials from the secret at runtime and inject them as env vars. The lm-logs
subchart does not participate in this mechanism.

### Evidence
```
Failed to sync release: execution error at (lm-container/charts/lm-logs/templates/configmap.yaml:5:6):
global.userDefinedSecret="lm-credentials" not found in namespace "logicmonitor"
```
Reproduced on ARO 4.20.15 with operator v0.3.1. The same chart works on AKS when using
inline credentials (accessID/accessKey/account directly in Helm values).

### Workaround
None via the operator. Customers cannot enable lm-logs when using `userDefinedSecret`.
The only workaround is to use inline credentials in the Helm values, which is not
supported by the operator (it always uses `userDefinedSecret`).

### Suggested Fix (Upstream)
lm-logs templates should read credentials from the Kubernetes Secret referenced by
`global.userDefinedSecret` using `secretKeyRef` in pod env vars, the same way argus
and CSC do. Alternatively, the post-install hook should inject credentials into
lm-logs components.

### Affected Component
- lm-logs v1.0.1 (subchart of lm-container v13.0.0)
- `charts/lm-logs/templates/configmap.yaml`

---

## Bug 5: Argus Deployment Missing companyDomain Default with userDefinedSecret

### Impact
The argus Deployment pod (discovery agent) crashes on startup with a DNS resolution
failure when using `userDefinedSecret` without a `companyDomain` key in the secret
and without `global.companyDomain` set in the Helm values. The API URL resolves to
`https://<account>.` instead of `https://<account>.logicmonitor.com`.

The argus StatefulSet collector pods are unaffected because the post-install hook
patches them with the correct `COMPANY_DOMAIN` env var.

### Root Cause
When credentials come from `userDefinedSecret`, the chart extracts the `account` field
but does not default `companyDomain` to `logicmonitor.com`. The argus Deployment pod
constructs the API URL by concatenating `account` + `.` + `companyDomain`, resulting
in a trailing dot with no domain.

The post-install hook handles this correctly for the StatefulSet pods (it checks for
`companyDomain` in the secret and falls back to the Helm value or `logicmonitor.com`).
But the Deployment pod is not patched by the hook.

### Evidence
```
level=fatal msg="Failed to initialize argus: failed to build resource tree:
Get \"https://lmryanmatuszewski./santaba/rest/device/groups/493\":
dial tcp: lookup lmryanmatuszewski. on 172.30.0.10:53: no such host"
```
Reproduced on ARO 4.20.15 with operator v0.3.1. The AKS cluster does not hit this
because it uses inline credentials where `companyDomain` defaults are applied at the
Helm values level.

### Workaround
Set `global.companyDomain: "logicmonitor.com"` in the LMContainer CR spec, or add a
`companyDomain` key to the credentials Secret.

### Suggested Fix (Upstream)
The chart should default `companyDomain` to `logicmonitor.com` in the argus Deployment
template when the value is not provided. This default is already applied in the
post-install hook logic but not in the Deployment template itself.

### Affected Component
- argus v15.0.1 (app v18.0.0)
- `charts/argus/templates/deployment.yaml`

---

## userDefinedSecret Integration Gaps (Pattern)

Bugs 4 and 5 share a common root cause: the `userDefinedSecret` feature is a bolt-on
that only covers code paths explicitly handled by the post-install hooks. Components
that read credentials or configuration directly from Helm values (not from env vars
injected by hooks) break when `userDefinedSecret` is used.

**Affected components:**
- lm-logs: reads credentials as plain Helm values (Bug 4)
- argus Deployment: missing companyDomain default (Bug 5)
- lmotel: likely affected (untested, same credential pattern as lm-logs)

**Unaffected components (hooks patch these):**
- argus StatefulSet (collector pods)
- collectorset-controller Deployment

The `userDefinedSecret` mechanism was designed for argus and CSC. When lm-logs and
lmotel were added as subcharts, the credential injection was not extended to cover
them. Any new subchart added to lm-container will likely have the same gap unless
it participates in the post-install hook credential injection.

---

## Environment
- OpenShift 4.20.15 (Azure Red Hat OpenShift)
- lm-container chart v13.0.0
- argus 15.0.1 (app v18.0.0)
- collectorset-controller 12.2.0 (app v13.4.0)
- kube-state-metrics included in chart
