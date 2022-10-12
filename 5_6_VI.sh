#!/bin/bash


#Script to kick off each MAS Individual Applications  --> Predict

source masDG.properties
source masDG-script-functions.bash


echo_h1 "Validate OpenShift Status"
echo ""

ocstatus
echo ""
echo ""



oc project "gpu-operator-resources" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "gpu-operator-resources" --display-name "NFD Operator Resources" > /dev/null 2>&1
fi

export nfdspace=$(oc config view --minify -o 'jsonpath={..namespace}')




echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  generateName: openshift-nfd
  name: openshift-nfd
  namespace: ${nfdspace}
spec:
  targetNamespaces:
  - ${nfdspace}
EOF


echo ""
sleep 10
echo ""

cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: ${nfdspace}
spec:
  channel: "4.8"
  installPlanApproval: Automatic
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo ""
sleep 4m
echo ""


cat << EOF |oc apply -f -
apiVersion: nfd.openshift.io/v1
kind: NodeFeatureDiscovery
metadata:
  namespace: ${nfdspace}
  name: nfd-instance
spec:
  customConfig:
    configData: |
      #    - name: "more.kernel.features"
      #      matchOn:
      #      - loadedKMod: ["example_kmod3"]
      #    - name: "more.features.by.nodename"
      #      value: customValue
      #      matchOn:
      #      - nodename: ["special-.*-node-.*"]
  instance: ''
  operand:
    image: >-
      registry.redhat.io/openshift4/ose-node-feature-discovery@sha256:680f48b4f7fc280d9869e37e8a3d0ee03c082d893a01193f290d5a73584f529a
    imagePullPolicy: Always
    namespace: openshift-nfd
  workerConfig:
    configData: >
      core:

      #  labelWhiteList:
      #  noPublish: false
        sleepInterval: 60s
      #  sources: [all]
      #  klog:
      #    addDirHeader: false
      #    alsologtostderr: false
      #    logBacktraceAt:
      #    logtostderr: true
      #    skipHeaders: false
      #    stderrthreshold: 2
      #    v: 0
      #    vmodule:
      ##   NOTE: the following options are not dynamically run-time configurable
      ##         and require a nfd-worker restart to take effect after being changed
      #    logDir:
      #    logFile:
      #    logFileMaxSize: 1800
      #    skipLogHeaders: false
      sources:
      #  cpu:
      #    cpuid:
      ##     NOTE: whitelist has priority over blacklist
      #      attributeBlacklist:
      #        - "BMI1"
      #        - "BMI2"
      #        - "CLMUL"
      #        - "CMOV"
      #        - "CX16"
      #        - "ERMS"
      #        - "F16C"
      #        - "HTT"
      #        - "LZCNT"
      #        - "MMX"
      #        - "MMXEXT"
      #        - "NX"
      #        - "POPCNT"
      #        - "RDRAND"
      #        - "RDSEED"
      #        - "RDTSCP"
      #        - "SGX"
      #        - "SSE"
      #        - "SSE2"
      #        - "SSE3"
      #        - "SSE4.1"
      #        - "SSE4.2"
      #        - "SSSE3"
      #      attributeWhitelist:
      #  kernel:
      #    kconfigFile: "/path/to/kconfig"
      #    configOpts:
      #      - "NO_HZ"
      #      - "X86"
      #      - "DMI"
        pci:
          deviceClassWhitelist:
            - "0200"
            - "03"
            - "12"
          deviceLabelFields:
      #      - "class"
            - "vendor"
      #      - "device"
      #      - "subsystem_vendor"
      #      - "subsystem_device"
      #  usb:
      #    deviceClassWhitelist:
      #      - "0e"
      #      - "ef"
      #      - "fe"
      #      - "ff"
      #    deviceLabelFields:
      #      - "class"
      #      - "vendor"
      #      - "device"
      #  custom:
      #    - name: "my.kernel.feature"
      #      matchOn:
      #        - loadedKMod: ["example_kmod1", "example_kmod2"]
      #    - name: "my.pci.feature"
      #      matchOn:
      #        - pciId:
      #            class: ["0200"]
      #            vendor: ["15b3"]
      #            device: ["1014", "1017"]
      #        - pciId :
      #            vendor: ["8086"]
      #            device: ["1000", "1100"]
      #    - name: "my.usb.feature"
      #      matchOn:
      #        - usbId:
      #          class: ["ff"]
      #          vendor: ["03e7"]
      #          device: ["2485"]
      #        - usbId:
      #          class: ["fe"]
      #          vendor: ["1a6e"]
      #          device: ["089a"]
      #    - name: "my.combined.feature"
      #      matchOn:
      #        - pciId:
      #            vendor: ["15b3"]
      #            device: ["1014", "1017"]
      #          loadedKMod : ["vendor_kmod1", "vendor_kmod2"]

