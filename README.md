# LogicMonitor OpenShift Operator

A Kubernetes operator for deploying and managing LogicMonitor Container Monitoring on OpenShift clusters. This operator wraps the `lm-container` Helm chart and provides native integration with OpenShift's Operator Lifecycle Manager (OLM).

## Overview

The LogicMonitor OpenShift Operator automates the deployment and lifecycle management of the LogicMonitor Container Monitoring stack, including:

- **Argus**: Kubernetes resource discovery and monitoring agent
- **Collectorset Controller**: Manages LogicMonitor collector pod lifecycle
- **Collectors**: LogicMonitor data collection pods
- **Kube State Metrics**: Kubernetes object metrics exporter

## Architecture

- Artifact Hub for LogicMonitor Helm Charts: https://artifacthub.io/packages/search?repo=logicmonitor-helm-charts&sort=relevance&page=1

```
┌─────────────────────────────────────────────────────────────┐
│                     OpenShift Cluster                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │                 logicmonitor namespace               │    │
│  ├─────────────────────────────────────────────────────┤    │
│  │  ┌──────────────┐    ┌─────────────────────────┐    │    │
│  │  │  Operator    │───▶│  LMContainer CR         │    │    │
│  │  │  Controller  │    │  (Custom Resource)      │    │    │
│  │  └──────────────┘    └─────────────────────────┘    │    │
│  │         │                       │                    │    │
│  │         ▼                       ▼                    │    │
│  │  ┌──────────────────────────────────────────────┐   │    │
│  │  │           Helm Release (lm-container)         │   │    │
│  │  ├──────────────────────────────────────────────┤   │    │
│  │  │  ┌───────┐  ┌───────────────┐  ┌─────────┐   │   │    │
│  │  │  │ Argus │  │ Collectorset  │  │   KSM   │   │   │    │
│  │  │  │       │  │  Controller   │  │         │   │   │    │
│  │  │  └───────┘  └───────────────┘  └─────────┘   │   │    │
│  │  │                    │                          │   │    │
│  │  │            ┌───────┴───────┐                  │   │    │
│  │  │            ▼               ▼                  │   │    │
│  │  │      ┌──────────┐   ┌──────────┐              │   │    │
│  │  │      │Collector │   │Collector │              │   │    │
│  │  │      │ Pod 1    │   │ Pod N    │              │   │    │
│  │  │      └──────────┘   └──────────┘              │   │    │
│  │  └──────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                   ┌─────────────────────┐
                   │   LogicMonitor      │
                   │   SaaS Platform     │
                   └─────────────────────┘
```

## Prerequisites

- OpenShift 4.12 or later (tested on ROSA and ARO)
- LogicMonitor account with Container Monitoring license
- LMv1 API credentials with appropriate permissions
- `oc` CLI configured with cluster-admin access

## Installation

### Option 1: OperatorHub (OLM)

Once published to OperatorHub, install via the OpenShift Console:

1. Navigate to Operators > OperatorHub
2. Search for "LogicMonitor"
3. Click Install and follow the prompts

### Option 2: Manual Installation

#### Step 1: Create Namespace

```bash
oc create namespace logicmonitor
```

#### Step 2: Apply CRD

```bash
oc apply -f https://raw.githubusercontent.com/ryanmat/logicmonitor-openshift-operator/main/config/crd/bases/monitoring.logicmonitor.com_lmcontainers.yaml
```

#### Step 3: Create Credentials Secret

```bash
oc create secret generic lm-credentials \
  --namespace logicmonitor \
  --from-literal=accessID=YOUR_ACCESS_ID \
  --from-literal=accessKey=YOUR_ACCESS_KEY \
  --from-literal=account=YOUR_ACCOUNT_NAME
```

#### Step 4: Deploy Operator

```bash
oc apply -f https://raw.githubusercontent.com/ryanmat/logicmonitor-openshift-operator/main/config/default/manager.yaml
```

#### Step 5: Create LMContainer Resource

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
    enabled: true
    clusterName: "my-openshift-cluster"
    clusterTreeParentID: 1
    collector:
      replicas: 2
      size: "medium"
  collectorset-controller:
    enabled: true
  kube-state-metrics:
    enabled: true
```

Apply with:

```bash
oc apply -f lmcontainer.yaml
```

## Configuration Reference

### LMContainer Spec

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `global.userDefinedSecret` | string | Yes | Name of Secret containing LM credentials |
| `argus.enabled` | boolean | No | Enable Argus discovery agent (default: true) |
| `argus.clusterName` | string | Yes | Unique cluster name in LogicMonitor |
| `argus.clusterTreeParentID` | integer | No | Parent resource group ID (default: 1) |
| `argus.collector.replicas` | integer | No | Number of collector pods (default: 1) |
| `argus.collector.size` | string | No | Collector size: nano, small, medium, large |
| `collectorset-controller.enabled` | boolean | No | Enable CSC (default: true) |
| `kube-state-metrics.enabled` | boolean | No | Enable KSM (default: true) |
| `lm-logs.enabled` | boolean | No | Enable LM Logs (default: false) |

### Collector Sizing Guide

| Size | CPU Request | Memory Request | Recommended Use |
|------|-------------|----------------|-----------------|
| nano | 200m | 256Mi | Small clusters (<50 pods) |
| small | 500m | 512Mi | Medium clusters (50-200 pods) |
| medium | 1000m | 1Gi | Large clusters (200-500 pods) |
| large | 2000m | 2Gi | Enterprise clusters (500+ pods) |

### Enabling Event and Pod Logs

```yaml
spec:
  argus:
    lm:
      lmlogs:
        k8sevent:
          enable: true
        k8spodlog:
          enable: true
