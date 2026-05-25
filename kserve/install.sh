APP=kserve
CHART=./kserve
OVERRIDE=override.yaml
NAMESPACE=kserve
CONTEXT=""

helm upgrade \
	--install \
	"${APP}" \
	"${CHART}" \
	--values $OVERRIDE \
	--namespace $NAMESPACE \
	--create-namespace