EOF


echo ""
sleep 1m
echo ""



cat << EOF |oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gpu-operator-certified
  namespace: ${nfdspace}
spec:
  channel: "V1.82"
  installPlanApproval: Automatic
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
EOF


echo ""
sleep 1m
echo ""

cat << EOF |oc apply -f -
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  migManager:
    enabled: true
    config:
      name: ''
    imagePullSecrets: []
    resources: {}
    repository: nvcr.io/nvidia/cloud-native
    env:
      - name: WITH_REBOOT
        value: 'false'
    securityContext: {}
    version: 'sha256:8cdb793f8a22b076bf0f19818f9d79fe87b121608f1aa28b12a560b6fe13f47e'
    image: k8s-mig-manager
  operator:
    defaultRuntime: crio
    initContainer:
      image: cuda
      imagePullSecrets: []
      repository: nvcr.io/nvidia
      version: 'sha256:15674e5c45c97994bc92387bad03a0d52d7c1e983709c471c4fecc8e806dbdce'
    runtimeClass: nvidia
    deployGFD: true
  dcgm:
    enabled: true
    imagePullSecrets: []
    resources: {}
    hostPort: 5555
    repository: nvcr.io/nvidia/cloud-native
    securityContext: {}
    version: 'sha256:28f334d6d5ca6e5cad2cf05a255989834128c952e3c181e6861bd033476d4b2c'
    image: dcgm
    tolerations: []
  gfd:
    imagePullSecrets: []
    resources: {}
    repository: nvcr.io/nvidia
    env:
      - name: GFD_SLEEP_INTERVAL
        value: 60s
      - name: FAIL_ON_INIT_ERROR
        value: 'true'
    securityContext: {}
    version: 'sha256:bfc39d23568458dfd50c0c5323b6d42bdcd038c420fb2a2becd513a3ed3be27f'
    image: gpu-feature-discovery
  dcgmExporter:
    config:
      name: ''
    imagePullSecrets: []
    resources: {}
    repository: nvcr.io/nvidia/k8s
    env:
      - name: DCGM_EXPORTER_LISTEN
        value: ':9400'
      - name: DCGM_EXPORTER_KUBERNETES
        value: 'true'
      - name: DCGM_EXPORTER_COLLECTORS
        value: /etc/dcgm-exporter/dcp-metrics-included.csv
    securityContext: {}
    version: 'sha256:e37404194fa2bc2275827411049422b93d1493991fb925957f170b4b842846ff'
    image: dcgm-exporter
    tolerations: []
  driver:
    licensingConfig:
      configMapName: ''
      nlsEnabled: false
    enabled: true
    imagePullSecrets: []
    resources: {}
    rdma:
      enabled: false
    repository: nvcr.io/nvidia
    manager:
      env:
        - name: DRAIN_USE_FORCE
          value: 'false'
        - name: DRAIN_POD_SELECTOR_LABEL
          value: ''
        - name: DRAIN_TIMEOUT_SECONDS
          value: 0s
        - name: DRAIN_DELETE_EMPTYDIR_DATA
          value: 'false'
      image: k8s-driver-manager
      imagePullSecrets: []
      repository: nvcr.io/nvidia/cloud-native
      version: 'sha256:907ab0fc008bb90149ed059ac3a8ed3d19ae010d52c58c0ddbafce45df468d5b'
    securityContext: {}
    repoConfig:
      configMapName: ''
      destinationDir: ''
    version: 450.80.02
    virtualTopology:
      config: ''
    image: driver
    nodeSelector:
      nvidia.com/gpu.deploy.driver: 'true'
    podSecurityContext: {}
  devicePlugin:
    imagePullSecrets: []
    resources: {}
    repository: nvcr.io/nvidia
    env:
      - name: PASS_DEVICE_SPECS
        value: 'true'
      - name: FAIL_ON_INIT_ERROR
        value: 'true'
      - name: DEVICE_LIST_STRATEGY
        value: envvar
      - name: DEVICE_ID_STRATEGY
        value: uuid
      - name: NVIDIA_VISIBLE_DEVICES
        value: all
      - name: NVIDIA_DRIVER_CAPABILITIES
        value: all
    securityContext: {}
    version: 'sha256:85def0197f388e5e336b1ab0dbec350816c40108a58af946baa1315f4c96ee05'
    image: k8s-device-plugin
    args: []
  mig:
    strategy: single
  validator:
    imagePullSecrets: []
    resources: {}
    repository: nvcr.io/nvidia/cloud-native
    env:
      - name: WITH_WORKLOAD
        value: 'true'
    securityContext: {}
    version: 'sha256:a07fd1c74e3e469ac316d17cf79635173764fdab3b681dbc282027a23dbbe227'
    image: gpu-operator-validator
  nodeStatusExporter:
    enabled: true
    imagePullSecrets: []
    resources: {}
    repository: nvcr.io/nvidia/cloud-native
    securityContext: {}
    version: 'sha256:a07fd1c74e3e469ac316d17cf79635173764fdab3b681dbc282027a23dbbe227'
    image: gpu-operator-validator
  daemonsets:
    priorityClassName: system-node-critical
    tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
  toolkit:
    enabled: true
    imagePullSecrets: []
    resources: {}
    repository: nvcr.io/nvidia/k8s
    securityContext: {}
    version: 'sha256:b0c84b47d5f95000a842b823ad33dc9aa28f0edfa6d9565c289b61cb1d4a9934'
    image: container-toolkit
