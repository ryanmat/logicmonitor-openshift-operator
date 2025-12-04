#!/bin/bash
# Description: Patches the generated bundle CSV with proper metadata from the base CSV.
# Description: Run this after 'make bundle' to ensure metadata is correctly applied.

set -e

BUNDLE_CSV="bundle/manifests/logicmonitor-openshift-operator.clusterserviceversion.yaml"
BASE_CSV="config/manifests/bases/logicmonitor-openshift-operator.clusterserviceversion.yaml"

if [ ! -f "$BUNDLE_CSV" ]; then
    echo "Error: Bundle CSV not found at $BUNDLE_CSV"
    exit 1
fi

if [ ! -f "$BASE_CSV" ]; then
    echo "Error: Base CSV not found at $BASE_CSV"
    exit 1
fi

echo "Patching bundle CSV with metadata from base CSV..."

# Use yq to extract and apply metadata from base CSV to bundle CSV
# Install yq if not available: brew install yq

if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Install with: brew install yq"
    exit 1
fi

# Extract fields from base CSV and apply to bundle CSV
yq eval-all '
  select(fileIndex == 0).spec.description = select(fileIndex == 1).spec.description |
  select(fileIndex == 0).spec.displayName = select(fileIndex == 1).spec.displayName |
  select(fileIndex == 0).spec.icon = select(fileIndex == 1).spec.icon |
  select(fileIndex == 0).spec.keywords = select(fileIndex == 1).spec.keywords |
  select(fileIndex == 0).spec.links = select(fileIndex == 1).spec.links |
  select(fileIndex == 0).spec.maintainers = select(fileIndex == 1).spec.maintainers |
  select(fileIndex == 0).spec.provider = select(fileIndex == 1).spec.provider |
  select(fileIndex == 0).spec.minKubeVersion = select(fileIndex == 1).spec.minKubeVersion |
  select(fileIndex == 0).spec.installModes = select(fileIndex == 1).spec.installModes |
  select(fileIndex == 0)
' "$BUNDLE_CSV" "$BASE_CSV" > "${BUNDLE_CSV}.tmp"

mv "${BUNDLE_CSV}.tmp" "$BUNDLE_CSV"

echo "Bundle CSV patched successfully."
echo "Run 'operator-sdk bundle validate ./bundle' to verify."
