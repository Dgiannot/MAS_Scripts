#!/bin/bash

#Script to kick off each MAS Individual Applications  --> Monitor


source masDG.properties
source masDG-script-functions.bash

# script start time
start_time=$SECONDS

echo ""
echo_h1 "Deploying Maximo Monitor"
echo ""

echo_h1 "Validate OpenShift Status"
echo ""

ocstatus
echo ""
echo ""

oc project "mas-${INSTANCEID}-monitor" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${INSTANCEID}-monitor" --display-name "MAS - Monitor (${INSTANCEID})" > /dev/null 2>&1
fi

export CORENAMESPACE="mas-${INSTANCEID}-core"
owneruid=$(oc get Suite ${INSTANCEID} -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")
export monitorspace=$(oc config view --minify -o 'jsonpath={..namespace}')

echo ""
echo ""
echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"
oc -n "${monitorspace}" create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1
echo ""
echo ""

sleep 10

echo ""
echo ""
echo "${COLOR_YELLOW}Installing Monitor Operator${COLOR_RESET}"

echo ""
echo ""
echo "${COLOR_CYAN}Operator will be by default set up to manual on channel 8.x${COLOR_RESET}"
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-monitor-operatorgroup
  namespace: ${monitorspace}
spec:
  targetNamespaces:
    - ${monitorspace}
EOF
echo ""
echo ""

echo_h2 "${COLOR_GREEN}Operator Successfully Created${COLOR_RESET}"

sleep 10

echo ""
echo ""
echo "${COLOR_CYAN}Create MAS Monitor Operator Subscription${COLOR_RESET}"
echo ""
echo ""


cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-monitor
  namespace: ${monitorspace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas-monitor
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""
echo ""
sleep 10

echo ""
echo_h2 "${COLOR_GREEN}MAS Monitor Operator Subscription Created${COLOR_RESET}"
echo ""
echo ""

echo -n "Monitor Subscription Created "
while [[ $(oc get Subscription ibm-mas-monitor -n ${monitorspace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

echo ""
echo ""
echo "${COLOR_CYAN}Approving Manual Installation${COLOR_RESET}"
# Find install plan
echo ""
echo ""
minstallplan=$(oc get subscription ibm-mas-monitor -o jsonpath="{.status.installplan.name}" -n "${monitorspace}")
echo ""
echo ""

echo "${COLOR_MAGENTA}installplan: $minstallplan${COLOR_RESET}"

echo ""
# Approve install plan
oc patch installplan ${minstallplan} -n "${monitorspace}" --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

echo ""
echo ""
sleep 5

echo -n "Monitor Subscription Ready "
while [[ $(oc get deployment/ibm-mas-monitor-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${monitorspace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

sleep 10

echo ""
echo ""
echo "${COLOR_CYAN}Instantiating Monitor App${COLOR_RESET}"
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: MonitorApp
metadata:
  namespace: ${monitorspace}
  name: ${INSTANCEID}
  labels:
    app.kubernetes.io/instance: ${INSTANCEID}
    app.kubernetes.io/managed-by: ibm-mas-monitor
    app.kubernetes.io/name: ibm-mas-monitor
    mas.ibm.com/applicationId: monitor
    mas.ibm.com/instanceId: ${INSTANCEID}
spec:
  bindings:
    jdbc: system
    kafka: system
    mongo: system
  settings:
    deployment:
      size: small
EOF

echo ""
echo ""

sleep 10

echo ""
echo -n "Monitor Config Ready "
while [[ $(oc get MonitorApp ${INSTANCEID} --ignore-not-found=true -n ${monitorspace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

sleep 5

echo ""
echo ""
echo "${COLOR_CYAN}Creating Monitor workspace...${COLOR_RESET}"
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: MonitorWorkspace
metadata:
  name: ${INSTANCEID}-${WORKSPACEID}
  namespace: ${monitorspace}
  labels:
    mas.ibm.com/applicationId: monitor
    mas.ibm.com/instanceId: ${INSTANCEID}
    mas.ibm.com/workspaceId: ${WORKSPACEID}
spec:
  bindings:
    iot: workspace
    jdbc: system
EOF

echo ""
echo ""

sleep 10m

echo "Monitor Workspace should be Ready "


echo "Check CRD to Verify"

# NOT Working, No Ready in 

#echo ""
#echo -n "${COLOR_GREEN}Monitor Workspace Ready ${COLOR_RESET}"
#while [[ $(oc get MonitorWorkspace ${INSTANCEID}-${WORKSPACEID} --ignore-not-found=true -n ${monitorspace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
#showWorking $!
#printf '\b'
#echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

echo ""
echo ""

echo_h2 "${COLOR_GREEN}Installation of MAS - Monitor Successfully Completed${COLOR_RESET}"

elapsed=$(( SECONDS - start_time ))

eval "echo Script Run Time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"

exit 0
