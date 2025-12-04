#!/bin/bash
# Description: Validates LogicMonitor credentials Secret before deployment.
# Description: Checks for Secret existence and required keys.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Required keys in the Secret
REQUIRED_KEYS=("account" "accessID" "accessKey")

# Usage function
usage() {
    echo "Usage: $0 <namespace> <secret-name>"
    echo ""
    echo "Validates that a LogicMonitor credentials Secret exists and contains required keys."
    echo ""
    echo "Arguments:"
    echo "  namespace    Kubernetes namespace where the Secret exists"
    echo "  secret-name  Name of the Secret to validate"
    echo ""
    echo "Example:"
    echo "  $0 logicmonitor lm-credentials"
    exit 1
}

# Check arguments
if [ $# -ne 2 ]; then
    usage
fi

NAMESPACE=$1
SECRET_NAME=$2

echo "Validating Secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist${NC}"
    exit 1
fi

# Check if Secret exists
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}Error: Secret '$SECRET_NAME' not found in namespace '$NAMESPACE'${NC}"
    echo ""
    echo "To create the Secret, run:"
    echo ""
    echo "  kubectl create secret generic $SECRET_NAME \\"
    echo "    --namespace $NAMESPACE \\"
    echo "    --from-literal=account=YOUR_ACCOUNT \\"
    echo "    --from-literal=accessID=YOUR_ACCESS_ID \\"
    echo "    --from-literal=accessKey=YOUR_ACCESS_KEY"
    exit 1
fi

echo -e "${GREEN}Secret '$SECRET_NAME' exists${NC}"

# Get Secret keys
SECRET_KEYS=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | grep -oE '"[^"]+":' | tr -d '":')

# Check for required keys
MISSING_KEYS=()
for key in "${REQUIRED_KEYS[@]}"; do
    if ! echo "$SECRET_KEYS" | grep -q "^${key}$"; then
        MISSING_KEYS+=("$key")
    fi
done

if [ ${#MISSING_KEYS[@]} -gt 0 ]; then
    echo -e "${RED}Error: Secret is missing required keys: ${MISSING_KEYS[*]}${NC}"
    echo ""
    echo "Required keys: ${REQUIRED_KEYS[*]}"
    echo ""
    echo "To update the Secret with missing keys, delete and recreate it:"
    echo ""
    echo "  kubectl delete secret $SECRET_NAME -n $NAMESPACE"
    echo "  kubectl create secret generic $SECRET_NAME \\"
    echo "    --namespace $NAMESPACE \\"
    echo "    --from-literal=account=YOUR_ACCOUNT \\"
    echo "    --from-literal=accessID=YOUR_ACCESS_ID \\"
    echo "    --from-literal=accessKey=YOUR_ACCESS_KEY"
    exit 1
fi

echo -e "${GREEN}All required keys present: ${REQUIRED_KEYS[*]}${NC}"

# Check for empty values
EMPTY_KEYS=()
for key in "${REQUIRED_KEYS[@]}"; do
    VALUE=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data.$key}" | base64 -d 2>/dev/null || echo "")
    if [ -z "$VALUE" ]; then
        EMPTY_KEYS+=("$key")
    fi
done

if [ ${#EMPTY_KEYS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Warning: The following keys have empty values: ${EMPTY_KEYS[*]}${NC}"
    echo "Ensure these are set to valid values before deploying."
fi

# Check for optional keys
OPTIONAL_KEYS=("etcdDiscoveryToken" "proxyURL" "proxyUser" "proxyPass")
FOUND_OPTIONAL=()
for key in "${OPTIONAL_KEYS[@]}"; do
    if echo "$SECRET_KEYS" | grep -q "^${key}$"; then
        FOUND_OPTIONAL+=("$key")
    fi
done

if [ ${#FOUND_OPTIONAL[@]} -gt 0 ]; then
    echo -e "${GREEN}Optional keys found: ${FOUND_OPTIONAL[*]}${NC}"
fi

echo ""
echo -e "${GREEN}Validation successful!${NC}"
echo ""
echo "You can reference this Secret in your LMContainer CR:"
echo ""
echo "  spec:"
echo "    global:"
echo "      userDefinedSecret: \"$SECRET_NAME\""
exit 0
