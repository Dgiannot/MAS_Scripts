
source masDG.properties
source masDG-script-functions.bash

export managespace="mas-${INSTANCEID}-manage"
export CORENAMESPACE="mas-${INSTANCEID}-core"


cat << EOF |oc apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  labels:
  name: maximo-pod-monitoragent
  namespace: ${managespace}
  mas.ibm.com/appType: serverBundle
  mas.ibm.com/appTypeName: allservers
  mas.ibm.com/applicationId: manage
  mas.ibm.com/instanceId:  ${INSTANCEID}
  mas.ibm.com/workspaceId: ${WORKSPACEID}
spec:
  podMetricsEndpoints:
  - interval: 30s
  targetPort: 9081
  scheme: http
  selector:
  mas.ibm.com/appType: serverBundle
  mas.ibm.com/appTypeName: allservers
  mas.ibm.com/applicationId: manage
  mas.ibm.com/instanceId:  ${INSTANCEID}
  mas.ibm.com/workspaceId: ${WORKSPACEID}
EOF

cat << EOF |oc apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  labels:
  k8s-app: maximo-monitoragent
  name: maximo-pod-monitoragent
  namespace: ${managespace}
spec:
  podMetricsEndpoints:
  - interval: 30s
  targetPort: 9081
  scheme: http
selector:
  mas.ibm.com/appType: serverBundle
  mas.ibm.com/appTypeName: allservers
  mas.ibm.com/applicationId: manage
  mas.ibm.com/instanceId: ${INSTANCEID}
  mas.ibm.com/workspaceId: ${WORKSPACEID}
EOF













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