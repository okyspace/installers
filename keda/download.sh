#!/bin/bash
set -e

cd "$(dirname "$0")"

# Usage: ./download.sh [KEDA_VERSION] [HTTP_ADDON_VERSION]
# Each defaults to latest if omitted. Separate args because keda and
# keda-add-ons-http are independently-versioned projects (e.g. keda 2.20.1
# vs keda-add-ons-http 0.15.0) - a single shared version arg would try to
# pull the http add-on at keda's version number and fail outright.
# Example: ./download.sh 2.20.1 0.15.0

REPO_ALIAS=kedacore
REPO_URL=https://kedacore.github.io/charts

KEDA_VERSION=${1:-}
HTTP_ADDON_VERSION=${2:-}

echo "Adding kedacore Helm repo..."
helm repo add "${REPO_ALIAS}" "${REPO_URL}" --force-update
helm repo update "${REPO_ALIAS}"

# Resolves the latest published version for an exact chart name.
# `helm search repo <name>` does substring matching, not exact matching -
# searching "keda" also matches "keda-add-ons-http", so this filters by
# exact name rather than trusting result order/index [0].
latest_version() {
    local chart_name="$1"
    helm search repo "${REPO_ALIAS}" --output json \
        | python3 -c "
import sys, json
entries = json.load(sys.stdin)
for e in entries:
    if e['name'] == '${REPO_ALIAS}/${chart_name}':
        print(e['version'])
        break
else:
    sys.exit('no exact match for ${REPO_ALIAS}/${chart_name}')
"
}

# Pulls one chart into charts/<name>, downloads its images into
# <name>-images.tar. Core keda also gets its standalone CRD manifest (a
# separate GitHub release asset); keda-add-ons-http bundles its CRDs inline
# in the chart instead (gated by its own crds.install value), so it has no
# equivalent manifest to fetch.
download_chart() {
    local CHART_NAME="$1"
    local REQUESTED_VERSION="$2"

    local VERSION_FLAG RESOLVED_VERSION
    if [ -n "${REQUESTED_VERSION}" ]; then
        VERSION_FLAG="--version ${REQUESTED_VERSION}"
        RESOLVED_VERSION="${REQUESTED_VERSION}"
        echo "Pulling ${CHART_NAME} helm chart version ${REQUESTED_VERSION}..."
    else
        echo "Resolving latest ${CHART_NAME} helm chart version..."
        RESOLVED_VERSION="$(latest_version "${CHART_NAME}")"
        VERSION_FLAG=""
        echo "Latest version: ${RESOLVED_VERSION}"
    fi

    # Pull chart and extract into charts/ (install.sh references ./charts/<name>)
    echo "Downloading chart into charts/${CHART_NAME}..."
    rm -rf "charts/${CHART_NAME}"
    helm pull "${REPO_ALIAS}/${CHART_NAME}" ${VERSION_FLAG} \
        --untar --untardir charts
    echo "Chart extracted to charts/${CHART_NAME}"

    if [ "${CHART_NAME}" = "keda" ]; then
        # Download the matching standalone CRD manifest
        # CRD file naming: keda-{VERSION}-crds.yaml (no leading 'v')
        local CRD_VERSION="${RESOLVED_VERSION#v}"
        local CRD_FILE="keda-${CRD_VERSION}-crds.yaml"
        local CRD_URL="https://github.com/kedacore/keda/releases/download/v${CRD_VERSION}/${CRD_FILE}"
        echo "Downloading CRD manifest (${CRD_FILE})..."
        curl -fsSL "${CRD_URL}" -o "${CRD_FILE}"
        echo "Downloaded ${CRD_FILE}"
    fi

    # Extract images from the helm chart
    echo "Extracting images from ${CHART_NAME} chart..."
    local IMAGES
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
        echo "No images found in ${CHART_NAME} chart."
    fi
}

download_chart keda "${KEDA_VERSION}"
download_chart keda-add-ons-http "${HTTP_ADDON_VERSION}"

echo ""
echo "Update install.sh CRD line to:"
echo "  kubectl apply --server-side -f ./keda-*-crds.yaml"
echo ""
echo "Done!"
