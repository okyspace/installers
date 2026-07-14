APP=kserve-runtime-configs
CHART=./charts/kserve-runtime-configs/kserve-runtime-configs
OVERRIDE=override-runtimes.yaml
NAMESPACE=kserve
CONTEXT=""

helm upgrade \
	--install \
	"${APP}" \
	"${CHART}" \
	--values $OVERRIDE \
	--namespace $NAMESPACE \
	--create-namespace
