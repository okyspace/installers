APP=kserve-crd
CHART=./kserve-crd
NAMESPACE=kserve
CONTEXT=""

helm upgrade \
	--install \
	"${APP}" \
	"${CHART}" \
	--namespace $NAMESPACE \
	--create-namespace
