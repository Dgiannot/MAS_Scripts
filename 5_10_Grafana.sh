#!/bin/bash

#Script to kick off Grafana  

source masDG.properties
source masDG-script-functions.bash

echo_h1 "Validate OpenShift Status"
echo ""

ocstatus
echo ""
echo ""











apiVersion: v1
kind: ConfigMap
data:
  config.yaml: |
    prometheusOperator:
      baseImage: quay.io/coreos/prometheus-operator
      prometheusConfigReloaderBaseImage: quay.io/coreos/prometheus-config-reloader
      configReloaderBaseImage: quay.io/coreos/configmap-reload
    prometheusK8s:
      retention: "{{ prometheus_retention_period }}"
      baseImage: openshift/prometheus
      volumeClaimTemplate:
        spec:
          storageClassName: "{{ prometheus_storage_class }}"
          resources:
            requests:
              storage: "{{ prometheus_storage_size }}"
    alertmanagerMain:
      baseImage: openshift/prometheus-alertmanager
      volumeClaimTemplate:
        spec:
          storageClassName: "{{ prometheus_alertmgr_storage_class }}"
          resources:
            requests:
              storage: "{{ prometheus_alertmgr_storage_size }}"
    enableUserWorkload: true
    nodeExporter:
      baseImage: openshift/prometheus-node-exporter
    kubeRbacProxy:
      baseImage: quay.io/coreos/kube-rbac-proxy
    kubeStateMetrics:
      baseImage: quay.io/coreos/kube-state-metrics
    grafana:
      baseImage: grafana/grafana
    auth:
      baseImage: openshift/oauth-proxy
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
---
apiVersion: v1
kind: ConfigMap
data:
  config.yaml: |
    prometheus:
      retention: "{{ prometheus_userworkload_retention_period }}"
      volumeClaimTemplate:
        spec:
          storageClassName: "{{ prometheus_userworkload_storage_class }}"
          resources:
            requests:
              storage: "{{ prometheus_userworkload_storage_size }}"
metadata:
  name: user-workload-monitoring-config
  namespace: openshift-user-workload-monitoring

































echo_h1 "Deploying Grafana"
echo ""

oc project "grafana" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "grafana" --display-name "Grafana" > /dev/null 2>&1
fi

export gfspace=$(oc config view --minify -o 'jsonpath={..namespace}')

echo ""
echo "${COLOR_YELLOW}Installing Grafana Operator${COLOR_RESET}"

echo ""
echo ""

echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: grafana-operator
  namespace: ${gfspace}
spec:
  targetNamespaces:
    - ${gfspace}
EOF

echo ""
echo ""

echo_h2 "${COLOR_GREEN}Grafana Operator Successfully Created${COLOR_RESET}"

sleep 10
echo ""
echo "${COLOR_CYAN}Create Grafana Operator Subscription${COLOR_RESET}"
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: grafana-operator
  namespace: ${gfspace}
spec:
  channel: v4
  installPlanApproval: Automatic
  name: grafana-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
  config:
    env:
      - name: "DASHBOARD_NAMESPACES_ALL"
        value: "true"
EOF

echo ""
echo ""

echo ""
echo ""            
echo -n "Grafana Subscription Ready "
while [[ $(oc get deployment/grafana-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${gfspace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

sleep 10

echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: grafana-operator
rules:
  - apiGroups:
      - ""
    resources:
      - events
    verbs:
      - get
      - list
      - watch
      - create
      - delete
      - update
      - patch
  - apiGroups:
      - integreatly.org
    resources:
      - grafanadashboards
      - grafanadatasources
      - grafanadatasources/status
    verbs:
      - get
      - list
      - create
      - update
      - delete
      - deletecollection
      - watch
EOF

echo ""
echo ""
sleep 10 
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: grafana-operator
roleRef:
  name: grafana-operator
  kind: ClusterRole
  apiGroup: ""
subjects:
  - kind: ServiceAccount
    name: grafana-operator-controller-manager
    namespace: ${gfspace}
EOF

echo ""
echo ""

sleep 10

cat << EOF |oc apply -f -
apiVersion: integreatly.org/v1alpha1
kind: Grafana
metadata:
  name: mas-grafana
  namespace: ${gfspace}
spec:
  config:
    auth:
      disable_login_form: false
      disable_signout_menu: true
    auth.anonymous:
      enabled: true
    log:
      level: warn
      mode: console
  dashboardLabelSelector:
  - matchExpressions:
    - key: app
      operator: In
      values:
      - grafana
  dataStorage:
    accessModes:
    - ReadWriteOnce
    class: ${SC_RWX}
    size: 25G
  ingress:
    enabled: true
EOF



