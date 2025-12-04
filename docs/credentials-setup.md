# Description: Guide for configuring LogicMonitor API credentials.
# Description: Covers Secret creation, required keys, and security practices.

# LogicMonitor Credentials Setup

This guide explains how to configure LogicMonitor API credentials for the LMContainer operator.

## Overview

The LMContainer operator requires LogicMonitor API credentials to:
- Register the cluster with LogicMonitor
- Create and manage collector pods
- Report metrics and resource information

Credentials should be stored in a Kubernetes Secret, not inline in the LMContainer CR.

## Creating API Credentials in LogicMonitor

1. Log in to your LogicMonitor portal
2. Navigate to **Settings > Users and Roles > API Tokens**
3. Click **Add** to create a new API token
4. Configure the token:
   - **Name**: Descriptive name (e.g., "openshift-prod-operator")
   - **User**: Select a user with appropriate permissions
   - **Permissions**: The token needs permissions to:
     - Create and manage devices
     - Create and manage collectors
     - Create and manage resource groups
5. Save and copy both the **Access ID** and **Access Key**

## Creating the Kubernetes Secret

### Option 1: Using kubectl

```bash
kubectl create namespace logicmonitor

kubectl create secret generic lm-credentials \
  --namespace logicmonitor \
  --from-literal=account=YOUR_ACCOUNT_NAME \
  --from-literal=accessID=YOUR_ACCESS_ID \
  --from-literal=accessKey=YOUR_ACCESS_KEY
```

### Option 2: Using a YAML manifest

Create a file named `lm-credentials.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: lm-credentials
  namespace: logicmonitor
type: Opaque
stringData:
  # LogicMonitor account name (subdomain from portal URL)
  # Example: If URL is "acme.logicmonitor.com", use "acme"
  account: "YOUR_ACCOUNT_NAME"

  # API access ID from LogicMonitor
  accessID: "YOUR_ACCESS_ID"

  # API access key from LogicMonitor
  accessKey: "YOUR_ACCESS_KEY"
```

Apply it:

```bash
kubectl apply -f lm-credentials.yaml
```

### Option 3: Using OpenShift CLI

```bash
oc new-project logicmonitor

oc create secret generic lm-credentials \
  --from-literal=account=YOUR_ACCOUNT_NAME \
  --from-literal=accessID=YOUR_ACCESS_ID \
  --from-literal=accessKey=YOUR_ACCESS_KEY
```

## Required Secret Keys

| Key | Required | Description |
|-----|----------|-------------|
| `account` | Yes | LogicMonitor account name (subdomain) |
| `accessID` | Yes | API access ID |
| `accessKey` | Yes | API access key |
| `etcdDiscoveryToken` | No | Token for etcd cluster discovery |
| `proxyURL` | No | Proxy URL if required |
| `proxyUser` | No | Proxy username |
| `proxyPass` | No | Proxy password |

## Referencing the Secret in LMContainer

Reference the Secret in your LMContainer CR using `global.userDefinedSecret`:

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
    clusterName: "my-cluster"
```

The operator passes this Secret name to the Helm chart, which reads the credentials at deployment time.

## Security Best Practices

### 1. Limit Secret Access

Create an RBAC Role that restricts access to the credentials Secret:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: lm-credentials-reader
  namespace: logicmonitor
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["lm-credentials"]
    verbs: ["get"]
```

### 2. Use Separate Namespaces

Deploy the LMContainer in a dedicated namespace to isolate credentials:

```bash
kubectl create namespace logicmonitor
```

### 3. Enable Secret Encryption at Rest

Ensure your cluster has encryption at rest enabled for Secrets. For OpenShift:

```bash
oc get apiserver cluster -o jsonpath='{.spec.encryption}'
```

### 4. Rotate Credentials Regularly

1. Create a new API token in LogicMonitor
2. Update the Secret:
   ```bash
   kubectl create secret generic lm-credentials \
     --namespace logicmonitor \
     --from-literal=account=YOUR_ACCOUNT \
     --from-literal=accessID=NEW_ACCESS_ID \
     --from-literal=accessKey=NEW_ACCESS_KEY \
     --dry-run=client -o yaml | kubectl apply -f -
   ```
3. The operator will use the new credentials on next reconciliation
4. Delete the old API token in LogicMonitor

### 5. Use External Secret Management (Optional)

For production environments, consider using:
- **HashiCorp Vault** with the Vault Secrets Operator
- **AWS Secrets Manager** with External Secrets Operator
- **Azure Key Vault** with the CSI driver

Example with External Secrets Operator:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: lm-credentials
  namespace: logicmonitor
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: lm-credentials
  data:
    - secretKey: account
      remoteRef:
        key: logicmonitor/credentials
        property: account
    - secretKey: accessID
      remoteRef:
        key: logicmonitor/credentials
        property: accessID
    - secretKey: accessKey
      remoteRef:
        key: logicmonitor/credentials
        property: accessKey
```

## Troubleshooting

### Secret Not Found

If the operator reports the Secret is not found:

```bash
# Verify Secret exists
kubectl get secret lm-credentials -n logicmonitor

# Check Secret has required keys
kubectl get secret lm-credentials -n logicmonitor -o jsonpath='{.data}' | jq
```

### Invalid Credentials

If authentication fails:

1. Verify the account name matches your portal subdomain
2. Confirm the API token is active in LogicMonitor
3. Check the token has sufficient permissions
4. Ensure no extra whitespace in Secret values

### Secret in Wrong Namespace

The Secret must be in the same namespace as the LMContainer CR:

```bash
# Check LMContainer namespace
kubectl get lmcontainer -A

# Verify Secret is in same namespace
kubectl get secret lm-credentials -n <lmcontainer-namespace>
```
