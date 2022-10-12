cat <<EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-maximo-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "Maximo Operator Catalog" 
  publisher: IBM
  sourceType: grpc
  image: icr.io/cpopen/ibm-maximo-operator-catalog:latest
  updateStrategy:
    registryPoll:
      interval: 45m
EOF


cat <<EOF |oc apply -f -
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: common-service
  namespace: ${COMMON_NAMESPACE}
spec:
  requests:
    - operands:
        - name: ibm-cert-manager-operator
        - name: ibm-mongodb-operator
        - name: ibm-iam-operator
        - name: ibm-monitoring-grafana-operator
        - name: ibm-healthcheck-operator
        - name: ibm-management-ingress-operator
        - name: ibm-licensing-operator
        - name: ibm-commonui-operator
        - name: ibm-events-operator
        - name: ibm-ingress-nginx-operator
        - name: ibm-auditlogging-operator
        - name: ibm-platform-api-operator
        - name: ibm-zen-operator
        - name: ibm-db2u-operator
        - name: cloud-native-postgresql
        - name: ibm-user-data-services-operator
        - name: ibm-cpd-ae-operator-subscription
        - name: ibm-zen-cpp-operator
        - name: ibm-bts-operator
      registry: common-service
EOF


cat <<EOF | oc apply -f -
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: common-service
  namespace: ${CERT_NAMESPACE}
spec:
  requests:
    - operands:
         - name: ibm-licensing-operator
          - name: ibm-events-operator
         - name: ibm-mongodb-operator
      registry: common-service
EOF
echo ""



cat <<EOF |oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dg-cp4d-certificate
  namespace: ${CP4D_NAMESPACE}
spec:
  dnsNames:
    - "cp4d.${DOMAIN_NAME}"
  issuerRef:
    kind: ClusterIssuer
    name: ${CLUSTERISSUER}
  secretName: "dg-cp4d-certificate"
  renewBefore: 720h0m0s # 30 days
  duration: 8760h0m0s # 1 year
EOF



#CP4D_INT_CRT_SCRUB=$(oc get secret -n ${CP4D_NAMESPACE} ibm-nginx-internal-tls-ca -o json | jq -r '.data."cert.crt"' | base64 -d | | sed -ne '/BEGIN\ CERTIFICATE/,/END\ CERTIFICATE/p')
#CP4D_EXT_CRT_SCRUB=$(oc get secret -n ${CP4D_NAMESPACE} dg-cp4d-certificate -o json | jq -r '.data."tls.crt"' | base64 -d | sed -ne '/BEGIN\ CERTIFICATE/,/END\ CERTIFICATE/p')
#CP4D_EXT_KEY_SCRUB=$(oc get secret -n ${CP4D_NAMESPACE} dg-cp4d-certificate -o json | jq -r '.data."tls.key"' | base64 -d | | sed -ne '/BEGIN\ CERTIFICATE/,/END\ CERTIFICATE/p')

tmpcert=$(oc -n ${MONGO_NAMESPACE} -c mongod exec $mongopod -- openssl s_client -connect localhost:27017 -showcerts 2>&1 < /dev/null  | sed -ne '/BEGIN\ CERTIFICATE/,/END\ CERTIFICATE/p')


CP4D_INT_CRT=$(oc get secret -n ${CP4D_NAMESPACE} ibm-nginx-internal-tls-ca -o json | jq -r '.data."cert.crt"' | base64 -d)
CP4D_EXT_CRT=$(oc get secret -n ${CP4D_NAMESPACE} dg-cp4d-certificate -o json | jq -r '.data."tls.crt"' | base64 -d)
CP4D_EXT_KEY_1=$(oc get secret -n ${CP4D_NAMESPACE} dg-cp4d-certificate -o json | jq -r '.data."tls.key"' | base64 -d)


