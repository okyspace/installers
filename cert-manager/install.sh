APP=cert-manager
NAMESPACE=cert-manager
CHART=./cert-manager-v1.20.1.tgz
CONTEXT=
OVERRIDE=override.yaml

helm upgrade \
    --install \
    $APP \
    $CHART \
    --values $OVERRIDE \
    --namespace $NAMESPACE \
    --create-namespace
