# Known Issues: lm-container v13.0.0

This document covers known issues with the lm-container Helm chart v13.0.0 bundled in the
LogicMonitor OpenShift Operator. Workarounds are applied in operator v0.3.1. These are
pending upstream fixes in the lm-container chart.

For full technical details and evidence, see `docs/product-bugs-lm-container-v13.md`.

## Post-Install Hook Compatibility

The lm-container chart uses Helm post-install/post-upgrade hooks to configure deployments
after installation. These hooks are designed for manual `helm install`/`helm upgrade`
workflows and conflict with automated reconcilers (operator, ArgoCD, Flux).

**Symptoms without workaround:**
- Pods restart continuously and never reach Ready state
- Helm release revision count climbs rapidly (dozens per minute)
- Operator logs show constant reconciliation activity

**Operator v0.3.1 workaround:** Hooks run only on initial install (not on every
reconciliation). Deployment templates declare correct replica counts directly. Users
should not need to take any action.

**Limitation:** If you change proxy settings in the credentials secret after initial
deployment, the hooks will not re-run to patch the new values. Delete and recreate the
LMContainer CR to trigger a fresh install in this scenario.

## Collector Group Auto-Creation

The CollectorSet Controller (CSC) expects a collector group named
"Kubernetes Cluster: <clusterName>" to exist in the LogicMonitor portal. In v13.0.0, CSC
does not create this group automatically.

**Symptoms without workaround:**
- CSC logs: "Collector group does not exist. Retrying in 1 minute..."
- No collectors provisioned
- Argus cannot connect to CSC (NOT_SERVING)

**Operator v0.3.1 workaround:** The operator automatically creates the collector group via
the LM REST API during initial deployment. Users should not need to take any action.

**If auto-creation fails:** You can create the group manually in the LogicMonitor portal
under Settings > Collectors > Collector Groups. Name it exactly:
"Kubernetes Cluster: <your-cluster-name>" (matching the clusterName in your LMContainer CR).

## RBAC Requirements

The operator requires broad cluster-scoped RBAC permissions because the lm-container Helm
chart creates ClusterRoles for its child components (argus, collectorset-controller,
kube-state-metrics). Kubernetes RBAC escalation prevention requires the operator to hold
all permissions it delegates.

**Operator v0.3.1 fix:** The operator ClusterRole includes all required permissions.
No manual RBAC configuration should be needed when installing from OperatorHub.
