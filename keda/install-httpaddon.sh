APP=keda-add-ons-http
NAMESPACE="keda"
CHART="./charts/keda-add-ons-http"
OVERRIDE="override-httpaddon.yaml"

# install keda http add-on (external scaler for HTTP workloads)
# Same "keda" namespace as core keda (installers/keda/install.sh) - not a
# hard requirement, but this add-on registers itself as an external scaler
# against the keda operator, so co-locating keeps that pairing obvious.
helm upgrade --install \
    $APP \
    $CHART \
    --namespace $NAMESPACE \
    --values $OVERRIDE \
    --create-namespace