EOF




oc describe node | egrep '^Name|^Capacity:|^Allocatable:|nvidia.com/gpu:'


echo ""
echo ""



echo ""
echo_h1 "Deploying Visual Inspection Monitor"
echo ""



oc project "mas-${INSTANCEID}-visualinspection" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${INSTANCEID}-visualinspection" --display-name "MAS - Visual Inspection (${INSTANCEID})" > /dev/null 2>&1
fi

export CORENAMESPACE="mas-${INSTANCEID}-core"
owneruid=$(oc get Suite ${INSTANCEID} -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")
export vsspace="mas-${INSTANCEID}-visualinspection"

echo ""
echo ""
echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"
oc -n "${vsspace}" create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1
echo ""
echo ""




cat << EOF |oc apply -f -
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
allowedCapabilities:
- CHOWN
- DAC_OVERRIDE
- FOWNER
- FSETID
- KILL
- SETGID
- SETUID
- SETPCAP
- NET_BIND_SERVICE
- NET_RAW
- SYS_CHROOT
allowedUnsafeSysctls: null
apiVersion: security.openshift.io/v1
defaultAddCapabilities: null
fsGroup:
  type: MustRunAs
  ranges:
  - max: 65535
    min: 1
groups: []
kind: SecurityContextConstraints
metadata:
  annotations:
    kubernetes.io/description: "This policy is the most restrictive for IBM Maximo Visual Inspection." 
  name: ibm-mas-visualinspection-scc
readOnlyRootFilesystem: false
requiredDropCapabilities: 
- ALL
runAsUser:
  type: MustRunAsRange
  uidRangeMax: 65535
  uidRangeMin: 0
seLinuxContext:
  type: RunAsAny
seccompProfiles: null
supplementalGroups:
  type: MustRunAs
  ranges:
  - max: 65535
    min: 1
users: []
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
EOF

cat << EOF |oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ibm-mas-visualinspection-clusterrole
rules:
- apiGroups:
  - 'security.openshift.io'
  resources:
  - 'securitycontextconstraints'
  resourceNames:
  - 'ibm-mas-visualinspection-scc'
  verbs:
  - use
- apiGroups:
  - ""
  resources:
  - nodes
  - pods
  verbs:
  - list
- apiGroups:
  - ""
  resources:
  - persistentvolumes
  verbs:
  - get
  - list
  - update
  - watch
EOF

cat << EOF |oc apply -f -
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
 name: ibm-mas-visualinspection-clusterrolebinding
subjects:
- kind: ServiceAccount
  name: ibm-mas-visualinspection-operator
  namespace: ${vsspace}
roleRef:
  kind: ClusterRole
  name: ibm-mas-visualinspection-clusterrole
  apiGroup: rbac.authorization.k8s.io
EOF


echo "${COLOR_CYAN}Instantiate Service Bindings Operator(SBO)${COLOR_RESET}"

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




echo ""
echo_h1 "Deploying Visual Inspection Monitor"
echo ""



oc project "mas-${INSTANCEID}-visualinspection" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${INSTANCEID}-visualinspection" --display-name "MAS - Visual Inspection (${INSTANCEID})" > /dev/null 2>&1
fi

export CORENAMESPACE="mas-${INSTANCEID}-core"
owneruid=$(oc get Suite ${INSTANCEID} -n ${CORENAMESPACE} -o jsonpath="{.metadata.uid}")
export vsspace="mas-${INSTANCEID}-visualinspection"

echo ""
echo ""
echo "${COLOR_CYAN}Creating IBM entitlement secret... ${COLOR_RESET}"
oc -n "${vsspace}" create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ENTITLEMENT_KEY} > /dev/null 2>&1
echo ""
echo ""

