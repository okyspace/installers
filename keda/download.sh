#!/bin/bash
set -e

cd "$(dirname "$0")"

REPO_ALIAS=kedacore
REPO_URL=https://kedacore.github.io/charts
CHART_NAME=keda

VERSION=${1:-}

echo "Adding kedacore Helm repo..."
helm repo add "${REPO_ALIAS}" "${REPO_URL}" --force-update
helm repo update "${REPO_ALIAS}"

# Resolve version — use latest if not specified
if [ -n "$VERSION" ]; then
    VERSION_FLAG="--version ${VERSION}"
    RESOLVED_VERSION="${VERSION}"
    echo "Pulling KEDA helm chart version ${VERSION}..."
else
    echo "Pulling latest KEDA helm chart..."
    VERSION_FLAG=""
    RESOLVED_VERSION=$(helm search repo "${REPO_ALIAS}/${CHART_NAME}" --output json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['version'])")
    echo "Latest version: ${RESOLVED_VERSION}"
fi

# Pull chart and extract into charts/ (install.sh references ./charts/keda)
echo "Downloading chart into charts/${CHART_NAME}..."
rm -rf "charts/${CHART_NAME}"
helm pull "${REPO_ALIAS}/${CHART_NAME}" ${VERSION_FLAG} \
    --untar --untardir charts
echo "Chart extracted to charts/${CHART_NAME}"

# Download the matching standalone CRD manifest
# CRD file naming: keda-{VERSION}-crds.yaml (no leading 'v')
CRD_VERSION="${RESOLVED_VERSION#v}"
CRD_FILE="keda-${CRD_VERSION}-crds.yaml"
CRD_URL="https://github.com/kedacore/keda/releases/download/v${CRD_VERSION}/${CRD_FILE}"
echo "Downloading CRD manifest (${CRD_FILE})..."
curl -fsSL "${CRD_URL}" -o "${CRD_FILE}"
echo "Downloaded ${CRD_FILE}"

# Extract images from the helm chart
echo "Extracting images from chart..."
IMAGES=$(helm template "${CHART_NAME}" "charts/${CHART_NAME}" \
    | grep "image:" \
    | grep -v '""' \
    | grep -v "repository:" \
    | awk '{print $2}' \
    | sed 's/"//g' \
    | sort | uniq)

if [ -n "$IMAGES" ]; then
    echo "Found images:"
    echo "$IMAGES"
    for IMAGE in $IMAGES; do
        echo "Pulling ${IMAGE}..."
        docker pull "$IMAGE"
    done
    echo "Saving images to ${CHART_NAME}-images.tar..."
    docker save $IMAGES -o "${CHART_NAME}-images.tar"
else
    echo "No images found in chart."
fi

echo ""
echo "Update install.sh CRD line to:"
echo "  kubectl apply --server-side -f ./${CRD_FILE}"
echo ""
echo "Done!"
