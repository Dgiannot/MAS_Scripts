#!/bin/bash

######################################
############ MAS Pre-Reqs ############
######################################

# Doug G Modified

# This will install the MAS Pre-reqa
# Set variables in masDG.properties

source masDG.properties
source masDG-script-functions.bash


# script start time
start_time=$SECONDS


ocstatus=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echo "Login to OpenShift to continue MAS Pre-Req installation." 1>&2
  exit 1
fi

echo ""
echo "${COLOR_CYAN}Currently logged into OpenShift as ${ocstatus}${COLOR_RESET}"
echo ""

echo ""


echo_h1 "Starting Installing of Maximo Application Suite Pre-Reqs"

echo "This will take about 1 hr"

echo ""
echo ""

echo_h1 "Install & Configure Redhat AMQ Streams"


oc project ${KAFKA_NAMESPACE} > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project ${KAFKA_NAMESPACE} > /dev/null 2>&1
fi

echo "${COLOR_CYAN}Create Redhat AMQ Streams Operator${COLOR_RESET}"

echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: amq-streams
  namespace: ${KAFKA_NAMESPACE}
spec:
  targetNamespaces:
    - ${KAFKA_NAMESPACE}
EOF

echo ""
echo ""

echo_h2 "${COLOR_GREEN}AMQ Streams Operator Successfully Created${COLOR_RESET}"

sleep 10

echo "${COLOR_CYAN}AMQ Streams Operator will be set up to Automatic on channel 1.8.x${COLOR_RESET}"
echo ""

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: amq-streams.${KAFKA_NAMESPACE}
  namespace: ${KAFKA_NAMESPACE}
spec:
  channel: amq-streams-1.8.x
  installPlanApproval: Automatic
  name: amq-streams
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF


echo ""
echo ""

sleep 30

while : ; do
    echo ""
    oc get subscription amq-streams.${KAFKA_NAMESPACE} -n ${KAFKA_NAMESPACE}	
    echo ""
    installedCSV=$(oc get subscription amq-streams.${KAFKA_NAMESPACE} -n ${KAFKA_NAMESPACE} -o jsonpath="{.status.installedCSV}")
    echo ""
    echo "Red Hat AMQ Streams status is $installedCSV"
    echo ""
    if [[ "$installedCSV" == amqstreams.v* ]]
    then
       echo ""
       echo_h2 "${COLOR_GREEN}Red Hat AMQ Streams Subscription Successfully Deployed${COLOR_RESET}"
       echo ""
        break
    fi
    sleep 20
done

echo ""
echo ""

echo_h2 "${COLOR_GREEN}AMQ Streams Successfully Installed${COLOR_RESET}"

sleep 15

echo ""
echo "${COLOR_CYAN}Configure Kafka & Kafka User${COLOR_RESET}"
echo ""

cat << EOF |oc apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: ${KAFKA_NAMESPACE}
spec:
  kafka:
    version: 2.7.0
    replicas: 3
    resources:
      requests:
        memory: 4Gi
        cpu: "1"
      limits:
        memory: 6Gi
        cpu: "2"
    jvmOptions:
      -Xms: 3072m
      -Xmx: 3072m
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      log.message.format.version: "2.7"
      log.retention.hours: 24
      log.retention.bytes: 1073741824
      log.segment.bytes: 268435456
      log.cleaner.enable: true
      log.cleanup.policy: delete
      auto.create.topics.enable: false
    storage:
      type: jbod
      volumes:
        - id: 0
          type: persistent-claim
          class: ${KAFKASC}
          size: 100Gi
          deleteClaim: true
    authorization:
        type: simple
    listeners:
      - name: tls
        port: 9094
        type: route
        tls: true
        authentication:
          type: scram-sha-512
  zookeeper:
    replicas: 3
    resources:
      requests:
        memory: 2Gi
        cpu: "0.5"
      limits:
        memory: 4Gi
        cpu: "1"
    jvmOptions:
      -Xms: 768m
      -Xmx: 768m
    storage:
      type: persistent-claim
      class: ${KAFKASC}
      size: 20Gi
      deleteClaim: true
  entityOperator:
    userOperator: {}
EOF

