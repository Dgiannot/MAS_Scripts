#!/bin/bash

# Script to add CPU to OCP Cluster on IBM Cloud

#### Environment Variables ####

source masDG.properties
source masDG-script-functions.bash

# IBM Cloud Vars

ENTITLEMENT_KEY=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJJQk0gTWFya2V0cGxhY2UiLCJpYXQiOjE2MjgyNjY3NTMsImp0aSI6IjQ3YTdhMWU4YTkwMzQ1M2Q4NDkzOTFhNzk5ZDBiYjIyIn0.ZL1f1itEuFSSeegRyo0cbSA7IoUVqGxx5iXHjUAkeeQ
CLUSTER_TYPE=roks
CLUSTER_NAME=mas-dg-test
OCP_VERSION=4.8_openshift
OCP_PROVISION_GPU=false
GPU_WORKERPOOL_NAME=gpu
GPU_WORKERS=1
GPU_FLAVOR=mg4c.32x384.2xp100
IBMCLOUD_APIKEY=f6-oGVZKKRlJNIMbYqsDG0QwIbDllH_rlqmi_MxvXKYT
IBMCLOUD_RESOURCEGROUP=DougG
ROKS_ZONE=dal13
ROKS_FLAVOR=b3c.16x64.300gb
ROKS_WORKERS=4
CP4D=Y

# CloudFlare Vars

MAXIMODEMO_ZONE=3dde740466cb2b0732d3b668357528bb
MXSUITE_ZONE=3e25fe51e620b117ea5a1d2ce7155d78
MXAPPSUITE_ZONE=dfb48d506ecf3c75fed914b9693a3107
MXTESTSUITE_ZONE=0e846447bc6b17463e96075b7e94ce5d
SUBDOMAIN="*.dg4"
D_TYPE=A
TTL=3600
PROXIED=false
CLOUDFLARE_EMAIL=Dgianno@hotmail.com
CLOUDFLARE_APIKEY=c98ec74a146c41cf026782dda38c2f17679c6


# Debug Info
# -----------------------------------------------------------------------------
echo "Cluster name ................. $CLUSTER_NAME"
echo "OCP version .................. $OCP_VERSION"
echo "IBM Cloud API key ............ $IBMCLOUD_APIKEY"
echo "IBM Cloud Resource Group ..... $IBMCLOUD_RESOURCEGROUP"
echo "ROKS zone .................... $ROKS_ZONE"
echo "ROKS flavor .................. $ROKS_FLAVOR"
echo "ROKS workers ................. $ROKS_WORKERS"


# IBM Cloud Login
# -----------------------------------------------------------------------------

echo_h1 "Log into IBM Cloud"

ibmcloud login --apikey $IBMCLOUD_APIKEY -q --no-region


echo_h1 "Switch Resource Group"

ibmcloud target -g $IBMCLOUD_RESOURCEGROUP


echo_h1 "Lookup VLANS"

ibmcloud ks vlan ls --zone $ROKS_ZONE --output json
 
echo_h1 "Set VLANS"
sleep 10

VLAN_PR_ID=$(ibmcloud ks vlan ls -zone $ROKS_ZONE | grep private | awk '{print $1}')
VLAN_PR_NUM=$(ibmcloud ks vlan ls -zone $ROKS_ZONE | grep private | awk '{print $2}')
VLAN_PR_ROUTE=$(ibmcloud ks vlan ls -zone $ROKS_ZONE | grep private | awk '{print $4}')
VLAN_PRIVATE="$VLAN_PR_ID-$VLAN_PR_NUM-$VLAN_PR_ROUTE"

VLAN_PB_ID=$(ibmcloud ks vlan ls -zone $ROKS_ZONE | grep public | awk '{print $1}')
VLAN_PB_NUM=$(ibmcloud ks vlan ls -zone $ROKS_ZONE | grep public | awk '{print $2}')
VLAN_PB_ROUTE=$(ibmcloud ks vlan ls -zone $ROKS_ZONE | grep public | awk '{print $4}')
VLAN_PUBLIC="$VLAN_PB_ID-$VLAN_PB_NUM-$VLAN_PB_ROUTE"


echo_h2 "VLAN Private --> $VLAN_PRIVATE"
echo_h2 "VLAN Publlic --> $VLAN_PUBLIC"



if [ $OCP_PROVISION_GPU = "true" ]; then

echo_h1 "Add GPU Pool"

ibmcloud oc worker-pool create classic --hardware dedicated --cluster {$CLUSTER_NAME} --name {$GPU_WORKERPOOL_NAME} --flavor {$GPU_FLAVOR} --size-per-zone {$GPU_WORKERS} --entitlement cloud_pak

sleep 5m

ibmcloud oc zone add classic --zone {$ROKS_ZONE} --cluster {$CLUSTER_NAME} --worker-pool {$GPU_WORKERPOOL_NAME} --private-vlan {$VLAN_PRIVATE} --public-vlan {$VLAN_PUBLIC}

sleep 5m

else 
echo "NO GPU to deploy"
fi

# Wait for Cluster to deploy

echo_h1 "Deploying GPU"


ibmcloud oc cluster get --cluster $CLUSTER_NAME 

sleep 30


ibmcloud ks worker ls --cluster $CLUSTER_NAME 

sleep 30



# Workder Node Hack for CP4D



if [ $CP4D = "Y" ]; then

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
ibmcloud oc worker ls -c $CLUSTER_NAME
workers=$(ibmcloud oc worker ls -c $CLUSTER_NAME -q | awk '{print $1}')
for wid in $workers; do ibmcloud oc worker replace -c $CLUSTER_NAME -w $wid -f; done

else

echo "CP4D not being Installed"

fi








if [ $OCP_PROVISION_GPU = "true" ]; then
  echo "Strings are equal"
else
  echo "Strings are not equal"
fi





# Update CloudFlare DNS 





curl -X GET "https://api.cloudflare.com/client/v4/zones?name=mxtestsuite.com" \
    -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
    -H "X-Auth-Key: $CLOUDFLARE_APIKEY" \
    -H "Content-Type: application/json"




curl -X POST "https://api.cloudflare.com/client/v4/zones/$MXSUITE_ZONE/dns_records" \
     -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
     -H "X-Auth-Key: $CLOUDFLARE_APIKEY" \
     -H "Content-Type: application/json" \
     --data '{"type":"'"$D_TYPE"'","name":"'"$SUBDOMAIN"'","content":"'"$INGRESS_IP"'","ttl":'"$TTL"',"proxied":'"$PROXIED"'}'


List DNS

curl -X GET "https://api.cloudflare.com/client/v4/zones/3e25fe51e620b117ea5a1d2ce7155d78/dns_records" \
     -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
     -H "X-Auth-Key: $CLOUDFLARE_APIKEY" \
     -H "Content-Type: application/json"