CP4D_EXT_CERT=$(getcert "$CP4D_EXT_CRT" 1 | sed 's/^/\ \ \ \ \ \ \ \ /g')
CP4D_EXT_CA=$(getcert "$CP4D_EXT_CRT" 2 | sed 's/^/\ \ \ \ \ \ \ \ /g')
CP4D_EXT_KEY=$(getcert "$CP4D_EXT_KEY_1" 1 | sed 's/^/\ \ \ \ \ \ \ \ /g')
CP4D_INT_CA=$(getcert "$CP4D_INT_CRT" 1 | sed 's/^/\ \ \ \ \ \ \ \ /g')



cat <<EOF |oc apply -f -
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: dg-cp4d-route
  namespace: ${CP4D_NAMESPACE}
  annotations:
    haproxy.router.openshift.io/balance=roundrobin
spec:
  host: "cp4d.${DOMAIN_NAME}"
  to:
    kind: Service
    name: ibm-nginx-svc
    weight: 100
  port:
    targetPort: ibm-nginx-https-port
  tls:
    termination: reencrypt
    certificate: |-
${CP4D_EXT_CERT}
    key: |
${CP4D_EXT_KEY}
    caCertificate: |-
${CP4D_EXT_CA}
    destinationCACertificate: |-
${CP4D_INT_CA}
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF





## Verify Ingress domain is created or not
for ((time=0;time<30;time++)); do
  oc get route -n openshift-ingress | grep 'router-default' > /dev/null 
  if [ $? == 0 ]; then
     break
  fi
  echo "Waiting up to 30 minutes for public Ingress subdomain to be created: $time minute(s) have passed."
  sleep 60
done


# Quits installation if Ingress public subdomain is still not set after 30 minutes
oc get route -n openshift-ingress | grep 'router-default'
if  [ $? != 0 ]; then
  echo -e "\e[1m Exiting installation as public Ingress subdomain is still not set after 30 minutes.\e[0m"
 




# Modify DB2 Logging Parameters

oc project ${DB2U_NS}

oc rsh pod/c-${DB2U_INST}-db2u-0

sleep 5
su - db2inst1
sleep 5
db2 get db cfg for ${DB2_NAME} | grep LOGARCHMETH
sleep 5
db2 "update database configuration for BLUDB using LOGARCHMETH1 off"
sleep 5
db2 terminate
sleep 15
db2 force application all
sleep 15
db2 deactivate db ${DB2_NAME}
sleep 30
db2stop
sleep 30
db2start
sleep 15
db2 activate db ${DB2_NAME}
sleep 15
db2 get db cfg for ${DB2_NAME} | grep LOGARCHMETH
sleep 15

exit
exit


oc project ${iotnamespace}



cat <<EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-db2oltp-cp4d-operator-catalog-subscription
  namespace: ibm-common-services
spec:
  channel: v1.0
  name: ibm-db2oltp-cp4d-operator
  installPlanApproval: Automatic
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF


cat <<EOF |oc apply -f -
apiVersion: databases.cpd.ibm.com/v1
kind: Db2oltpService
metadata:
  name: db2oltp-cr     
  namespace: cpd-instance     # Replace with the project where you will install Db2
spec:
  license:
    accept: true
    license: Standard    
  version: 4.0.8
EOF




cat <<EOF |oc apply -f -
apiVersion: config.mas.ibm.com/v1
kind: WatsonStudioCfg
metadata:
  name: ${INSTANCEID}-watsonstudio-system
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${INSTANCEID}
  namespace: ${CORENAMESPACE}
spec:
  displayName: WatsonStudio
  certificates:
    - alias: cp4d
      crt: |-
${WATSONC1}       
  config:
    credentials:
      secretName: ${INSTANCEID}-usersupplied-watsons-creds-system
    endpoint: ${cp4d_url_s}
  displayName: WatsonStudio service
EOF











# My Script

1 - OCP_Create.sh  --> Create OCP Cluster
2 - Get OCP Token and Log in
3 - WorkNodeHack.sh --> Reload Worker Nodes on IBM Cloud