```

### Full Configuration Example

```yaml
apiVersion: monitoring.logicmonitor.com/v1alpha1
kind: LMContainer
metadata:
  name: lm-monitoring-full
  namespace: logicmonitor
  labels:
    app.kubernetes.io/name: lmcontainer
    app.kubernetes.io/part-of: logicmonitor-operator
spec:
  global:
    userDefinedSecret: "lm-credentials"
  argus:
    enabled: true
    clusterName: "prod-openshift-east"
    clusterTreeParentID: 1
    resourceContainerID: 1
    deleteDevices: true
    disableAlerting: false
    loglevel: "info"
    collector:
      replicas: 2
      size: "large"
      useEA: false
    lm:
      lmlogs:
        k8sevent:
          enable: true
        k8spodlog:
          enable: true
  collectorset-controller:
    enabled: true
  kube-state-metrics:
    enabled: true
    replicas: 1
    collectors:
      - daemonsets
      - deployments
      - endpoints
      - nodes
      - pods
      - services
      - statefulsets
      - persistentvolumes
      - persistentvolumeclaims
  lm-logs:
    enabled: false
  lmotel:
    enabled: false
```

## Credentials Secret Format

The operator expects a Secret with the following keys:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: lm-credentials
  namespace: logicmonitor
type: Opaque
stringData:
  account: "company"           # LogicMonitor account subdomain
  accessID: "ABC123..."        # LMv1 API Access ID
  accessKey: "xyz789..."       # LMv1 API Access Key
```

Validate your secret before deployment:

```bash
./scripts/validate-secret.sh logicmonitor lm-credentials
```

## Verification

Check operator status:

```bash
oc get pods -n logicmonitor
oc get lmcontainer -n logicmonitor
```

Expected output:

```
NAME                                                    READY   STATUS
lm-container-argus-0                                    1/1     Running
lm-container-argus-1                                    1/1     Running
lm-container-collectorset-controller-xxxxx              1/1     Running
lm-container-kube-state-metrics-xxxxx                   1/1     Running
```

Check Helm release:

```bash
helm list -n logicmonitor
```

## Troubleshooting

### Pods Not Starting

1. Check credentials secret exists and has correct keys:
   ```bash
   oc get secret lm-credentials -n logicmonitor -o yaml
   ```

2. Verify SCC is applied:
   ```bash
   oc get scc logicmonitor-scc
   ```

3. Check operator logs:
   ```bash
   oc logs -f deployment/logicmonitor-openshift-operator-controller-manager -n logicmonitor
   ```

### Collectors Not Registering

1. Verify network connectivity to LogicMonitor:
   ```bash
   oc exec -it lm-container-argus-0 -n logicmonitor -- curl -I https://YOUR_ACCOUNT.logicmonitor.com
   ```

2. Check Argus logs:
   ```bash
   oc logs -f lm-container-argus-0 -n logicmonitor
   ```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Pods pending | SCC not applied | Apply logicmonitor-scc to service accounts |
| Auth errors | Invalid credentials | Verify accessID/accessKey in secret |
| No data in LM | Firewall blocking | Allow outbound HTTPS to *.logicmonitor.com |

## Development

### Building from Source

```bash
# Build operator image
make docker-build IMG=your-registry/logicmonitor-operator:dev

# Push to registry
make docker-push IMG=your-registry/logicmonitor-operator:dev

# Deploy to cluster
make deploy IMG=your-registry/logicmonitor-operator:dev
```

### Running Locally

```bash
# Install CRDs
make install

# Run operator locally
make run
```

### Building OLM Bundle

```bash
# Generate bundle
make bundle VERSION=0.1.0

# Build bundle image
make bundle-build BUNDLE_IMG=your-registry/logicmonitor-operator-bundle:v0.1.0

# Build catalog
make catalog-build CATALOG_IMG=your-registry/logicmonitor-operator-catalog:v0.1.0
```

## Project Structure

```
.
├── bundle/                    # OLM bundle manifests
│   ├── manifests/            # CSV and CRDs for OLM
│   └── metadata/             # Bundle annotations
├── config/
│   ├── crd/                  # Custom Resource Definitions
│   ├── manager/              # Operator deployment manifests
│   ├── rbac/                 # RBAC configuration
│   └── samples/              # Example CRs
├── helm-charts/
│   └── lm-container/         # Embedded Helm chart (v11.2.0)
├── scripts/                  # Utility scripts
└── docs/                     # Documentation
```

## Version Compatibility

| Operator Version | Helm Chart Version | OpenShift Version |
|-----------------|-------------------|-------------------|
| 0.1.x | lm-container 11.x | 4.12+ |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test
4. Submit a pull request

## License

Apache License 2.0

## Support

- Documentation: https://www.logicmonitor.com/support/lm-container
- Issues: https://github.com/ryanmat/logicmonitor-openshift-operator/issues
- Artifact Hub: https://artifacthub.io/packages/search?repo=logicmonitor-helm-charts&sort=relevance&page=1
