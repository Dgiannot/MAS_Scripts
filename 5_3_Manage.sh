#!/bin/bash

#Script to kick off each MAS Individual Applications  --> Manage


source masDG.properties
source masDG-script-functions.bash


start_time=$SECONDS

echo_h1 "Deploying Maximo Manage"
echo ""

echo_h1 "Validate OpenShift Status"
echo ""

ocstatus
echo ""
echo ""

oc project "mas-${INSTANCEID}-manage" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${INSTANCEID}-manage" --display-name "MAS - Manage (${INSTANCEID})" > /dev/null 2>&1
fi


export managespace=$(oc config view --minify -o 'jsonpath={..namespace}')
export CORENAMESPACE="mas-${INSTANCEID}-core"

echo ""
echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"
oc -n "${managespace}" create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1

sleep 5
echo ""
echo "${COLOR_YELLOW}Installing Manage Operator${COLOR_RESET}"
echo ""

echo ""
echo "${COLOR_CYAN}Operator will be by default set up to manual on channel 8.x${COLOR_RESET}"
echo ""

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-manage-operatorgroup
  namespace: ${managespace}
spec:
  targetNamespaces:
    - ${managespace}
EOF

echo ""

sleep 5

echo ""
echo_h2 "${COLOR_GREEN}Operator Successfully Created${COLOR_RESET}"

sleep 10

