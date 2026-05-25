#!/bin/bash
set -e

# Change to the directory where this script is located
cd "$(dirname "$0")"

VERSION=${1:-}
if [ -n "$VERSION" ]; then
    VERSION_FLAG="--version $VERSION"
    echo "Pulling CloudNativePG helm charts version $VERSION..."
else
    VERSION_FLAG=""
    echo "Pulling latest CloudNativePG helm charts..."
fi

# Add/update repo
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update cnpg

pull_chart() {
    local CHART_NAME=$1
    local GLOB="${CHART_NAME}-*.tgz"

    rm -f ${GLOB}
    helm pull cnpg/${CHART_NAME} $VERSION_FLAG

    CHART_TAR=$(ls ${GLOB} 2>/dev/null | head -n 1)
    if [ -z "$CHART_TAR" ]; then
        echo "Error: Failed to download ${CHART_NAME} helm chart."
        exit 1
    fi
    echo "Downloaded $CHART_TAR"

    echo "Extracting images from ${CHART_NAME}..."
    rm -rf "${CHART_NAME}"
    tar xf "$CHART_TAR"
    IMAGES=$(helm template "${CHART_NAME}" "./${CHART_NAME}" | grep "image:" | grep -v '""' | grep -v "repository:" | awk '{print $2}' | sed 's/"//g' | sort | uniq)
    rm -rf "${CHART_NAME}"

    if [ -n "$IMAGES" ]; then
        echo "Found images:"
        echo "$IMAGES"
        for IMAGE in $IMAGES; do
            echo "Pulling $IMAGE..."
            docker pull "$IMAGE"
        done
        echo "Saving images to ${CHART_NAME}-images.tar..."
        docker save $IMAGES -o "${CHART_NAME}-images.tar"
    else
        echo "No images found in ${CHART_NAME}."
    fi
}

pull_chart cloudnative-pg
pull_chart cluster

echo "Done!"
