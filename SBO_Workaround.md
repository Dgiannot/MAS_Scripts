cat <<EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
name: rh-service-binding-operator
namespace: openshift-operators
spec:
channel: stable
name: rh-service-binding-operator
source: redhat-operators
sourceNamespace: openshift-marketplace
installPlanApproval: Manual
startingCSV: service-binding-operator.v1.0.1
EOF1

Then run:
oc get installplan -n openshift-operators | grep -i service-binding | awk '{print $1}'

when the install plan returns, run:
oc patch installplan service-binding-operator.v1.0.1 -n openshift-operators --type merge --patch '{"spec":{"approved":true}}'
