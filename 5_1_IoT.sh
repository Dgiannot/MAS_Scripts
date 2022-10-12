#!/bin/bash

#Script to kick off each MAS Individual Applications  --> IoT Platform


source masDG.properties
source masDG-script-functions.bash

# script start time
start_time=$SECONDS

echo_h1 "Validate OpenShift Status"
echo ""

ocstatus
echo ""
echo ""

echo_h1 "Deploying MAS IOT"
echo ""

oc project "mas-${INSTANCEID}-iot" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${INSTANCEID}-iot" --display-name "MAS - IoT (${INSTANCEID})" > /dev/null 2>&1
fi

export CORENAMESPACE="mas-${INSTANCEID}-core"
export iotnamespace=$(oc config view --minify -o 'jsonpath={..namespace}')

owneruid=$(oc get Suite ${INSTANCEID} -n mas-${INSTANCEID}-core -o jsonpath="{.metadata.uid}")

sleep 5

echo ""
echo ""

echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"

oc -n "${iotnamespace}" create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1

echo ""
echo ""

sleep 5


echo ""
echo ""

echo_h1 "Retriving JDBC SSL certificate"

# Get secret from  -->  db2wh-internal-tls   --> ca.crt

#DB2C=$(oc -n ${CP4D_NAMESPACE} get secret db2wh-internal-tls -o "jsonpath={.data.ca\.crt}" | base64 -d | sed -E 's/^/\ \ \ \ \ \ \ \ /g')
DB2U_C=$(oc -n ${DB2U_NS} get secret db2u-certificate -o "jsonpath={.data.ca\.crt}" | base64 -d | sed -E 's/^/\ \ \ \ \ \ \ \ /g')

db2_pass_system=$(oc -n ${DB2U_NS} get secret c-${DB2U_INST}-instancepassword -o "jsonpath={.data.password}" | base64 -d)


echo ""
echo ""
echo -e "${COLOR_GREEN}Successfully Retrieved Certs${COLOR_RESET}"

echo ""
echo ""

echo_h1 "Apply DB2 System JdbcCfg"
echo ""
echo ""


cat << EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: JdbcCfg
metadata:
  name: ${INSTANCEID}-jdbc-system
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${INSTANCEID}
      uid: ${owneruid}
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${INSTANCEID}
spec:
  certificates:
    - alias: ${DB2U_INST}
      crt: |-
${DB2U_C}
  config:
    credentials:
      secretName: ${INSTANCEID}-usersupplied-jdbc-creds-system
    driverOptions: {}
    sslEnabled: ${db2jdbcsslenabled}
    url: >-
      ${db2_jdbc_url_system}
  displayName: db2-iot-database
  type: external
EOF

echo ""
echo ""


jdbcowneruid=$(oc get JdbcCfg ${INSTANCEID}-jdbc-system -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")

sleep 5

cat << EOF | oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-usersupplied-jdbc-creds-system
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: JdbcCfg
      name: ${INSTANCEID}-jdbc-system
      uid: ${jdbcowneruid}
data:
  password: $(echo -n "${db2_pass_system}" | base64)
  username: $(echo -n "${db2_user_system}" | base64 )
type: Opaque  
EOF

echo ""
echo ""

sleep 10


echo ""
echo -n "${COLOR_GREEN}IBM DB2 System Database Configuration Ready${COLOR_RESET} "
echo ""
echo ""
while [[ $(oc get JdbcCfg ${INSTANCEID}-jdbc-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
echo ""

sleep 10

echo ""
echo "${COLOR_YELLOW}Installing IoT Operator${COLOR_RESET}"

echo ""
echo ""
echo "${COLOR_CYAN}Operator will be by default set up to manual on channel 8.x${COLOR_RESET}"

echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-iot-operatorgroup
  namespace: ${iotnamespace}
spec:
  targetNamespaces:
    - ${iotnamespace}
EOF

echo ""
echo ""


echo_h2 "${COLOR_GREEN}IoT Operator Successfully Created${COLOR_RESET}"

sleep 10
echo ""
echo "${COLOR_CYAN}Create MAS IoT Operator Subscription${COLOR_RESET}"
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-iot
  namespace: ${iotnamespace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas-iot
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""
echo ""

sleep 10


echo_h2 "${COLOR_GREEN}MAS IoT Operator Subscription Created${COLOR_RESET}"

echo -n "IoT Subscription Created "

while [[ $(oc get Subscription ibm-mas-iot -n ${iotnamespace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Approving Manual Installation${COLOR_RESET}"

# Find install plan
iotinstallplan=$(oc get subscription ibm-mas-iot -o jsonpath="{.status.installplan.name}" -n ${iotnamespace})
echo ""
echo "${COLOR_MAGENTA}installplan: $iotinstallplan${COLOR_RESET}"
echo ""
echo ""

# Approve install plan
oc patch installplan ${iotinstallplan} -n ${iotnamespace} --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

echo ""
echo ""            
echo -n "IoT Subscription Ready "
while [[ $(oc get deployment/ibm-mas-iot-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${iotnamespace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

sleep 10

echo ""
echo ""
echo "${COLOR_CYAN}Instantiating IoT App${COLOR_RESET}"
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: iot.ibm.com/v1
kind: IoT
metadata:
  namespace: ${iotnamespace}
  name: ${INSTANCEID}
  labels:
    app.kubernetes.io/instance: ${INSTANCEID}
    app.kubernetes.io/managed-by: ibm-mas-iot
    app.kubernetes.io/name: ibm-mas-iot
    mas.ibm.com/applicationId: iot
    mas.ibm.com/instanceId: ${INSTANCEID}
spec:
  bindings:
    jdbc: system
    kafka: system
    mongo: system
  components: {}
  settings:
    deployment:
      size: small
    messagesight:
      storage:
        class: ${SC_RWX}
        size: 75Gi
EOF


echo ""
echo ""
echo -n "IoT Config Ready "
while [[ $(oc get IoT ${INSTANCEID} --ignore-not-found=true -n ${iotnamespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


sleep 10

echo ""
echo ""
echo "${COLOR_CYAN}Creating IoT workspace...${COLOR_RESET}"
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: iot.ibm.com/v1
kind: IoTWorkspace
metadata:
  name: ${INSTANCEID}-${WORKSPACEID}
  namespace: ${iotnamespace}

  labels:
    mas.ibm.com/applicationId: iot
    mas.ibm.com/instanceId: ${INSTANCEID}
    mas.ibm.com/workspaceId: ${WORKSPACEID}
spec: {}
EOF

echo ""
echo ""

sleep 10

echo ""
echo -n "${COLOR_GREEN}IoT Workspace Ready${COLOR_RESET}"
while [[ $(oc get IoTWorkspace ${INSTANCEID}-${WORKSPACEID} --ignore-not-found=true -n ${iotnamespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo ""
echo ""

echo_h2 "${COLOR_GREEN}Installation of MAS - IoT Platform Successfully Completed${COLOR_RESET}"

# script end time

elapsed=$(( SECONDS - start_time ))

eval "echo Script Run Time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"

exit 0