echo ""
echo ""
sleep 20
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: mas-user
  labels:
    strimzi.io/cluster: ${KAFKA_NAMESPACE}
spec:
  authentication:
    type: scram-sha-512
  authorization:
    type: simple
    acls:
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: prefix
          type: topic
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: prefix
          type: group
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: literal
          type: topic
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: literal
          type: group
EOF

echo ""
echo ""
echo_h2 "${COLOR_GREEN}AMQ Streams Successfully Configured${COLOR_RESET}"

sleep 15


# Install SBO

echo_h1 "Install Service Bindings Operator(SBO)"

echo ""
echo ""

echo "${COLOR_CYAN}Instantiate Service Bindings Operator(SBO)${COLOR_RESET}"
echo ""
echo ""

cat << EOF |oc apply -f -
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
EOF
echo ""
echo ""

sleep 1m

while : ; do
  oc get po -n openshift-operators | grep service-binding-operator
  operatorStatus=$(oc get po -n openshift-operators | grep service-binding-operator | grep 1/1 | awk '{print $3}')
if [[ $operatorStatus == "Running" ]]; then
  echo "Completed"
  break
fi
  sleep 15
done

echo_h2 "${COLOR_GREEN}SBO Successfully Installed${COLOR_RESET}"


# Install MongoDB

echo_h1 "Install MongoDB"

echo ""
echo ""

