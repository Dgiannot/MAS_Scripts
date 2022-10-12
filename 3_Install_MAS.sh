#!/bin/bash


############################################
############ MAS Installation ##############
############################################

source masDG-script-functions.bash
source masDG.properties

# script start time
start_time=$SECONDS


echo_h1 "Deploying Maximo Application Suite"
oc project "mas-${INSTANCEID}-core" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${INSTANCEID}-core" --display-name "MAS Core Systems (${INSTANCEID}) " > /dev/null 2>&1
fi

CORENAMESPACE=$(oc config view --minify -o 'jsonpath={..namespace}')


echo ""
echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"
oc -n ${CORENAMESPACE} create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1
echo ""

if [[ -z "${DOMAIN_NAME=}" ]]; then 
  echo "${COLOR_CYAN}Resolving domain through Ingress configuration...${COLOR_RESET}"
  domain=$(oc get Ingress.config cluster -o jsonpath='{.spec.domain}')
  echo_h2 "${COLOR_CYAN}Domain is ${DOMAIN_NAME}${COLOR_RESET}"
else
  echo_h2 "${COLOR_GREEN}Domain is preset. Using --> ${DOMAIN_NAME=}${COLOR_RESET}"
fi

echo_h1 "${COLOR_YELLOW}[1/6] Installing MAS Operator${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Operator will be by default set up to manual on channel 8.x${COLOR_RESET}"

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-mas-operatorgroup
  namespace: ${CORENAMESPACE}
spec:
  targetNamespaces:
    - ${CORENAMESPACE}
EOF

echo ""
sleep 10

echo_h2 "${COLOR_GREEN}Operator Successfully Created${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Create MAS Operator Subscription${COLOR_RESET}"

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas
  namespace: ${CORENAMESPACE}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""
sleep 10

echo_h2 "${COLOR_GREEN}MAS Operator Subscription Created${COLOR_RESET}"

