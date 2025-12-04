# Description: Reference documentation for lm-container Helm chart values.
# Description: Documents required fields, defaults, and subchart configurations.

# LM-Container Helm Chart Values Reference

Chart Version: 11.2.0
Kubernetes Version: >= 1.16.0

## Required Values

These values must be set for the chart to function. Provide them either directly or via `global.userDefinedSecret`.

| Field | Type | Description |
|-------|------|-------------|
| `global.accessID` | string | LogicMonitor API Token access ID |
| `global.accessKey` | string | LogicMonitor API Token access key |
| `global.account` | string | LogicMonitor account name (subdomain from `<account>.logicmonitor.com`) |
| `argus.clusterName` | string | Unique name for the cluster resource group in LogicMonitor |

## Using a Secret for Credentials

Instead of providing credentials directly, reference a Kubernetes Secret:

```yaml
global:
  userDefinedSecret: "lm-credentials"
```

The Secret must contain these keys:
- `accessID`
- `accessKey`
- `account`

Optional keys:
- `etcdDiscoveryToken`
- Proxy credentials

## Global Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `global.companyDomain` | string | `""` | LogicMonitor domain (e.g., `logicmonitor.com`, `lmgov.us`) |
| `global.userDefinedSecret` | string | `""` | Name of Secret containing LM credentials |
| `global.image.registry` | string | `""` | Override image registry for all components |
| `global.image.pullPolicy` | string | `""` | Override image pull policy for all components |
| `global.collectorsetServiceNameSuffix` | string | `"lm-container-collectorset-controller"` | Service name suffix for collectorset controller |

## Component Enable Flags

| Component | Field | Default | Description |
|-----------|-------|---------|-------------|
| Argus | `argus.enabled` | `true` | Kubernetes resource discovery and monitoring |
| Collectorset Controller | `collectorset-controller.enabled` | `true` | Manages collector pod lifecycle |
| Kube State Metrics | `kube-state-metrics.enabled` | `true` | Kubernetes metrics exporter |
| LM Logs | `lm-logs.enabled` | `false` | Log forwarding to LogicMonitor |
| LMOTEL | `lmotel.enabled` | `false` | OpenTelemetry integration |

## Argus Configuration

Argus handles Kubernetes resource discovery and monitoring.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `argus.clusterName` | string | `""` | **Required.** Unique cluster identifier in LogicMonitor |
| `argus.clusterTreeParentID` | integer | `1` | Parent resource group ID for the cluster tree |

For full Argus configuration options, see:
https://artifacthub.io/packages/helm/logicmonitor-helm-charts/argus?modal=values-schema

## Collectorset Controller Configuration

Manages the lifecycle of collector pods.

For full configuration options, see:
https://artifacthub.io/packages/helm/logicmonitor-helm-charts/collectorset-controller?modal=values-schema

## Kube State Metrics Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `kube-state-metrics.enabled` | boolean | `true` | Enable KSM deployment |
| `kube-state-metrics.replicas` | integer | `1` | Number of KSM pod replicas |
| `kube-state-metrics.selfMonitor.enabled` | boolean | `true` | Enable self-monitoring |
| `kube-state-metrics.selfMonitor.telemetryPort` | integer | `8081` | Telemetry port |
| `kube-state-metrics.collectors` | array | See below | List of enabled collectors |

Default collectors:
- daemonsets
- replicasets
- statefulsets
- persistentvolumes
- persistentvolumeclaims
- endpoints
- cronjobs
- jobs
- pods
- nodes
- deployments
- services
- poddisruptionbudgets

For full KSM configuration options, see:
https://artifacthub.io/packages/helm/prometheus-community/kube-state-metrics?modal=values

## LM Logs Configuration

Log forwarding to LogicMonitor (disabled by default).

For full configuration options, see:
https://artifacthub.io/packages/helm/logicmonitor-helm-charts/lm-logs?modal=values-schema

## LMOTEL Configuration

OpenTelemetry integration (disabled by default).

For full configuration options, see:
https://artifacthub.io/packages/helm/logicmonitor-helm-charts/lmotel

## Subcharts

| Chart | Version | Repository |
|-------|---------|------------|
| argus | 13.2.0 | https://logicmonitor.github.io/helm-charts |
| collectorset-controller | 11.2.0 | https://logicmonitor.github.io/helm-charts |
| kube-state-metrics | 5.36.0 | https://prometheus-community.github.io/helm-charts |
| lm-logs | 0.7.0 | https://logicmonitor.github.io/helm-charts |
| lmotel | 1.9.0 | https://logicmonitor.github.io/helm-charts |
| lmutil | 0.1.9 | https://logicmonitor.github.io/helm-charts |

## Example: Minimal Configuration

```yaml
apiVersion: monitoring.logicmonitor.com/v1alpha1
kind: LMContainer
metadata:
  name: lm-monitoring
  namespace: logicmonitor
spec:
  global:
    userDefinedSecret: "lm-credentials"
  argus:
    clusterName: "my-openshift-cluster"
```

## Example: Full Configuration

```yaml
apiVersion: monitoring.logicmonitor.com/v1alpha1
kind: LMContainer
metadata:
  name: lm-monitoring
  namespace: logicmonitor
spec:
  global:
    userDefinedSecret: "lm-credentials"
    companyDomain: "logicmonitor.com"
  argus:
    enabled: true
    clusterName: "prod-openshift-east"
    clusterTreeParentID: 1
  collectorset-controller:
    enabled: true
  kube-state-metrics:
    enabled: true
    replicas: 2
  lm-logs:
    enabled: false
  lmotel:
    enabled: false
```
