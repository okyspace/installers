APP=kserve
CHART=./charts/kserve/kserve-resources
OVERRIDE=override-controller.yaml
NAMESPACE=kserve
CONTEXT=""

helm upgrade \
	--install \
	"${APP}" \
	"${CHART}" \
	--values $OVERRIDE \
	--namespace $NAMESPACE \
	--create-namespace
