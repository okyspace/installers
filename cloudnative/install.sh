#!/bin/bash
set -e

cd "$(dirname "$0")"

OPERATOR_APP=cloudnative-pg
OPERATOR_NAMESPACE=cnpg-system
OPERATOR_CHART=./cloudnative-pg-0.28.2.tgz
OPERATOR_OVERRIDE=override-operator.yaml

CLUSTER_CHART=./cluster-0.6.1.tgz
CLUSTER_OVERRIDE=override-cluster.yaml

usage() {
    echo "Usage:"
    echo "  $0 all <namespace>        # install operator + cluster into <namespace>"
    echo "  $0 operator               # install operator only"
    echo "  $0 cluster <namespace>    # install cluster into <namespace>"
    exit 1
}

install_operator() {
    echo "Installing CloudNativePG operator in namespace '${OPERATOR_NAMESPACE}'..."
    helm upgrade \
        --install \
        $OPERATOR_APP \
        $OPERATOR_CHART \
        --values $OPERATOR_OVERRIDE \
        --namespace $OPERATOR_NAMESPACE \
        --create-namespace
}

install_cluster() {
    local NS=$1
    if [ -z "$NS" ]; then
        echo "Error: namespace required for cluster install."
        usage
    fi
    echo "Installing CloudNativePG cluster in namespace '${NS}'..."
    helm upgrade \
        --install \
        postgres \
        $CLUSTER_CHART \
        --values $CLUSTER_OVERRIDE \
        --namespace "$NS" \
        --create-namespace
}

MODE=${1:-}

if [ -z "$MODE" ]; then
    echo "Error: mode required."
    usage
fi

case "$MODE" in
    operator)
        install_operator
        ;;
    cluster)
        install_cluster "${2:-}"
        ;;
    all)
        install_cluster "${2:-}"
        install_operator
        ;;
    *)
        usage
        ;;
esac

echo "Done!"
