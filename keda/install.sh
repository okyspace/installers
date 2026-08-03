APP=keda
NAMESPACE="keda"
CHART="./charts/keda"
OVERRIDE="override.yaml"
VERSION="2.20.2"

# install keda operator
helm upgrade --install \
    $APP \
    $CHART \
    --namespace $NAMESPACE \
    --values $OVERRIDE \
    --create-namespace \
    --skip-crds

# install crds
kubectl apply --server-side -f "keda-${VERSION}-crds.yaml"