sleep 10

echo ""
echo ""
echo "${COLOR_YELLOW}Installing VI Operator${COLOR_RESET}"

echo ""
echo ""
echo "${COLOR_CYAN}Operator will be by default set up to manual on channel 8.x${COLOR_RESET}"
echo ""
echo ""

# ibm-visualinspection-operatorgroup 


cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-visualinspection-operatorgroup
  namespace: ${vsspace}
spec:
  targetNamespaces:
    - ${vsspace}
EOF
echo ""
echo ""

echo_h2 "${COLOR_GREEN}Operator Successfully Created${COLOR_RESET}"

sleep 10

echo ""
echo ""
echo "${COLOR_CYAN}Create MAS VI Operator Subscription${COLOR_RESET}"
echo ""
echo ""


cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-visualinspection
  namespace: ${vsspace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas-visualinspection
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""
echo ""
sleep 10

echo ""
echo_h2 "${COLOR_GREEN}MAS VI Operator Subscription Created${COLOR_RESET}"
echo ""
echo ""

echo -n "VI Subscription Created"
while [[ $(oc get Subscription ibm-mas-visualinspection -n ${vsspace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

echo ""
echo ""
echo "${COLOR_CYAN}Approving Manual Installation${COLOR_RESET}"
# Find install plan
echo ""
echo ""
vi_installplan=$(oc get subscription ibm-mas-visualinspection -o jsonpath="{.status.installplan.name}" -n "${monitorspace}")
echo ""
echo ""

echo "${COLOR_MAGENTA}installplan: $vi_installplan${COLOR_RESET}"

echo ""
# Approve install plan
oc patch installplan ${vi_installplan} -n "${vsspace}" --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

echo ""
echo ""
sleep 5

echo -n "VI Subscription Ready "
while [[ $(oc get deployment/ibm-mas-visualinspection-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${vsspace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

echo ""
echo ""
echo "${COLOR_CYAN}Instantiating Visual Inspection App${COLOR_RESET}"
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: VisualInspectionApp
metadata:
  name: ${INSTANCEID}
  namespace: ${vsspace}
   labels:
    mas.ibm.com/instanceId: ${INSTANCEID}
spec:
  bindings:
    edge: application
  settings:
    storage:
      size: 75Gi
      storageClassName: ibmc-file-gold-gid
  size: 1
EOF




echo ""
echo ""

sleep 15m

#echo ""
#echo -n "VI Config Ready "
#while [[ $(oc get VisualInspectionApp ${INSTANCEID} --ignore-not-found=true -n ${vsspace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
#showWorking $!
#printf '\b'
#echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

echo ""
echo ""
echo "${COLOR_CYAN}Creating VI workspace...${COLOR_RESET}"
echo ""
echo ""

cat << EOF |oc apply -f -
apiVersion: apps.mas.ibm.com/v1
kind: VisualInspectionAppWorkspace
metadata:
  name: ${INSTANCEID}-${WORKSPACEID}
  namespace: ${vsspace}
  labels:
    mas.ibm.com/applicationId: visualinspection
    mas.ibm.com/instanceId: ${INSTANCEID}
    mas.ibm.com/workspaceId: ${WORKSPACEID}
spec: {}
EOF

echo ""
echo ""

sleep 5m

#echo ""
#echo -n "${COLOR_GREEN}VI Workspace Ready${COLOR_RESET}"
#while [[ $(oc get VisualInspectionAppWorkspace ${INSTANCEID}-${WORKSPACEID} --ignore-not-found=true -n ${vsspace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
#showWorking $!
#printf '\b'
#echo -e "${COLOR_GREEN} [OK]${COLOR_RESET}"

echo ""
echo ""

echo_h2 "${COLOR_GREEN}Installation of MAS - Visual Inspection Successfully Completed${COLOR_RESET}"

exit 0