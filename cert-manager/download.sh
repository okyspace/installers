#!/bin/bash
set -e

cd "$(dirname "$0")"

CHART_REPO=https://charts.jetstack.io
CHART_NAME=cert-manager

VERSION=${1:-v1.20.1}

echo "Adding jetstack Helm repo..."
helm repo add jetstack "${CHART_REPO}" --force-update
helm repo update jetstack

echo "Pulling ${CHART_NAME} chart (${VERSION})..."
rm -f ${CHART_NAME}-*.tgz
helm pull jetstack/${CHART_NAME} --version "${VERSION}"

CHART_TAR=$(ls ${CHART_NAME}-*.tgz 2>/dev/null | head -n 1)
if [ -z "$CHART_TAR" ]; then
    echo "Error: Failed to download ${CHART_NAME} helm chart."
    exit 1
fi
echo "Downloaded ${CHART_TAR}"

echo "Extracting images from ${CHART_NAME}..."
rm -rf "${CHART_NAME}"
tar xf "${CHART_TAR}"
IMAGES=$(helm template "${CHART_NAME}" "./${CHART_NAME}" \
    --set crds.enabled=true \
    | grep "image:" \
    | grep -v '""' \
    | grep -v "repository:" \
    | awk '{print $2}' \
    | sed 's/"//g' \
    | sort | uniq)
rm -rf "${CHART_NAME}"

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
    echo "No images found in ${CHART_NAME}."
fi

echo "Done!"