echo "${COLOR_CYAN}Create MAS Manage Operator Subscription${COLOR_RESET}"
echo ""

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-manage
  namespace: ${managespace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas-manage
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""

sleep 10

echo_h2 "${COLOR_GREEN}MAS Manage Operator Subscription Created${COLOR_RESET}"

while [[ $(oc get Subscription ibm-mas-manage -n ${managespace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Approving Manual Installation${COLOR_RESET}"
# Find install plan
installplan=$(oc get subscription ibm-mas-manage -o jsonpath="{.status.installplan.name}" -n "${managespace}")
echo ""
echo "${COLOR_MAGENTA}installplan: $installplan${COLOR_RESET}"
echo ""


# Approve install plan
echo ""
oc patch installplan ${installplan} -n "mas-${INSTANCEID}-manage" --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1


sleep 5

echo -n "Manage Subscription Ready "
while [[ $(oc get deployment/ibm-mas-manage-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${managespace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo ""

sleep 10

owneruid=$(oc get Suite ${INSTANCEID} -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")




echo ""
echo -n "${COLOR_CYAN}Creating Oracle JDBC configuration...${COLOR_RESET}"
echo ""



if [ "$ORCL_CONTAIN"  =  "Y"  ]
then
echo ""
echo "Oracle Database is located in OpenShift Container"
echo ""
echo ""

OCPROJECT="db-19c"
ORACLE_SVC_IP=$(oc get service -n ${OCPROJECT} | grep -i LoadBalancer | awk '{printf $4}')
ORACLE_SVC_PORT=1521
ocjdbcurl="jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${ORACLE_SVC_IP})(PORT=${ORACLE_SVC_PORT}))(CONNECT_DATA=(SID=${jdbcsid})))"

manageindexspace=${ocmanageindexspace}
managetablespace=${ocmanagetablespace}
jdbcschema=${ocjdbcusername}

echo ""
echo ""
cat << EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: JdbcCfg
metadata:
  name: ${INSTANCEID}-jdbc-wsapp-${WORKSPACEID}-manage
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${INSTANCEID}
      uid: ${owneruid}
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/configScope: workspace-application
    mas.ibm.com/instanceId: ${INSTANCEID}
    mas.ibm.com/WORKSPACEID: ${WORKSPACEID}
spec:
  config:
    credentials:
      secretName: ${INSTANCEID}-usersupplied-jdbc-creds-wsapp-${WORKSPACEID}-manage
    driverOptions: {}
    sslEnabled: ${orclsslenabled}
    url: >-
      ${ocjdbcurl}
  displayName: Maximo Manage Oracle Database
  type: external
EOF

sleep 5

echo ""
echo ""
cat << EOF |oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-usersupplied-jdbc-creds-wsapp-${WORKSPACEID}-manage
  namespace: ${CORENAMESPACE}
data:
  password: $(echo -n ${ocjdbcpassword} | base64)
  username: $(echo -n ${ocjdbcusername} | base64)
type: Opaque
EOF


else

echo "Oracle Database is located on Bare Metal"

echo ""
echo ""
cat << EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: JdbcCfg
metadata:
  name: ${INSTANCEID}-jdbc-wsapp-${WORKSPACEID}-manage
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${INSTANCEID}
      uid: ${owneruid}
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/configScope: workspace-application
    mas.ibm.com/instanceId: ${INSTANCEID}
    mas.ibm.com/WORKSPACEID: ${WORKSPACEID}
spec:
  config:
    credentials:
      secretName: ${INSTANCEID}-usersupplied-jdbc-creds-wsapp-${WORKSPACEID}-manage
    driverOptions: {}
    sslEnabled: ${orclsslenabled}
    url: >-
      ${jdbcurl}
  displayName: Maximo Manage Oracle Database
  type: external
EOF

sleep 5

echo ""
echo ""
cat << EOF |oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-usersupplied-jdbc-creds-wsapp-${WORKSPACEID}-manage
  namespace: ${CORENAMESPACE}
data:
  password: $(echo -n ${jdbcpassword} | base64)
  username: $(echo -n ${jdbcusername} | base64)
type: Opaque
EOF

fi

echo ""
echo ""
sleep 10

echo -n "${COLOR_CYAN}Manage JDBC Config Ready ${COLOR_RESET}"
echo ""
while [[ $(oc get JdbcCfg ${INSTANCEID}-jdbc-wsapp-${WORKSPACEID}-manage --ignore-not-found=true -n ${CORENAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

sleep 10

echo ""
echo "${COLOR_CYAN}Instantiating Manage app${COLOR_RESET}"
echo ""

cat << EOF | oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: ManageApp
metadata:
  labels:
    app.kubernetes.io/instance: ${INSTANCEID}
    app.kubernetes.io/managed-by: ibm-mas-manage
    app.kubernetes.io/name: ibm-mas-manage
    mas.ibm.com/applicationId: manage
    mas.ibm.com/instanceId: ${INSTANCEID}
  name: ${INSTANCEID}
  namespace: ${managespace}
spec:
  license:
    accept: true
EOF

echo ""
echo ""

sleep 10

echo ""
echo -n "${COLOR_CYAN}Manage Config Ready ${COLOR_RESET}"
while [[ $(oc get ManageApp ${INSTANCEID} --ignore-not-found=true -n ${managespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

sleep 10

echo ""
echo ""
echo "${COLOR_CYAN}Creating Crypto(x) Key Secret...${COLOR_RESET}"
echo ""

cat << EOF |oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-manage-db-es
  namespace: ${managespace}
data:
  MXE_SECURITY_CRYPTOX_KEY: $(echo -n ${cryptox_key} | base64)
  MXE_SECURITY_CRYPTO_KEY: $(echo -n ${crypto_key} | base64)
  MXE_SECURITY_OLD_CRYPTOX_KEY: $(echo -n ${oldcryptox_key} | base64)
  MXE_SECURITY_OLD_CRYPTO_KEY: $(echo -n ${oldcrypto_key} | base64)
type: Opaque
EOF

sleep 10

echo ""
echo "${COLOR_CYAN}Now Activating Manage.${COLOR_RESET}"
echo ""
echo ""
echo "This will take about 1 hr"
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: ManageWorkspace
metadata:
  namespace: ${managespace}
  name: ${INSTANCEID}-${WORKSPACEID}
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/instanceId: ${INSTANCEID}
    mas.ibm.com/workspaceId: ${WORKSPACEID}
spec:
  bindings:
    jdbc: workspace-application
  components:
    base:
      version: latest
    health:
      version: latest
    spatial:
      version: latest
  settings:
    deployment:
      persistentVolumes:
        - mountPath: /DOCLINKS
          pvcName: ${manage-doclinks}
          size: 20Gi
          storageClassName: ${SC_RWX}
      mode: up
      importedCerts: []
      buildTag: latest
      serverBundles:
        - bundleType: all
          isDefault: true
          isUserSyncTarget: true
          name: mxall
          replica: 3
          routeSubDomain: all
          isMobileTarget: true
        - bundleType: standalonejms
          name: jms
          replica: 1
      autoGenerateEncryptionKeys: true
      serverTimezone: America/Chicago
    languages:
      baseLang: ${managebaselang}
    db:
      dbSchema: ${jdbcschema}
      encryptionSecret: ${INSTANCEID}-manage-db-es
      maxinst:
        bypassUpgradeVersionCheck: false
        db2Vargraphic:  false
        demodata: ${managedemodata}
        indexSpace: ${manageindexspace}
        tableSpace: ${managetablespace}
EOF

sleep 10

echo ""
echo -n "${COLOR_GREEN}Workspace Config Ready ${COLOR_RESET}"
while [[ $(oc get ManageWorkspace  --ignore-not-found=true -n  ${managespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo ""
echo ""

elapsed=$(( SECONDS - start_time ))

eval "echo Script Run Time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"


echo_h2 "${COLOR_GREEN}Installation of MAS - Manage Successfully Completed${COLOR_RESET}"

exit 0