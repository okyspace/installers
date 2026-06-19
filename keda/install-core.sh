APP=keda
NAMESPACE="keda"
CHART="./charts/keda"
OVERRIDE="override-core.yaml"

# install keda core
helm upgrade --install \
    $APP \
    $CHART \
    --namespace $NAMESPACE \
    --values $OVERRIDE \
    --create-namespace \
    --skip-crds

# install crds
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.19.0/keda-2.19.0-crds.yaml
