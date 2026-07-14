#!/usr/bin/env bash

# download.sh - Fetch the kserve-crd chart from GitHub source and the kserve
# chart from the OCI registry.
# Usage: ./download.sh [VERSION] [CRD_REF]
#        ./download.sh --list-versions [CHART_NAME]
# Example: ./download.sh v0.17.1 master
# Example: ./download.sh --list-versions kserve-resources

set -euo pipefail

CHART_ROOT="$(dirname "${BASH_SOURCE[0]}")/charts"
REPO="kserve/kserve"
HELM_REGISTRY_CONFIG="${HOME}/.config/helm/registry/config.json"

# Resolve ghcr.io credentials from GHCR_USER/GHCR_TOKEN, falling back to
# whatever `helm registry login ghcr.io` already cached.
ghcr_credentials() {
  if [[ -n "${GHCR_USER:-}" && -n "${GHCR_TOKEN:-}" ]]; then
    echo "${GHCR_USER}:${GHCR_TOKEN}"
    return
  fi
  if [[ -f "${HELM_REGISTRY_CONFIG}" ]]; then
    local auth
    auth="$(jq -r '.auths["ghcr.io"].auth // empty' "${HELM_REGISTRY_CONFIG}")"
    if [[ -n "${auth}" ]]; then
      echo "${auth}" | base64 -d
      return
    fi
  fi
  echo "No GHCR credentials found. Run 'helm registry login ghcr.io' first, or set GHCR_USER/GHCR_TOKEN." >&2
  return 1
}

# List published tags for a chart under ghcr.io/kserve/charts/<name>.
list_versions() {
  local chart="${1:-kserve-resources}"
  local creds token
  creds="$(ghcr_credentials)" || exit 1
  token="$(curl -s -u "${creds}" \
    "https://ghcr.io/token?scope=repository:kserve/charts/${chart}:pull&service=ghcr.io" \
    | jq -r .token)"
  curl -s -H "Authorization: Bearer ${token}" \
    "https://ghcr.io/v2/kserve/charts/${chart}/tags/list" | jq -r '.tags[]' | sort -V
}

# kserve-crd isn't published as a release asset or to the OCI registry, so pull
# the chart directory straight out of the repo at $CRD_REF.
download_crd_chart() {
  local dest="${CHART_ROOT}/kserve-crd"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN

  echo "Downloading kserve-crd chart from ${REPO}@${CRD_REF}..."
  curl -L -f "https://github.com/${REPO}/archive/${CRD_REF}.tar.gz" -o "${tmp}/repo.tar.gz"
  tar -xzf "${tmp}/repo.tar.gz" -C "${tmp}"

  local src
  src="$(find "${tmp}" -maxdepth 1 -type d -name 'kserve-*')/charts/kserve-crd"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  cp -r "${src}/." "${dest}/"
  echo "kserve-crd chart saved to ${dest}"
}

# kserve resources chart, pulled directly from the OCI registry (no repo add needed).
download_kserve_chart() {
  local dest="${CHART_ROOT}/kserve"
  echo "Pulling kserve-resources chart version ${VERSION} from OCI registry..."
  rm -rf "${dest}"
  helm pull "oci://ghcr.io/kserve/charts/kserve-resources" \
    --version "${VERSION}" \
    --untar \
    --untardir "${dest}"
  echo "kserve-resources chart extracted to ${dest}"
}

# Default ClusterServingRuntimes (huggingface, sklearn, xgboost, lightgbm, ...).
# Without this, InferenceServices fail with "No runtime found to support
# specified framework/version" — kserve-resources only installs the controller,
# not any runtimes.
download_runtime_configs_chart() {
  local dest="${CHART_ROOT}/kserve-runtime-configs"
  echo "Pulling kserve-runtime-configs chart version ${VERSION} from OCI registry..."
  rm -rf "${dest}"
  helm pull "oci://ghcr.io/kserve/charts/kserve-runtime-configs" \
    --version "${VERSION}" \
    --untar \
    --untardir "${dest}"
  echo "kserve-runtime-configs chart extracted to ${dest}"
}

IMAGE_ROOT="$(dirname "${BASH_SOURCE[0]}")/images"

# Pull + `docker save` every image below into its own tar under images/, for
# air-gapped/on-prem transfer (same purpose as cert-manager-images.tar /
# keda-images.tar in the sibling installer dirs). Defined inside the function
# (not as top-level arrays) so ${VERSION} is already set by the time this runs.
download_images() {
  # Controller-side images (kserve-resources); tag defaults to kserve.version
  # (see charts/kserve/kserve-resources/values.yaml) except kube-rbac-proxy,
  # which is pinned independently upstream.
  local controller_images=(
    "kserve/kserve-controller:${VERSION}"
    "kserve/agent:${VERSION}"
    "kserve/router:${VERSION}"
    "kserve/storage-initializer:${VERSION}"
    "quay.io/brancz/kube-rbac-proxy:v0.18.0"
  )

  # Images for the runtimes currently enabled in override-runtimes.yaml
  # (huggingfaceserver, huggingfaceserver-multinode, tritonserver). Keep this
  # list in sync if you enable/disable runtimes there.
  local runtime_images=(
    "kserve/huggingfaceserver:${VERSION}"
    "kserve/huggingfaceserver:${VERSION}-gpu"
    "nvcr.io/nvidia/tritonserver:23.05-py3"
  )

  mkdir -p "${IMAGE_ROOT}"
  local image name dest
  for image in "${controller_images[@]}" "${runtime_images[@]}"; do
    name="$(echo "${image}" | sed -E 's#.*/##; s#:#-#')"
    dest="${IMAGE_ROOT}/${name}.tar"
    echo "Pulling ${image}..."
    docker pull "${image}"
    echo "Saving ${image} -> ${dest}"
    docker save -o "${dest}" "${image}"
  done
  echo "All images saved to ${IMAGE_ROOT}"
}

if [[ "${1:-}" == "--list-versions" ]]; then
  list_versions "${2:-kserve-resources}"
  exit 0
fi

VERSION="${1:-v0.19.0}"
CRD_REF="${2:-master}"

mkdir -p "${CHART_ROOT}"

download_crd_chart
download_kserve_chart
download_runtime_configs_chart
download_images

echo "All charts and images downloaded successfully."
