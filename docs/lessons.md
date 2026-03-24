# Project-Specific Learned Behavioral Rules
# Review at session start. These are hard constraints learned from past corrections.
# Global lessons are in ~/.claude/docs/lessons.md -- this file is for THIS project only.

## OLM Bundle

- `make bundle` STRIPS custom annotations from bundle metadata. The `com.redhat.openshift.versions` annotation in `bundle/metadata/annotations.yaml` is removed every time. After running `make bundle`, ALWAYS re-add this annotation (either manually or via `patch-bundle-csv.sh`). Verify it exists before committing.
- Kustomize namePrefix concatenated with base resource names can exceed the K8s 63-character DNS label limit. Before submitting a bundle, verify ALL generated resource names are <= 63 chars. The metrics service name hit this: `logicmonitor-openshift-operator-controller-manager-metrics-service` (66 chars). Shortened to `manager-metrics-svc`.
- community-operators-prod requires DCO (Developer Certificate of Origin). ALL commits in a PR must have `Signed-off-by: Name <email>` in the commit message. Use `git commit --signoff` for every commit targeting that repo.

## community-operators-prod Pipeline

- The pipeline has 4 independent validation gates, each can fail separately:
  1. DCO check (Signed-off-by on all commits)
  2. Static tests (API version constraints, OpenShift version annotation presence)
  3. Preflight tests (DeployableByOLM -- actually deploys and tests the operator)
  4. Maintainer approval
- Fix failures one at a time. Force-pushing the PR branch re-triggers the pipeline.
- Stale PRs for older versions should be closed before or alongside new version submissions to avoid maintainer confusion.

## Helm Chart Upgrades

- When upstream lm-container chart releases a new version, the full upgrade path is: update chart in `helm-charts/lm-container/`, bump operator version in Makefile, run `make bundle`, re-add stripped annotations, update README, tag, push, submit PR to community-operators-prod.

## Bundled Chart Modifications

- The operator bundles a copy of the lm-container Helm chart. When the upstream chart has bugs, apply minimal targeted workarounds to the bundled copy and document in `docs/product-bugs-lm-container-v13.md`.
- The operator ClusterRole (`config/rbac/role.yaml`) must be a superset of ALL permissions that child chart ClusterRoles delegate. Kubernetes RBAC escalation prevention blocks the operator from creating ClusterRoles that grant permissions it does not hold. When upgrading the bundled chart, audit all child rbac.yaml files and update role.yaml. ADDITIONALLY: the operator ClusterRole needs `escalate` and `bind` verbs on `clusterroles` and `clusterrolebindings` resources. Without these, even a complete list of explicit permissions is insufficient when child charts use aggregationRules or wildcard verbs. Explicit permissions + escalate/bind is the correct pattern.
- Post-install hooks that use `post-upgrade` cause infinite reconciliation loops with any automated reconciler (operator, ArgoCD, Flux). The chart's hooks assume manual `helm upgrade` workflows. Workaround: change `post-install,post-upgrade` to `post-install` only.
- Deployment templates that hardcode `replicas: 0` (relying on hooks to scale) must be changed to use the actual replica value from values.yaml. Otherwise, removing `post-upgrade` from hooks causes replicas to reset to 0 on every reconciliation.
- When writing hook scripts that run in minimal container images (e.g., `logicmonitor/kubectl`), verify tool availability BEFORE building and pushing. Common missing tools: `openssl`, `curl` (sometimes), `jq`. Check by reading the Dockerfile or running `docker run --rm <image> which <tool>`. Pure-bash alternatives exist for most crypto operations (e.g., HMAC-SHA256 via xxd + sha256sum). Verify any crypto implementation against a known test vector before deploying.

## OLM Testing Workflow

- Use a custom CatalogSource pointing to your own bundle index image to test the full OLM install flow before submitting to community-operators-prod. This tests the exact same path users experience (subscription, install plan, CSV, operator deployment).
- OLM and Kubernetes nodes cache container images by tag. During development, pushing a new image with the same tag (e.g., `v0.3.0`) will NOT cause the node to pull the updated image. Use unique tags for each iteration (e.g., `0.3.1-rc1`, `0.3.1-rc2`) or set `imagePullPolicy: Always` on the operator deployment. Unique tags are more reliable because imagePullPolicy depends on the CSV/deployment spec which may also be cached.
- Sample resources in `config/samples/` are included in the OLM bundle. OLM applies them to the operator namespace as example CRs. If `config/samples/` contains a Secret with placeholder credentials, OLM will create that Secret, potentially overwriting real credentials the user already deployed. Either exclude Secrets from samples, use obviously-invalid placeholder values (e.g., `REPLACE_ME`), or add a note in the CSV description warning users to deploy credentials before installing.

## Correction Log
Format: YYYY-MM-DD | category | brief description

2026-03-24 | olm bundle | `make bundle` stripped `com.redhat.openshift.versions` annotation. Pipeline static test failed. Fixed by adding annotation back to bundle/metadata/annotations.yaml.
2026-03-24 | olm bundle | Metrics service name exceeded 63-char K8s DNS label limit (66 chars). Pipeline preflight test failed. Fixed by shortening name in config/default/kustomization.yaml.
2026-03-24 | git workflow | community-operators-prod DCO check failed because commit lacked Signed-off-by line. Fixed with amend and force push.
2026-03-24 | rbac | Operator ClusterRole missing permissions for child chart components (apiextensions.k8s.io, logicmonitor.com, nodes, PVs, etc.). K8s RBAC escalation prevention blocked Helm release. Required cluster-admin workaround until role.yaml was expanded.
2026-03-24 | helm chart | Post-install hooks with post-upgrade annotation caused 41 Helm revisions in 15 minutes. Deployment templates hardcoded replicas:0. Fixed both in bundled chart.
2026-03-24 | helm chart | CSC does not auto-create collector groups. Hangs indefinitely retrying GET. Added LM API call to post-install hook as workaround.
2026-03-24 | rbac | Expanded role.yaml with all explicit permissions but still failed. Child chart ClusterRoles use aggregationRules and wildcard verbs which require escalate+bind verbs. Took 3 iterations to get right: initial expansion, missing escalate/bind, final fix.
2026-03-24 | container image | Hook script assumed openssl was available in logicmonitor/kubectl image. It was not, and non-root prevents apk add. Code reviewer flagged it but we did not verify before building. Cost 2 extra build/push cycles. Fixed with pure-bash HMAC.
2026-03-24 | olm testing | Pushed updated image with same tag (v0.3.0), ARO node used cached old image. Wasted a full rebuild cycle before realizing unique tags are required for iterative testing.
2026-03-24 | olm bundle | Sample Secret in config/samples/ gets applied by OLM to the namespace. Placeholder credentials overwrite real user credentials. Not yet fixed -- needs architectural decision on how to handle.

## Convergence Tracker

| Category | Count | Last Occurrence | Trend |
|----------|-------|-----------------|-------|
| olm bundle | 3 | 2026-03-24 | Recurring -- annotation stripping, name length, sample secret collision. Three distinct sub-patterns. |
| git workflow | 1 | 2026-03-24 | Stable -- DCO requirement for community-operators-prod |
| rbac | 2 | 2026-03-24 | Recurring -- escalation prevention is deeper than just listing permissions. escalate+bind verbs required. |
| helm chart | 2 | 2026-03-24 | Stable -- upstream chart assumes manual helm workflows. Well-documented now. |
| container image | 1 | 2026-03-24 | New -- verify tool availability before building images |
| olm testing | 1 | 2026-03-24 | New -- image tag caching during iterative development |
