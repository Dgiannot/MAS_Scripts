#!/bin/bash


#Script to kick off each MAS Individual Applications  --> HPU

source masDG-script-functions.bash
source masDG.properties



echo_h1 "Deploying Health and Predict - Utilities"

oc project "mas-${INSTANCEID}-hputilities" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${INSTANCEID}-hputilities" --display-name "MAS - HPUtilities (${INSTANCEID})" > /dev/null 2>&1
fi


hpspace=$(oc config view --minify -o 'jsonpath={..namespace}')
CORENAMESPACE="mas-${INSTANCEID}-core"


echo ""
echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"
oc -n "${hpspace}" create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1

sleep 5

echo ""
echo "${COLOR_YELLOW}Installing Health and Predict - Utilities Operator${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Operator will be by default set up to manual on channel 8.x${COLOR_RESET}"

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-hputilities-operatorgroup
  namespace: ${hpspace}
spec:
  targetNamespaces:
    - ${hpspace}
EOF



echo ""
echo ""

echo_h2 "${COLOR_GREEN}Operator Successfully Created${COLOR_RESET}"

sleep 10

echo ""
echo "${COLOR_CYAN}Create MAS Health and Predict - Utilities Operator Subscription${COLOR_RESET}"
echo ""

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-hputilities
  namespace: ${hpspace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas-hputilities
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""

sleep 10

echo ""
echo_h2 "${COLOR_GREEN}MAS MAS Health and Predict - Utilities Operator Subscription Created${COLOR_RESET}"


while [[ $(oc get Subscription ibm-mas-hputilities -n ${hpspace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'


echo ""
echo "${COLOR_CYAN}Approving Manual Installation${COLOR_RESET}"
# Find install plan
hpinstallplan=$(oc get subscription ibm-mas-hputilities -o jsonpath="{.status.installplan.name}" -n "${hpspace}")
echo "${COLOR_MAGENTA}installplan: $hpinstallplan${COLOR_RESET}"

echo ""
# Approve install plan
oc patch installplan ${hpinstallplan} -n "${hpspace}" --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

echo -n "HPU Subscription Ready "
while [[ $(oc get deployment/ibm-mas-hputilities-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${hpspace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo ""
echo "${COLOR_CYAN}Instlling IBM App Connect${COLOR_RESET}"

./AppConnect.sh

echo ""
echo_h2 "${COLOR_GREEN}MAS MAS Health and Predict - Utilities Operator Subscription Created${COLOR_RESET}"


echo ""
echo "${COLOR_CYAN}Instantiating MAS Health and Predict - Utilities app${COLOR_RESET}"
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: HPUtilitiesApp
metadata:
  namespace: ${hpspace}
  name: ${INSTANCEID}
  labels:
    app.kubernetes.io/instance: ${INSTANCEID}
    app.kubernetes.io/managed-by: ibm-mas-hputilities
    app.kubernetes.io/name: ibm-mas-hputilities
    mas.ibm.com/applicationId: hputilities
    mas.ibm.com/instanceId: ${INSTANCEID}
spec:
  bindings:
    appconnect: system
    health: workspace
  components: {}
  settings: {}
EOF



echo ""
echo ""
echo -n "HPUtilities Config Ready "
while [[ $(oc get HPUtilitiesApp ${INSTANCEID} --ignore-not-found=true -n ${hpspace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"



echo ""
echo "${COLOR_CYAN}Creating Health and Predict - Utilities workspace...${COLOR_RESET}"
echo ""

cat << EOF |oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: HPUtilitiesWorkspace
metadata:
  name: ${INSTANCEID}-${WORKSPACEID}
  namespace: ${hpspace}
  labels:
    mas.ibm.com/applicationId: hputilities
    mas.ibm.com/workspaceId: ${WORKSPACEID}
    mas.ibm.com/instanceId: ${INSTANCEID}
spec:
  bindings:
    watsonstudio: system
  components: {}
  settings: {}
EOF



echo ""
echo ""
echo -n "${COLOR_GREEN}HPUtilities Workspace Ready${COLOR_RESET}"
while [[ $(oc get HPUtilitiesWorkspace ${INSTANCEID}-${WORKSPACEID} --ignore-not-found=true -n ${hpspace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo "${COLOR_CYAN}Creating Watson Studio configuration...${COLOR_RESET}"
echo ""
echo ""

cat <<EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: WatsonStudioCfg
metadata:
  name: ${INSTANCEID}-watsonstudio-app-hputilities
  labels:
    mas.ibm.com/configScope: application
    mas.ibm.com/instanceId: ${INSTANCEID}
  namespace: mas-base-core
spec:
  displayName: WatsonStudio
  certificates:
    - alias: cp4d
      crt: |-
${WATSONC1}       
  config:
    credentials:
      secretName: ${INSTANCEID}-usersupplied-watsons-creds-hpu-system
    endpoint: ${cp4d_url_s}
  displayName: WatsonStudio service
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"
echo ""


while [[ $(oc get WatsonStudioCfg ${INSTANCEID}-watsonstudio-app-hputilities --ignore-not-found=true -n ${CORENAMESPACE} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

watsoncfguname=$db2user
watsoncfgpassword=$db2password
watsonuid=$(oc get WatsonStudioCfg ${INSTANCEID}-watsonstudio-app-hputilities -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")

echo ""
echo "${COLOR_CYAN}Creating Watson Studio configuration credentials...${COLOR_RESET}"
echo ""
cat << EOF | oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-usersupplied-watsons-creds-hpu-system
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: WatsonStudioCfg
      name: ${INSTANCEID}-watsonstudio-app-hputilities
      uid: ${watsonuid}
data:
  password: $(echo -n "${watsoncfgpassword}" | base64)
  username: $(echo -n "${watsoncfguname}" | base64 )
type: Opaque  
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo ""
echo -n "${COLOR_GREEN}Watson Studio Configuration Ready:${COLOR_RESET} "
while [[ $(oc get WatsonStudioCfg ${INSTANCEID}-watsonstudio-app-hputilities --ignore-not-found=true -n ${CORENAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo ""
echo ""