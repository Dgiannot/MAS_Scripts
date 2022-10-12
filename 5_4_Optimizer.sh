#!/bin/bash


#Script to kick off each MAS Individual Applications  --> Optimizer

source masDG-script-functions.bash
source masDG.properties

# script start time
start_time=$SECONDS

# Deploy MSO


echo_h1 "Deploying Maximo Optimizer"
echo ""

echo_h1 "Validate OpenShift Status"
echo ""

ocstatus
echo ""
echo ""

oc project "mas-${INSTANCEID}-optimizer" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${INSTANCEID}-optimizer" --display-name "MAS - Optimizer (${INSTANCEID})" > /dev/null 2>&1
fi


export optnamespace=$(oc config view --minify -o 'jsonpath={..namespace}')

echo ""
echo ""
echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"


oc -n "${optnamespace}" create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1

echo ""
echo ""
echo "${COLOR_YELLOW}Installing Maximo Optimizer Operator${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Operator will be by default set up to manual on channel 8.x${COLOR_RESET}"
echo ""
echo

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${optnamespace}-operatorgroup
  namespace: ${optnamespace}
spec:
  targetNamespaces:
    - ${optnamespace}
EOF

sleep 5

echo ""

echo_h2 "${COLOR_GREEN}Maximo Optimizer Operator Successfully Created${COLOR_RESET}"


echo ""
echo "${COLOR_CYAN}Create Maximo Optimizer Operator Subscription${COLOR_RESET}"

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-optimizer
  namespace: ${optnamespace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas-optimizer
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""
echo ""

sleep 10

echo_h2 "${COLOR_GREEN}Maximo Optimizer Operator Subscription Created${COLOR_RESET}"


while [[ $(oc get Subscription ibm-mas-optimizer -n ${optnamespace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Approving Manual Installation${COLOR_RESET}"
echo ""

# Find install plan
optinstallplan=$(oc get subscription ibm-mas-optimizer -o jsonpath="{.status.installplan.name}" -n ${optnamespace})
echo ""
echo "${COLOR_MAGENTA}installplan: $optinstallplan${COLOR_RESET}"

# Approve install plan
echo ""
oc patch installplan ${optinstallplan} -n ${optnamespace} --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

echo ""

echo -n "Optimizer Subscription Ready "
while [[ $(oc get deployment/ibm-mas-optimizer-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${optnamespace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

sleep 5

echo ""
echo ""
echo "${COLOR_CYAN}Instantiating Maximo Optimizer App${COLOR_RESET}"
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: OptimizerApp
metadata:
  name: ${INSTANCEID}
  namespace: ${optnamespace}
  labels:
    app.kubernetes.io/instance: ${INSTANCEID}
    app.kubernetes.io/managed-by: ibm-mas-optimizer
    app.kubernetes.io/name: ibm-mas-optimizer
    mas.ibm.com/applicationId: optimizer
    mas.ibm.com/instanceId: ${INSTANCEID}
spec:
  bindings:
    mongo: system
  plan: full
  settings:
    adminUI:
      replicas: 1
      resources:
        limits:
          cpu: '1'
          memory: 1Gi
        requests:
          cpu: '0.01'
          memory: 196Mi
    api:
      logLevel: debug
      replicas: 1
      resources:
        limits:
          cpu: '1'
          memory: 2Gi
        requests:
          cpu: '0.01'
          memory: 196Mi
    retainDataOnDelete: true
EOF

echo ""
echo ""

sleep 10
echo ""
echo -n "Maximo Optimizer Config Ready "
while [[ $(oc get OptimizerApp ${INSTANCEID} --ignore-not-found=true -n ${optnamespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"


echo ""
echo "${COLOR_CYAN}Creating Maximo Optimizer workspace...${COLOR_RESET}"
echo ""

cat << EOF |oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: OptimizerWorkspace
metadata:
  name: ${INSTANCEID}-${WORKSPACEID}
  namespace: ${optnamespace}
  labels:
    app.kubernetes.io/instance: ibm-mas-optimizer
    app.kubernetes.io/name: ibm-mas-optimizer
    mas.ibm.com/applicationId: optimizer
    mas.ibm.com/instanceId: ${INSTANCEID}
    mas.ibm.com/workspaceId: ${WORKSPACEID}
spec:
  settings:
    executionService:
      logLevel: debug
      memoryMax: 4
      maxWorkerMemory: 4096
      queueWorkers: 3
      cpuMinUnits: Millicores
      cpuMin: 100
      memoryMaxUnits: Gi
      maxWorkerMemoryUnits: Mb
      memoryMin: 512
      cpuMaxUnits: Cores
      replicas: 3
      cpuMax: 3
      memoryMinUnits: Mi
    retainDataOnDeactivate: true
EOF

sleep 10

echo ""
echo -n "${COLOR_GREEN}Optimizer Workspace Ready${COLOR_RESET}"
while [[ $(oc get OptimizerWorkspace ${INSTANCEID}-${WORKSPACEID} --ignore-not-found=true -n ${optnamespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

echo ""
echo ""

elapsed=$(( SECONDS - start_time ))

eval "echo Script Run Time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"
echo ""
echo ""


echo_h2 "${COLOR_GREEN}Installation of MAS - Optimizer Successfully Completed${COLOR_RESET}"

exit 0