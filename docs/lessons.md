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
- The operator ClusterRole (`config/rbac/role.yaml`) must be a superset of ALL permissions that child chart ClusterRoles delegate. Kubernetes RBAC escalation prevention blocks the operator from creating ClusterRoles that grant permissions it does not hold. When upgrading the bundled chart, audit all child rbac.yaml files and update role.yaml.
- Post-install hooks that use `post-upgrade` cause infinite reconciliation loops with any automated reconciler (operator, ArgoCD, Flux). The chart's hooks assume manual `helm upgrade` workflows. Workaround: change `post-install,post-upgrade` to `post-install` only.
- Deployment templates that hardcode `replicas: 0` (relying on hooks to scale) must be changed to use the actual replica value from values.yaml. Otherwise, removing `post-upgrade` from hooks causes replicas to reset to 0 on every reconciliation.

## Correction Log
Format: YYYY-MM-DD | category | brief description

2026-03-24 | olm bundle | `make bundle` stripped `com.redhat.openshift.versions` annotation. Pipeline static test failed. Fixed by adding annotation back to bundle/metadata/annotations.yaml.
2026-03-24 | olm bundle | Metrics service name exceeded 63-char K8s DNS label limit (66 chars). Pipeline preflight test failed. Fixed by shortening name in config/default/kustomization.yaml.
2026-03-24 | git workflow | community-operators-prod DCO check failed because commit lacked Signed-off-by line. Fixed with amend and force push.
2026-03-24 | rbac | Operator ClusterRole missing permissions for child chart components (apiextensions.k8s.io, logicmonitor.com, nodes, PVs, etc.). K8s RBAC escalation prevention blocked Helm release. Required cluster-admin workaround until role.yaml was expanded.
2026-03-24 | helm chart | Post-install hooks with post-upgrade annotation caused 41 Helm revisions in 15 minutes. Deployment templates hardcoded replicas:0. Fixed both in bundled chart.
2026-03-24 | helm chart | CSC does not auto-create collector groups. Hangs indefinitely retrying GET. Added LM API call to post-install hook as workaround.

## Convergence Tracker

| Category | Count | Last Occurrence | Trend |
|----------|-------|-----------------|-------|
| olm bundle | 2 | 2026-03-24 | New -- two distinct sub-patterns (annotation stripping, name length) |
| git workflow | 1 | 2026-03-24 | New -- DCO requirement for community-operators-prod |
| rbac | 1 | 2026-03-24 | New -- escalation prevention requires superset of child permissions |
| helm chart | 2 | 2026-03-24 | New -- upstream chart assumes manual helm workflows |
