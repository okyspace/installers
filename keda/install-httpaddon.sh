APP=keda-http-add-on
NAMESPACE="keda"
CHART="./charts/http-add-on"
OVERRIDE="override-httpaddon.yaml"

# install crds first; download from https://github.com/kedacore/http-add-on/releases
kubectl apply --server-side -f keda-add-ons-http-0.14.0-crds.yaml

# install keda http addon
helm upgrade --install \
    $APP \
    $CHART \
    --namespace $NAMESPACE \
    --values $OVERRIDE \
    --create-namespace \
    --skip-crds
