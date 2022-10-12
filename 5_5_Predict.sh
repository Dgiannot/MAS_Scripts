#!/bin/bash


#Script to kick off each MAS Individual Applications  --> Predict

source masDG-script-functions.bash
source masDG.properties

# script start time
start_time=$SECONDS



echo_h1 "Deploying Maximo Predict"
echo ""

echo_h1 "Validate OpenShift Status"
echo ""

ocstatus
echo ""
echo ""

oc project "mas-${INSTANCEID}-predict" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${INSTANCEID}-predict" --display-name "MAS - Predict (${INSTANCEID})" > /dev/null 2>&1
fi

echo ""
predictspace=$(oc config view --minify -o 'jsonpath={..namespace}')
CORENAMESPACE="mas-${INSTANCEID}-core"


echo ""
echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"
echo ""
oc -n "${predictspace}" create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1

sleep 5

echo ""
echo "${COLOR_YELLOW}Installing Predict Operator${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Operator will be by default set up to manual on channel 8.x${COLOR_RESET}"

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-predict-operatorgroup
  namespace: ${predictspace}
spec:
  targetNamespaces:
    - ${predictspace}
EOF

echo ""
echo_h2 "${COLOR_GREEN}Operator Successfully Created${COLOR_RESET}"

sleep 10

echo ""
echo "${COLOR_CYAN}Create MAS Predict Operator Subscription${COLOR_RESET}"
echo ""

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-predict
  namespace: ${predictspace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas-predict
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF


sleep 10

echo ""
echo_h2 "${COLOR_GREEN}MAS Predict Operator Subscription Created${COLOR_RESET}"


while [[ $(oc get Subscription ibm-mas-predict -n ${predictspace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo ""
echo ""
echo "${COLOR_CYAN}Approving Manual Installation${COLOR_RESET}"
# Find install plan
pinstallplan=$(oc get subscription ibm-mas-predict -o jsonpath="{.status.installplan.name}" -n "${predictspace}")
echo "${COLOR_MAGENTA}installplan: $pinstallplan${COLOR_RESET}"

echo ""
# Approve install plan
oc patch installplan ${pinstallplan} -n "${predictspace}" --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1


echo -n "Predict Subscription Ready "
while [[ $(oc get deployment/ibm-mas-predict-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${predictspace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"



echo_h1 "${COLOR_YELLOW}Instantiating Watson Studio configuration${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Retriving Watson Studio Route${COLOR_RESET}"
echo ""

cp4d_url=$(oc get route cpd -n "${CP4D_NAMESPACE}" | awk 'NR==2 {print $2}')
cp4d_url_s=https://$cp4d_url

echo ""
echo ""
echo $cp4d_url
echo ""
echo ""

#echo ""
#echo "${COLOR_CYAN}Retriving Watson Studio Certificate${COLOR_RESET}"
#echo ""

#WATSONC=$(fetchCertificates $cp4d_url 443)
#WATSONC1=$(getcert "$WATSONC" 1 | sed 's/^/\ \ \ \ \ \ \ \ /g')
#W2=$(oc -n ${CP4D_NAMESPACE} get secret default-ssl -o "jsonpath={.data.cert\.crt}" | base64 -d | sed -E 's/^/\ \ \ \ \ \ \ \ /g')

echo ""
echo ""

cat <<EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: WatsonStudioCfg
metadata:
  name: ${INSTANCEID}-watsonstudio-system
  namespace: ${CORENAMESPACE}
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${INSTANCEID}
spec:
  config:
    credentials:
      secretName: ${INSTANCEID}-usersupplied-watsons-creds-system
    endpoint: ${cp4d_url_s}
  displayName: "MAS - Watson Studio configuration"
  type: external
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"
echo ""


while [[ $(oc get WatsonStudioCfg ${INSTANCEID}-watsonstudio-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"



watsoncfguname=admin
#watsoncfgpassword=$db2password
CP4D_INIT_PASS=$(oc -n ${CP4D_NAMESPACE} get secret admin-user-details -o "jsonpath={.data.initial_admin_password}" | base64 -d)
watsonuid=$(oc get WatsonStudioCfg ${INSTANCEID}-watsonstudio-system -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")

echo ""
echo "${COLOR_CYAN}Creating Watson Studio configuration credentials...${COLOR_RESET}"
echo ""
cat << EOF | oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-usersupplied-watsons-creds-system
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: WatsonStudioCfg
      name: ${INSTANCEID}-watsonstudio-system
      uid: ${watsonuid}
data:
  password: $(echo -n "${CP4D_INIT_PASS}" | base64)
  username: $(echo -n "${watsoncfguname}" | base64 )
type: Opaque  
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo ""
echo -n "${COLOR_GREEN}Watson Studio Configuration Ready:${COLOR_RESET} "
while [[ $(oc get WatsonStudioCfg ${INSTANCEID}-watsonstudio-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo ""

echo ""
echo ""
echo "${COLOR_CYAN}Instantiating Predict app${COLOR_RESET}"

echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: PredictApp
metadata:
  name: ${INSTANCEID}
  labels:
    app.kubernetes.io/instance: ${INSTANCEID}
    app.kubernetes.io/managed-by: ibm-mas-predict
    app.kubernetes.io/name: ibm-mas-predict
    mas.ibm.com/applicationId: predict
    mas.ibm.com/instanceId: ${INSTANCEID}
  namespace: ${predictspace}
spec:
  bindings:
    jdbc: system
  components: {}
  settings:
    deployment: {}
EOF

echo ""
echo ""

sleep 5

echo ""
echo -n "Predict Config Ready "
while [[ $(oc get PredictApp ${INSTANCEID} --ignore-not-found=true -n ${predictspace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo ""
echo ""
echo "${COLOR_CYAN}Creating Predict workspace...${COLOR_RESET}"


cat << EOF |oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: PredictWorkspace
metadata:
  name: ${INSTANCEID}-${WORKSPACEID}
  namespace: ${predictspace}
labels:
    mas.ibm.com/applicationId: predict
    mas.ibm.com/instanceId: ${INSTANCEID}
    mas.ibm.com/workspaceId: ${WORKSPACEID}
spec:
  bindings:
    health: workspace
    jdbc: system
    monitor: workspace
    watsonstudio: system
  components: {}
  settings: {}
EOF


echo ""
echo -n "${COLOR_GREEN}Predict Workspace Ready${COLOR_RESET}"
while [[ $(oc get PredictWorkspace ${INSTANCEID}-${WORKSPACEID} --ignore-not-found=true -n ${predictspace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo ""
echo ""

elapsed=$(( SECONDS - start_time ))

eval "echo Script Run Time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"

echo_h2 "${COLOR_GREEN}Installation of MAS - Predict Successfully Completed${COLOR_RESET}"

exit 0