while [[ $(oc get Subscription ibm-mas -n ${CORENAMESPACE} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done 

echo ""
echo "${COLOR_CYAN}Approving Manual Installation${COLOR_RESET}"
# Find install plan
installplan=$(oc get subscription ibm-mas -o jsonpath="{.status.installplan.name}" -n ${CORENAMESPACE})
echo "${COLOR_MAGENTA}installplan: $installplan${COLOR_RESET}"

# Approve install plan
oc patch installplan ${installplan} -n ${CORENAMESPACE} --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

echo_h2 "${COLOR_GREEN}MAS Core Operator ready${COLOR_RESET}"

while [[ $(oc get deployment/ibm-mas-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${CORENAMESPACE}) != "1" ]];do sleep 5; done 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}" 

sleep 20

echo ""
echo ""
echo "${COLOR_CYAN}Creating MAS Suite Instance${COLOR_RESET}"
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: core.mas.ibm.com/v1
kind: Suite
metadata:
  name: ${INSTANCEID}
  labels:
    mas.ibm.com/instanceId: ${INSTANCEID}
  namespace: ${CORENAMESPACE}
spec:
  certManagerNamespace: ${CERT_NAMESPACE}
  certificateIssuer:
    duration: 2160h # 90d
    name: ${CLUSTERISSUER}
    renewBefore: 360h # 15d
  domain: ${DOMAIN_NAME}
  license:
    accept: true
  settings:
    icr:
      cp: cp.icr.io/cp
      cpopen: icr.io/cpopen
EOF

echo ""
echo ""

sleep 5

while [[ $(oc get Suite ${INSTANCEID} --ignore-not-found=true  --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 10; done 


owneruid=$(oc get Suite ${INSTANCEID} -o jsonpath="{.metadata.uid}")


echo_h2 "${COLOR_GREEN}Creating Admin Dashboard.${COLOR_RESET}"

while [[ $(oc get deployment/${INSTANCEID}-admin-dashboard --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${CORENAMESPACE}) != "1" ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo_h2 "${COLOR_GREEN}Core API ready ${COLOR_RESET}"   

while [[ $(oc get deployment/${INSTANCEID}-coreapi --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${CORENAMESPACE}) != "3" ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo_h1 "Installation Summary"
echo ""
echo ""
echo_h2 "Administration Dashboard URL"
echo_highlight "https://admin.${DOMAIN_NAME}"

echo ""
echo_h2 ${COLOR_GREEN}"Super User Credentials${COLOR_RESET}"
echo -n "Username: "
oc get secret ${INSTANCEID}-credentials-superuser -o jsonpath='{.data.username}' -n ${CORENAMESPACE} | base64 --decode && echo ""
echo -n "Password: "
oc get secret ${INSTANCEID}-credentials-superuser -o jsonpath='{.data.password}' -n ${CORENAMESPACE} | base64 --decode && echo ""


echo_h1 "${COLOR_YELLOW}[2/6] Instantiating MongoDB Configuration${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Retriving certificates from mongodb generated scripts${COLOR_RESET}"
mongosvc=$(oc get service -n ${MONGO_NAMESPACE} | grep -i ClusterIP | awk '{printf $1}')
mongopod=$(oc get pods --selector app=$mongosvc -n ${MONGO_NAMESPACE} | sed '2!d' | awk '{printf $1}')
tmpcert=$(oc -n ${MONGO_NAMESPACE} -c mongod exec $mongopod -- openssl s_client -connect localhost:27017 -showcerts 2>&1 < /dev/null  | sed -ne '/BEGIN\ CERTIFICATE/,/END\ CERTIFICATE/p')
mongoCACertificate=$(getcert "$tmpcert" 1 | sed 's/^/\ \ \ \ \ \ \ \ /g')
mongoServerCertificate=$(getcert "$tmpcert" 2 | sed 's/^/\ \ \ \ \ \ \ \ /g')
echo ""
echo "${COLOR_CYAN}Creating Mongo Configuration... ${COLOR_RESET}"

#echo "Mongo CA Cert = ${mongoCACertificate}"
#echo ""
#echo "Mongo Server Cert = ${mongoServerCertificate}"

echo ""
cat << EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: MongoCfg
metadata:
  name: ${INSTANCEID}-mongo-system
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
    - alias: cacert
      crt: |-
${mongoCACertificate}
    - alias: servercert
      crt: |-
${mongoServerCertificate}
  config:
    authMechanism: DEFAULT
    configDb: admin
    credentials:
      secretName: ${INSTANCEID}-usersupplied-mongo-creds-system
    hosts:
      - host: mas-mongo-ce-0.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
      - host: mas-mongo-ce-1.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
      - host: mas-mongo-ce-2.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
  displayName: mas-mongo-ce-0.mas-mongo-ce-svc.mongo.svc.cluster.local
  type: external
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"

sleep 10
while [[ $(oc get MongoCfg ${INSTANCEID}-mongo-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 1; done &
showWorking $!
printf '\b'
mongoowneruid=$(oc get MongoCfg ${INSTANCEID}-mongo-system -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")
mongocfgpassword=$(oc -n ${MONGO_NAMESPACE} get secret mas-mongo-ce-admin-password -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "${COLOR_CYAN}Creating Mongo Configuration Credentials... ${COLOR_RESET}"
echo ""

cat << EOF | oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-usersupplied-mongo-creds-system
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: MongoCfg
      name: ${INSTANCEID}-mongo-system
      uid: ${mongoowneruid}
data:
  password: $(echo -n "${mongocfgpassword}" | base64)
  username: $(echo -n "admin" | base64 )
type: Opaque  
EOF

sleep 5

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"


echo ""
echo -n "${COLOR_GREEN}Mongo Configuration Ready:${COLOR_RESET} "
while [[ $(oc get MongoCfg ${INSTANCEID}-mongo-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo ""
echo ""
echo ""

echo_h1 "${COLOR_YELLOW}[3/6] Instantiating UDS configuration${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Retrieving UDS endpoint${COLOR_RESET}"

uds_endpoint=$(oc get routes uds-endpoint -n "${COMMON_NAMESPACE}" |awk 'NR==2 {print $2}')
uds_url=https://$uds_endpoint

echo ""
echo "${COLOR_CYAN}Retrieving UDS API KEY${COLOR_RESET}"
uds_apikey=$(oc get secret uds-api-key -n "${COMMON_NAMESPACE}" --output="jsonpath={.data.apikey}" | base64 -d)

echo ""
echo "${COLOR_CYAN}Retriving UDS certificates${COLOR_RESET}"

uds_certificates=$(fetchCertificates $uds_endpoint 443)
udsCA1Certificate=$(getcert "$uds_certificates" 1 | sed 's/^/\ \ \ \ \ \ \ \ /g')
udsCA2Certificate=$(getcert "$uds_certificates" 2 | sed 's/^/\ \ \ \ \ \ \ \ /g')
udsCA3Certificate=$(wget -qO - https://letsencrypt.org/certs/isrgrootx1.pem | sed 's/^/\ \ \ \ \ \ \ \ /g')


#echo "UDS Cert 1 = ${udsCA1Certificate}"
#echo ""
#echo "UDS Cert 2 = ${udsCA2Certificate}"
#echo ""
#echo "UDS Cert 3 = ${udsCA3Certificate}"
#echo ""

echo ""
echo "${COLOR_CYAN}Creating UDS configuration...${COLOR_RESET}"
echo ""

cat << EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: BasCfg
metadata:
  name: ${INSTANCEID}-bas-system
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
    - alias: cacert1
      crt: |-
${udsCA1Certificate}
    - alias: cacert2
      crt: |-
${udsCA2Certificate}
    - alias: cacert3
      crt: |-
${udsCA3Certificate}
  config:
    contact:
      email: ${CONTACT_EMAIL}
      firstName: ${CONTACT_FIRSTNAME}
      lastName: ${CONTACT_LASTNAME}
    credentials:
      secretName: ${INSTANCEID}-usersupplied-uds-creds-system
    url: '${uds_url}'
  displayName: System BAS Configuration
EOF

sleep 10

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"

sleep 10

while [[ $(oc get BasCfg ${INSTANCEID}-bas-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 1; done &
showWorking $!
printf '\b'

udsowneruid=$(oc get BasCfg ${INSTANCEID}-bas-system -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")



echo ""
echo  "${COLOR_CYAN}Creating UDS configuration credentials...${COLOR_RESET}"
echo ""

cat << EOF | oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-usersupplied-uds-creds-system
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: BasCfg
      name: ${INSTANCEID}-bas-system
      uid: ${udsowneruid}
stringData:
  api_key: "${uds_apikey}"
type: Opaque  
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo ""
echo -n "${COLOR_GREEN}UDS Configuration Ready:${COLOR_RESET} "
while [[ $(oc get BasCfg ${INSTANCEID}-bas-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

sleep 10

echo ""
echo ""
echo ""

echo_h1 "${COLOR_YELLOW}[4/6] Instantiating SLS configuration${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Retriving SLS url${COLOR_RESET}"
sls_url=$(oc get ConfigMap sls-suite-registration -n ${SLSNAMESPACE} -o jsonpath="{.data.url}")
echo ""
echo $sls_url
echo ""


echo "${COLOR_CYAN}Retriving SLS configuration${COLOR_RESET}"
echo ""
echo ""
slscertificate=$(oc get ConfigMap sls-suite-registration -n ${SLSNAMESPACE} -o jsonpath="{.data.ca}"| sed 's/^/\ \ \ \ \ \ \ \ /g')

echo "${COLOR_CYAN}Retriving SLS registrationKey${COLOR_RESET}"
echo ""
echo ""
slsRegistrationKey=$(oc get ConfigMap sls-suite-registration -n ${SLSNAMESPACE} -o jsonpath="{.data.registrationKey}" | base64 )

echo "${COLOR_CYAN}Creating SLS configuration...${COLOR_RESET}"
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: SlsCfg
metadata:
  name: ${INSTANCEID}-sls-system
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
    - alias: cacert
      crt: |-
${slscertificate}
  config:
    credentials:
      secretName: ${INSTANCEID}-usersupplied-sls-creds-system
    url: >-
      ${sls_url}
  displayName: System SLS Configuration
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"
echo ""

sleep 5
while [[ $(oc get SlsCfg ${INSTANCEID}-sls-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 1; done &
showWorking $!
printf '\b'
slsowneruid=$(oc get SlsCfg ${INSTANCEID}-sls-system -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")

echo ""
echo "${COLOR_CYAN}Creating SLS configuration credentials...${COLOR_RESET}"
echo ""

cat << EOF |oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-usersupplied-sls-creds-system
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: SlsCfg
      name: ${INSTANCEID}-sls-system
      uid: ${slsowneruid}
data:
  registrationKey: ${slsRegistrationKey} 
type: Opaque
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo ""
echo -n "${COLOR_GREEN}SLS Configuration Ready:${COLOR_RESET} "
while [[ $(oc get SlsCfg ${INSTANCEID}-sls-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo ""
echo ""
echo ""


echo_h1 "${COLOR_YELLOW}[5/6] Instantiating Kafka configuration${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Retriving Kafka Certificate${COLOR_RESET}"
echo ""

KAFKAC=$(oc -n ${KAFKA_NAMESPACE} get secret maskafka-cluster-ca-cert -o "jsonpath={.data.ca\.crt}" | base64 -d | sed -E 's/^/\ \ \ \ \ \ \ \ /g')
#KAFKAC2=$(oc get Kafka.kafka.strimzi.io maskafka -n ${KAFKA_NAMESPACE}  -o jsonpath="{.status.listeners[0].certificates[0]}")

echo ""
echo ""

echo "${COLOR_CYAN}Creating Kafka configuration...${COLOR_RESET}"
echo ""

cat <<EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: KafkaCfg
metadata:
  name: ${INSTANCEID}-kafka-system
  namespace: ${CORENAMESPACE}
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${INSTANCEID}
spec:
  displayName: AMQ Streams - ${KAFKA_NAMESPACE}
  config:
    hosts:
      - host: maskafka-kafka-0.maskafka-kafka-brokers.maskafka.svc
        port: 9094
      - host: maskafka-kafka-1.maskafka-kafka-brokers.maskafka.svc
        port: 9094
      - host: maskafka-kafka-2.maskafka-kafka-brokers.maskafka.svc
        port: 9094
    credentials:
      secretName: ${INSTANCEID}-usersupplied-kafka-creds-system
    saslMechanism: SCRAM-SHA-512
  certificates:
    - alias: kafka-ca
      crt: |-
${KAFKAC}
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"
echo ""

sleep 10

while [[ $(oc get KafkaCfg ${INSTANCEID}-kafka-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 5; done &
showWorking $!
printf '\b'

kafkacfgpassword=$(oc -n ${KAFKA_NAMESPACE} get secret mas-user -o jsonpath="{.data.password}" | base64 -d)
kafkauid=$(oc get KafkaCfg ${INSTANCEID}-kafka-system -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")

sleep 5

echo ""
echo "${COLOR_CYAN}Creating Kafka configuration credentials...${COLOR_RESET}"
echo ""
cat << EOF | oc apply -f -
kind: Secret
apiVersion: v1
metadata:
  name: ${INSTANCEID}-usersupplied-kafka-creds-system
  namespace: ${CORENAMESPACE}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: KafkaCfg
      name: ${INSTANCEID}-kafka-system
      uid: ${kafkauid}
data:
  password: $(echo -n "${kafkacfgpassword}" | base64)
  username: $(echo -n "mas-user" | base64 )
type: Opaque  
EOF

echo ""
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo ""
echo -n "${COLOR_GREEN}Kafka Configuration Ready:${COLOR_RESET} "
while [[ $(oc get KafkaCfg ${INSTANCEID}-kafka-system --ignore-not-found=true -n ${CORENAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo ""
echo ""
echo ""

echo_h1 "${COLOR_YELLOW}[6/6] Instantiating of workspace configuration${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Workspace id value = --> $WORKSPACEID${COLOR_RESET}"
echo ""
echo "${COLOR_CYAN}Instance id value = --> $INSTANCEID${COLOR_RESET}"
echo ""
echo ""
echo "${COLOR_CYAN}Creating Workspace configuration...${COLOR_RESET}"
echo ""

cat << EOF |oc apply -f -
apiVersion: core.mas.ibm.com/v1
kind: Workspace
metadata:
  name: ${INSTANCEID}-${WORKSPACEID}
  namespace: ${CORENAMESPACE}
  labels:
    mas.ibm.com/instanceId: ${INSTANCEID}
    mas.ibm.com/workspaceId: ${WORKSPACEID}
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${INSTANCEID}
      uid: ${owneruid}
spec:
  displayName: ${WORKSPACEDISPLAYNAME}
  settings: {}
EOF

echo ""
sleep 10

echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo ""
echo -n "${COLOR_GREEN}Workspace Configuration Ready${COLOR_RESET} "
while [[ $(oc get Workspace ${INSTANCEID}-${WORKSPACEID} --ignore-not-found=true -n ${CORENAMESPACE} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
echo ""


echo_h1 "${COLOR_YELLOW}Maximo Application Suite Info${COLOR_RESET}"


echo_h2 ${COLOR_GREEN}"Administration URL${COLOR_RESET}"
echo ""

admin_endpoint=$(oc get routes ${INSTANCEID}-admin -n "${CORENAMESPACE}" |awk 'NR==2 {print $2}')
admin_url=https://$admin_endpoint

echo "$admin_url"
echo ""


echo_h2 ${COLOR_GREEN}"General URL${COLOR_RESET}"
echo ""

general_endpoint=$(oc get routes ${INSTANCEID}-home -n "${CORENAMESPACE}" |awk 'NR==2 {print $2}')
general_url=https://$general_endpoint

echo "$general_url"
echo ""

echo_h2 ${COLOR_GREEN}"Credentials${COLOR_RESET}"

echo -n "Username: "
oc get secret ${INSTANCEID}-credentials-superuser -o jsonpath='{.data.username}' -n ${CORENAMESPACE} | base64 --decode && echo ""
echo -n "Password: "
oc get secret ${INSTANCEID}-credentials-superuser -o jsonpath='{.data.password}' -n ${CORENAMESPACE} | base64 --decode && echo ""

echo ""
echo ""

echo_h1 "${COLOR_YELLOW}Create MAS OCP Console Link${COLOR_RESET}"
echo ""
echo ""


cat <<EOF | oc apply -f -
apiVersion: console.openshift.io/v1
kind: ConsoleLink
metadata:
  name: maximo
spec:
  href: ${admin_url}
  location: ApplicationMenu
  applicationMenu:
    section: Maximo Application Suite
  text: Admin
EOF

echo ""
echo ""


echo_h2 "${COLOR_GREEN}Installation of Maximo Application Suite Successfully Completed${COLOR_RESET}"

elapsed=$(( SECONDS - start_time ))

eval "echo Script Run Time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"

exit 0


