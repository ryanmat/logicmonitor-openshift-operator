# Changelog

All notable changes to the LogicMonitor OpenShift Operator are documented here.

## [0.3.2] - 2026-03-26

### Fixed
- Added `global.companyDomain: "logicmonitor.com"` to all sample CRs. When using
  `userDefinedSecret`, the argus Deployment pod crashes without this field because
  the API URL resolves to `https://account.` instead of `https://account.logicmonitor.com`.

### Added
- Known issues documentation for `companyDomain` requirement when using
  `userDefinedSecret`.
- Known issues documentation for `lm-logs` subchart incompatibility with the
  operator (requires inline credentials not supported by the operator).
- Documented argus built-in log forwarding (`k8sevent`, `k8spodlog`) as the
  supported alternative to the `lm-logs` subchart.

### Known Issues
- `lm-logs` and `lmotel` subcharts cannot be enabled via the operator. They require
  inline credentials. Use argus built-in log forwarding instead.
- See `docs/product-bugs-lm-container-v13.md` for all upstream chart bugs (5 total).

## [0.3.1] - 2026-03-24

### Fixed
- Expanded operator RBAC ClusterRole to include all permissions required by child
  chart components (argus, collectorset-controller, kube-state-metrics). Added
  `escalate` and `bind` verbs for ClusterRole delegation.
- Post-install hooks changed from `post-install,post-upgrade` to `post-install`
  only. The `post-upgrade` annotation caused infinite reconciliation loops with
  automated reconcilers (operator, ArgoCD, Flux).
- Deployment templates changed from `replicas: 0` (relying on hooks to scale) to
  actual replica values. Deployments now start with the correct replica count
  without needing hooks.
- Removed redundant `kubectl scale` calls from post-install hooks (dead code
  after the deployment template fix above).
- Removed placeholder credentials Secret from OLM bundle. The Secret had
  `REPLACE_WITH_*` values and could overwrite real user credentials on install.

### Added
- Collector group auto-creation via LM REST API in the argus post-install hook.
  Works around a CSC bug where it retries GET for the collector group without
  ever creating it. Uses POST-first approach with diagnostic logging.
- Shortend metrics service name to comply with 63-character K8s DNS label limit.
- `com.redhat.openshift.versions` annotation for OpenShift catalog compatibility.

### Known Issues
- Pure-bash HMAC-SHA256 auth for the collector group API call returns 401. The
  hook is non-fatal (`set +e`) and CSC handles group lookup as a fallback. See
  `docs/known-issues.md` for details and manual workaround.
- See `docs/product-bugs-lm-container-v13.md` for upstream lm-container chart
  bugs that motivated these workarounds.

## [0.3.0] - 2026-03-10

### Added
- Initial release published to OperatorHub (Community Operators catalog).
- Helm-based operator wrapping lm-container v13.0.0 chart.
- LMContainer CRD (`monitoring.logicmonitor.com/v1alpha1`).
- OLM bundle with sample CRs for minimal, full, OpenShift, and ROSA deployments.
- OpenShift SCC support for kube-state-metrics.
- Credential validation script (`make validate-credentials`).
