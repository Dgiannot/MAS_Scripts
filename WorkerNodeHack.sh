#!/bin/bash

# MAS Ansible script to create OCP Cluster on IBM Cloud

#### Environment Variables ####

source masDG.properties
source masDG-script-functions.bash

# IBM Cloud Vars


echo_h1 "Validate OpenShift Status"


ocstatus=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echo "Login to OpenShift to continue cert installation." 1>&2
  exit 1
fi

echo ""
echo "${COLOR_CYAN}Currently logged into OpenShift as ${ocstatus}${COLOR_RESET}"
echo ""



echo_h1 "Log into IBM Cloud"

ibmcloud login --apikey $IBMCLOUD_APIKEY -q --no-region

echo ""
echo ""

echo_h1 "Which OCP Cluster"

echo ""
echo "You are using Cluster ${CLUSER_NAME}"
echo ""


echo_h1 "Add IBM Entitlement to Worker Nodes"

b64_credential=`echo -n "cp:$ENTITLEMENT_KEY" | base64 -w0`
rm -f .dockerconfigjson
oc extract secret/pull-secret -n openshift-config
if [ "$(cat .dockerconfigjson)" = "" ]; then
  echo "creating new .dockerconfigjson"
  oc create secret docker-registry --docker-server=cp.icr.io --docker-username=cp \
    --docker-password=$ENTITLEMENT_KEY --docker-email="not-used" -n openshift-config pull-secret
  oc extract secret/pull-secret -n openshift-config
fi
if [ "$(cat .dockerconfigjson  | grep '.auths' | grep 'cp.icr.io')" = "" ]; then
  echo "updating .dockerconfigjson"
  sed -i -e 's|:{|:{"cp.icr.io":{"auth":"'$b64_credential'"\},|' .dockerconfigjson
fi
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=./.dockerconfigjson
sleep 15


echo_h1 "Reload Worker Nodes"


ibmcloud oc worker ls -c $CLUSTER_NAME
workers=$(ibmcloud oc worker ls -c $CLUSTER_NAME -q | awk '{print $1}')
for wid in $workers; do ibmcloud oc worker replace -c $CLUSTER_NAME -w $wid -f; done


echo -n "${COLOR_GREEN}Checking Worker Status.......:${COLOR_RESET} "

WState=$(ibmcloud oc cluster get --cluster $CLUSTER_NAME | grep "State:" | awk '{print $2}')

M_WS=${WState::-7}

while [[ $M_WS != *"pending"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"




else

echo "CP4D not being Installed"

fi