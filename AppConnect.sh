#!/bin/bash

######################################
############ AppConnect Pre-Reqs ############
######################################

# Doug G Modified

# This will install the MAS Pre-reqa
# Set variables in masDG.properties

source masDG.properties
source masDG-script-functions.bash


echo_h1 "Create IBM App Connect Project"
echo ""

oc project ${APPCONNECT_NAMESPACE} > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project ${APPCONNECT_NAMESPACE} --display-name "App Connect" > /dev/null 2>&1
fi


echo ""
echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"
oc -n ${APPCONNECT_NAMESPACE} create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1
echo ""


echo_h1 "Create IBM App Connect Operator Group"
echo ""

echo ""
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: app-connect-operator-group
  namespace: ${APPCONNECT_NAMESPACE}
spec:
  targetNamespaces:
    - ${APPCONNECT_NAMESPACE}
EOF

echo ""

sleep 10

echo_h1 "Create IBM App Connect Subscription"
echo ""

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-appconnect
  namespace: ${APPCONNECT_NAMESPACE}
spec:
  channel: v4.2
  installPlanApproval: Automatic
  name: ibm-appconnect
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""

while : ; do
    echo ""
    oc get subscription ibm-appconnect -n ${APPCONNECT_NAMESPACE}	
    echo ""
    installedCSV=$(oc get subscription ibm-appconnect -n ${APPCONNECT_NAMESPACE} -o jsonpath="{.status.installedCSV}")
    echo ""
    echo "IBM App Connect status is $installedCSV"
    echo ""
    if [[ "$installedCSV" == ibm-appconnect* ]]
    then
       echo ""
      echo_h2 "${COLOR_GREEN}IBM App Connect Subscription Successfully Deployed${COLOR_RESET}"
       echo ""
        break
    fi
    sleep 20
done


echo ""

sleep 30

echo_h1 "Create IBM App Connect Dashboard"
echo ""


cat <<EOF | oc apply -f -
apiVersion: appconnect.ibm.com/v1beta1
kind: Dashboard
metadata:
  name: ${APPCONNECT_DASHBOARD}
  namespace: ${APPCONNECT_NAMESPACE}	
spec:
  license:
    accept: true
    license: ${APPCONNECT_LICENSE}
    use: AppConnectEnterpriseProduction
  pod:
    containers:
      content-server:
        resources:
          limits:
            cpu: 250m
            memory: 512Mi
          requests:
            cpu: 50m
            memory: 50Mi
      control-ui:
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 50m
            memory: 125Mi
  useCommonServices: false
  version: '12.0'
  storage:
    class: ${SC_RWX}
    size: 5Gi
    type: persistent-claim
  replicas: 1
EOF

echo ""

echo ""
echo -n "${COLOR_GREEN}App Connect Dashboard Ready${COLOR_RESET} "
while [[ $(oc get Dashboard ${APPCONNECT_DASHBOARD} --ignore-not-found=true -n ${APPCONNECT_NAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
echo ""

sleep 20

echo_h1 "Retrieve IBM App Connect Routes"
echo ""


appconnect_endpoint=$(oc get routes ${APPCONNECT_DASHBOARD}-ui -n "${APPCONNECT_NAMESPACE}" |awk 'NR==2 {print $2}')
appconnect_url=https://$appconnect_endpoint

echo ""
echo "$appconnect_url"
echo ""

echo ""

echo_h1 "Register IBM App Connect Add-on to MAS"
echo ""


cat <<EOF | oc apply -f -
apiVersion: addons.mas.ibm.com/v1
kind: AppConnect
metadata:
  name: ${INSTANCEID}-addons-appconnect
  namespace: ${CORENAMESPACE}
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId:  ${INSTANCEID}
spec:
  displayName: MAS AppConnect Configuration
  config:
    dashboard: ${appconnect_url}
    users: []
EOF




echo_h2 "${COLOR_GREEN}Installation of IBM App Connect Successfully Completed${COLOR_RESET}"

exit 0