mkdir -p logs
rm -rf work/*

./mongo_setup.sh

sleep 10

echo ""
echo ""

echo_h2 "${COLOR_GREEN}MongoDB Successfully Installed${COLOR_RESET}"

sleep 10

# Install UDS

echo_h1 "Install User Data Service"
echo ""


echo "${COLOR_CYAN}Install User Data Services Operand opetator${COLOR_RESET}"
echo ""

cat <<EOF | oc apply -f -
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: user-data-services
  namespace: ${COMMON_NAMESPACE}
spec:
  requests:
    - operands:
        - name: ibm-user-data-services-operator
      registry: common-service
EOF

sleep 10


echo ""
echo "${COLOR_CYAN}Verify UDS installation${COLOR_RESET}"
echo ""


while : ; do
    installedCSV=$(oc get subscription ibm-user-data-services-operator -n ${COMMON_NAMESPACE} -o jsonpath="{.status.currentCSV}" | awk '{print substr($1, 1, length($1)-7)}')
    echo "Installing $installedCSV"
    if [[ "$installedCSV" == user-data-services-operator* ]]
    then
        echo ""
        echo "${COLOR_CYAN}UDS Operator Successfully Installed $installedCSV${COLOR_RESET}"
        break
    fi
    sleep 1m
done

sleep 30

echo ""
echo "${COLOR_CYAN}Create the UDS AnalyticsProxy Instance${COLOR_RESET}"
echo ""

cat <<EOF |oc apply -f -
apiVersion: uds.ibm.com/v1
kind: AnalyticsProxy
metadata:
 name: analyticsproxy
 namespace: ${COMMON_NAMESPACE}
spec:
 license:
   accept: true
 db_archive:
   persistent_storage:
     storage_size: 10G
 kafka:
   storage_size: 5G
   zookeeper_storage_size: 5G
 airgappeddeployment:
   enabled: false
 env_type: lite
 event_scheduler_frequency: '@hourly'
 storage_class: "${STORAGECLASS_RWO}"
 proxy_settings:
   http_proxy: ''
   https_proxy: ''
   no_proxy: ''
 ibmproxyurl: 'https://iaps.ibm.com'
 allowed_domains: '*'
 postgres:
   backup_frequency: '@daily'
   backup_type: incremental
   storage_size: 10G
 tls:
   airgap_host: ''
   uds_host: ''
EOF

echo ""
sleep 30

echo ""
echo -n "${COLOR_GREEN}AnalyticsProxy is Deploying${COLOR_RESET} "
echo ""
while [[ $(oc get analyticsproxies.uds.ibm.com analyticsproxy -n ${COMMON_NAMESPACE} -o jsonpath="{.status.phase}") != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}AnalyticsProxy Successfully Deployed${COLOR_RESET}"

sleep 20


echo ""
echo "${COLOR_CYAN}Generate an API Key to use it for authentication${COLOR_RESET}"
echo ""

cat <<EOF | oc apply -f -
apiVersion: uds.ibm.com/v1
kind: GenerateKey
metadata:
  name: uds-api-key
  namespace: ${COMMON_NAMESPACE}
spec:
  image_pull_secret: uds-images-pull-secret
EOF

check_for_key=$(getGenerateUDSKey)

check_for_key2=$(oc get secret uds-api-key -n ${COMMON_NAMESPACE} --output="jsonpath={.data.apikey}" | base64 -d)





uds_endpoint_url=https://$(oc get routes uds-endpoint -n "${COMMON_NAMESPACE}" |awk 'NR==2 {print $2}')

echo ""
echo "${COLOR_CYAN}Get the API key value and the URLs${COLOR_RESET}"
echo ""
echo ""
echo "===========API KEY=============="
echo ""
echo ""
echoYellow $check_for_key
echo ""
echo ""
#echoYellow $check_for_key2
echo "===========UDS Endpoint URL=============="
echo ""
echo ""
echoYellow $uds_endpoint_url
echo ""
echo ""
echo_h2 "${COLOR_GREEN}IBM User Data Services Successfully Installed${COLOR_RESET}"
sleep 10
echo ""
echo ""

echo_h1 "Install IBM Suite License Analytics Service"
echo ""
echo ""


oc project ${SLSNAMESPACE} > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project ${SLSNAMESPACE} > /dev/null 2>&1
fi

sleep 5

echo ""
echo "${COLOR_CYAN}Instantiate SLS operator${COLOR_RESET}"
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-sls
  namespace: ${SLSNAMESPACE}
spec:
  targetNamespaces:
    - ${SLSNAMESPACE}
EOF

echo ""
echo ""

sleep 10


echo "${COLOR_CYAN}Activate subscription${COLOR_RESET}"
echo ""

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-sls
  namespace: ${SLSNAMESPACE}
  labels:
    operators.coreos.com/ibm-sls.${SLSNAMESPACE}: ''
spec:
  channel: 3.x
  installPlanApproval: Automatic
  name: ibm-sls
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""
echo ""

while [[ $(oc get ClusterServiceVersion -n ${SLSNAMESPACE} --no-headers | grep ibm-sls | awk '{printf $1}') == "" ]];do sleep 15; done 

sls_operator_name=$(oc get ClusterServiceVersion -n ${SLSNAMESPACE} --no-headers | grep ibm-sls | awk '{printf $1}')

while [[ $(oc get ClusterServiceVersion ${sls_operator_name} -n ${SLSNAMESPACE} -o jsonpath="{.status.phase}"  --ignore-not-found=true ) != "Succeeded" ]];do sleep 5; done 


echo ""
echo "${COLOR_CYAN}Using Domain -->  ${DOMAIN_NAME}${COLOR_RESET}"

echo ""
echo "${COLOR_CYAN}Add IBM Entitlement Registry${COLOR_RESET}"
echo ""


oc -n ${SLSNAMESPACE} create secret docker-registry ibm-entitlement \
  --docker-server=cp.icr.io/cp \
  --docker-username=cp \
  --docker-password="${ENTITLEMENT_KEY}"

sleep 5

echo ""
echo ""
echo "${COLOR_CYAN}Create Mongo DB credentials${COLOR_RESET}"
echo ""

MONGO_PASSWORD2=$(oc get secret mas-mongo-ce-admin-password -n ${MONGO_NAMESPACE} --output="jsonpath={.data.password}" | base64 -d)

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: sls-mongo-credentials
  namespace: ${SLSNAMESPACE}
stringData:
  username: "admin"
  password: "${MONGO_PASSWORD2}"
EOF

sleep 10


# Bootstrap Code
echo ""
echo "${COLOR_CYAN}BootStrap License Key${COLOR_RESET}"
echo ""

cat <<EOF | oc create -f -
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: sls-bootstrap
  namespace: ${SLSNAMESPACE}
stringData:
  licensingId: "10005a141d2b"
  licensingKey: |
    SERVER sls.ibm-sls.svc 10005a141d2b 27000
    VENDOR ibmratl
    VENDOR telelogic
    VENDOR rational
    apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: sls-bootstrap
  namespace: ${SLSNAMESPACE}
stringData:
  licensingId: "10005a141d2b"
  licensingKey: |
    SERVER sls.ibm-sls.svc 10005a141d2b 27000
    VENDOR ibmratl
    VENDOR telelogic
    VENDOR rational
    INCREMENT AppPoints ibmratl 1.0 15-jan-2023 1005 vendor_info="0|IBM Maximo AppPoints Pool|0" ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="00D6 25A6 8142 35EC 9382 E00D 4240 D100 7F09 4940 EF0F C78F A7D7 7616 B08C"
    INCREMENT MAS-Admin-Limited ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Admin-Limited,5 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="003F C7E2 98C1 3628 C42E C8B7 5245 6400 A87F E448 BD70 0877 6EC8 0D67 532B"
    INCREMENT MAS-Admin-Base ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Admin-Base,10 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="00F7 2C66 6D42 4808 7697 0A3C EFD2 A900 B9A4 294C 62ED 193C AA3E DBDB AB96"
    INCREMENT MAS-Admin-Premium ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Admin-Premium,15 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="005A 5672 0BFA 7355 3A5D E48C E077 2700 5CB1 3E96 D80E A775 4BDB EB37 8740"
    INCREMENT MAS-API-Limited ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-API-Limited,5 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="00E2 DADA B290 C310 67DF 9027 41F6 B500 E494 28E4 3489 73B3 14F9 0563 34D5"
    INCREMENT MAS-API-Base ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-API-Base,10 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="000A BAAE 2178 12D2 9F75 55E0 FA15 C200 F6A4 0DDF 0340 5EB5 B1BB 0CCC 78FF"
    INCREMENT MAS-API-Premium ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-API-Premium,15 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="0000 AD7B 8A04 5AC7 00A4 F3C3 5DF5 5A00 54E9 3C2B DAC8 40D7 AADA CACB 3225"
    INCREMENT MAS-Limited ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Limited,5 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="00EC A4D8 2626 6649 C142 75DA 055A 4F00 6BA3 5E30 D5BD 4F2B D9FC 80C3 3388"
    INCREMENT MAS-Base ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Base,10 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="0016 5473 8E96 35CE 3640 0CDC CB89 2500 EA28 11E7 1612 4DB6 EA1D 17DA F240"
    INCREMENT MAS-Premium ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Premium,15 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="0058 7DC3 F4B7 BC74 5146 B744 B2A7 E500 FA67 0739 1018 CE6B 0620 6A5F E3B3"
    INCREMENT MAS-Add-On-Limited ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Add-On-Limited,5 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="002A D1B9 7287 53D6 C467 D1DA A844 8B00 A2F9 2C3D D446 CA5C D014 F5E9 5384"
    INCREMENT MAS-Add-On-Base ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Add-On-Base,10 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="0085 D91A D44F 47FC 253F DAFE 302B 1700 1B0C E275 C83D 5E6A 6CD5 B46E 4178"
    INCREMENT MAS-Add-On-Premium ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Add-On-Premium,15 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="0010 A92D 3B6B 7889 7440 EE07 0062 2700 4886 BAB7 4332 6154 C41B 593E 947C"
    INCREMENT MAS-Server-Limited ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Server-Limited,5 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="0048 66DF 7C48 D330 50AC 582D 19B7 4A00 8FBA 2456 AC51 FBA1 FA29 0E02 DFF2"
    INCREMENT MAS-Server-Base ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Server-Base,10 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="0028 BBE1 6F42 7861 5EC5 CBC9 51EB 9900 167B 2555 DF52 F73D 042F 1A17 3505"
    INCREMENT MAS-Server-Premium ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Server-Premium,15 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="00A4 FE90 13F8 52AE 7A43 7F99 367D AE00 527D 3155 35FA A66D A6AA E5C2 A830"
    INCREMENT MAS-SelfService ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-SelfService,0 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="0002 23AE 1380 C408 6F80 19A0 39B6 8600 CB07 363D BD2B 64AE A9F0 94CC 62B5"
    INCREMENT MAS-Limited-Authorized ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Limited-Authorized,2 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="0086 5529 38A3 042A 2C4E 97C6 86C9 4300 03D2 48F1 A0B7 E392 19B2 2641 593F"
    INCREMENT MAS-Base-Authorized ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Base-Authorized,3 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="00FA E801 495A 495B 5673 A979 4B73 E300 70C1 6ADA 887B C880 2B48 87A7 7937"
    INCREMENT MAS-Premium-Authorized ibmratl 1.0 15-jan-2023 1 VENDOR_STRING=IBM:t,AppPoints,1.0,MAS-Premium-Authorized,5 ISSUED=01-Apr-2022 NOTICE="Sales Order Number:IBM_AMERICAS_2022_Internal_5;Account ID:IBM AMERICAS 2022 Internal Account;Customer Name:IBM Customer Name;ICN:Internal_IBM;Purchase Order:Internal_IBM_MAS;Contract:Internal_IBM_MAS;Country:US" SIGN="00DE 9377 7300 6103 D3BD 8780 252A 6200 D491 04C0 A964 3229 31DA 11B7 2CF8"
EOF

echo ""
echo ""
echo "${COLOR_CYAN}Create License Service instance.${COLOR_RESET}"
echo ""

MONGO_CERT=$(oc get configmap mas-mongo-ce-cert-map -n ${MONGO_NAMESPACE} -o jsonpath='{.data.ca\.crt}' | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g')
MONGO_NODES=""
for i in $(seq 0 $((${MONGO_REPLICAS} - 1))); do
  MONGO_NODES="${MONGO_NODES}\n      - host: mas-mongo-ce-${i}.mas-mongo-ce-svc.mongo.svc.cluster.local\n        port: 27017\n"
done
MONGO_NODES=$(echo -ne "${MONGO_NODES}")

sleep 10

cat <<EOF | oc apply -f -
apiVersion: sls.ibm.com/v1
kind: LicenseService
metadata:
  name: sls
  namespace: ${SLSNAMESPACE}
  labels:
    app.kubernetes.io/instance: ibm-sls
    app.kubernetes.io/managed-by: olm
    app.kubernetes.io/name: ibm-sls
spec:
  license:
    accept: true
  domain: ${DOMAIN_NAME}
  mongo:
    authMechanism: DEFAULT
    retryWrites: true
    configDb: admin
    nodes:
${MONGO_NODES}
    secretName: sls-mongo-credentials
    certificates:
      - alias: mongodb
        crt: "${MONGO_CERT}"
  rlks:
    storage:
      class: ${STORAGECLASS_RWO}
      size: 5G
  settings:
    auth:
      enforce: true
    compliance:
      enforce: true
    reconciliation:
      enabled: true
      reconciliationPeriod: 1800
    registration:
      open: true
    reporting:
      maxDailyReports: 90
      maxHourlyReports: 24
      maxMonthlyReports: 12
      reportGenerationPeriod: 3600
      samplingPeriod: 900
EOF



echo ""
echo "${COLOR_CYAN}Waiting for License Service instance to initialize.${COLOR_RESET}"
echo ""

while : ; do
  oc get -n ${SLSNAMESPACE} licenseservice | grep sls | awk '{print $1, $3}'
  operatorStatus3=$(oc get -n ${SLSNAMESPACE} licenseservice | grep sls | awk '{print $3}')
if [[ $operatorStatus3 == "Ready" ]]; then
  echo "Completed"
  break
fi
  sleep 1m
done


echo ""
echo ""

LICENSEID=$(oc get -n ${SLSNAMESPACE} licenseservice | grep sls | awk '{print $5}')

echo ""
echo "${COLOR_CYAN}License ID --> ${LICENSEID}${COLOR_RESET}"
echo ""


echo_h2 "${COLOR_GREEN}IBM Suite License Analytics Successfully Installed${COLOR_RESET}"

sleep 20

echo_h2 "${COLOR_GREEN}Installation of Maximo Application Suite Pre-Reqs completed${COLOR_RESET}"

# script end time

elapsed=$(( SECONDS - start_time ))

eval "echo Script Run Time: $(date -ud "@$elapsed" +'$((%s/3600/24)) days %H hr %M min %S sec')"

exit 0