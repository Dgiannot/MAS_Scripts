#!/bin/bash

# Doug G Modified

# This will install the IBM Operator Catalog, IBM Cert Manager & Define CloudFlare Webhook
# Set variables in masDG.properties

source masDG.properties
source masDG-script-functions.bash


# script start time
start_time=$SECONDS


echo_h1 "Validate OpenShift Status"


ocstatus=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echo "Login to OpenShift to continue cert installation." 1>&2
  exit 1
fi
echo ""
echo "${COLOR_CYAN}Currently logged into OpenShift as ${ocstatus}${COLOR_RESET}"
echo ""



echo_h1 "Install IBM Operator Catalog"
echo ""

cat <<EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "IBM Operator Catalog" 
  publisher: IBM
  sourceType: grpc
  image: icr.io/cpopen/ibm-operator-catalog:latest
  updateStrategy:
    registryPoll:
      interval: 45m
EOF
echo ""

while : ; do
   echo ""
   oc get po -n openshift-marketplace | grep ibm-operator-catalog
   catalogOperatorStatus=$(oc get po -n openshift-marketplace | grep ibm-operator-catalog | grep 1/1 | awk '{print $3}') 
   echo ""
if [[ $catalogOperatorStatus == "Running" ]]; then 
  echo ""
   echo_h2 "${COLOR_GREEN}Successfully Deployed IBM Operator Catalog${COLOR_RESET}"
   break
fi
   sleep 10
done

echo ""
echo_h1 "Install Opencloud Catalog"

echo ""
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: opencloud-operators
  namespace: openshift-marketplace
spec:
  displayName: IBMCS Operators
  publisher: IBM
  sourceType: grpc
  image: docker.io/ibmcom/ibm-common-service-catalog:latest
  updateStrategy:
    registryPoll:
      interval: 45m
EOF

echo ""
while : ; do
   oc get po -n openshift-marketplace | grep opencloud-operators
   catalogOperatorStatus2=$(oc get po -n openshift-marketplace | grep opencloud-operators | grep 1/1 | awk '{print $3}') 
   echo ""
if [[ $catalogOperatorStatus2 == "Running" ]]; then
   echo ""
   echo_h2 "${COLOR_GREEN}Successfully Deployed Opencloud Operator Catalog${COLOR_RESET}"  
   break
fi
   sleep 10
done

echo_h1 "Create IBM Common Services Project"
echo ""

oc project ${COMMON_NAMESPACE} > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project ${COMMON_NAMESPACE} > /dev/null 2>&1
fi

echo ""
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: operatorgroup
  namespace: ${COMMON_NAMESPACE}
spec:
  targetNamespaces:
    - ${COMMON_NAMESPACE}
EOF

sleep 5

echo ""
echo_h1 "Create subscription to IBM Common Services operator"

echo ""
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-common-service-operator
  namespace: ${COMMON_NAMESPACE}
spec:
  channel: v3
  installPlanApproval: Automatic
  name: ibm-common-service-operator
  # source: opencloud-operators
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF
echo ""

while : ; do
    installedCSV=$(oc get subscription ibm-common-service-operator -n ${COMMON_NAMESPACE} -o jsonpath="{.status.installedCSV}")
    echo "Subscription status of IBM Common Services is $installedCSV"
    echo ""
    if [[ "$installedCSV" == ibm-common-service-operator* ]]
    then
        break
    fi
    sleep 10
done

while : ; do
    dg_status=$(oc get po | grep "secretshare\|ibm-common-service-webhook\|ibm-namespace-scope-operator\|operand-deployment-lifecycle-manager" | grep Running | grep 1/1 | wc -l)
    echo "${dg_status} IBM Common Service Operator pods are running"
    echo ""
    if [[ $dg_status -eq 4 ]]
    then
        break
    fi
    sleep 20
done

echo ""
echo_h1 "Check if CRD operandrequests.operator.ibm.com got created"

while : ; do
    crd_status=$(oc get crd operandrequests.operator.ibm.com |grep operandrequests.operator.ibm.com | wc -l)
    echo "${crd_status} Operand Successfully Installed"
    if [[ $crd_status -eq 1 ]]
    then
        break
    fi
    sleep 10
done

sleep 30

echo ""
echo_h1 "Install IBM Certificate Manager"


cat <<EOF | oc apply -f -
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: common-service
  namespace: ${CERT_NAMESPACE}
spec:
  requests:
    - operands:
        - name: ibm-cert-manager-operator
        - name: ibm-licensing-operator
      registry: common-service
EOF
echo ""

sleep 30


while : ; do
    echo ""
    oc get subscription ibm-cert-manager-operator -n ${COMMON_NAMESPACE}	
    echo ""
    installedCSV=$(oc get subscription ibm-cert-manager-operator -n ${COMMON_NAMESPACE} -o jsonpath="{.status.installedCSV}")
    echo ""
    echo "IBM Cert Manager status is $installedCSV"
    echo ""
    if [[ "$installedCSV" == ibm-cert-manager-operator* ]]
    then
       echo ""
      echo_h2 "${COLOR_GREEN}IBM Cert Manager Subscription Successfully Deployed${COLOR_RESET}"
       echo ""
        break
    fi
    sleep 20
done



echo_h1 "Install CloudFlare DNS Integration"

sleep 5

echo ""
echo "${COLOR_CYAN}Adding Secret${COLOR_RESET}"
echo ""

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-key-secret
  namespace: ${CERT_NAMESPACE}
type: Opaque
stringData:
  api-key: ${CLOUDFLAREAPI}
EOF

sleep 10

echo ""
echo "${COLOR_CYAN}Define ClusterIssuer${COLOR_RESET}"


cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${CLUSTERISSUER}
  namespace: ${CERT_NAMESPACE}
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${LEID}
    privateKeySecretRef:
        name: letsencrypt-prod
    solvers:
    - dns01:
        cloudflare:
          email: ${CLOUDFLAREID}
          apiKeySecretRef:
            key: api-key
            name: cloudflare-api-key-secret
EOF

sleep 10
echo ""

echo_h2 "${COLOR_GREEN}IBM Catalogs & IBM Cert Manager successfully installed${COLOR_RESET}"

# script end time

elapsed=$(( SECONDS - start_time ))

eval "echo Script Run Time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"


exit 0
