#!/bin/bash

# Script to create OCP Cluster on IBM Cloud

#### Environment Variables ####

source masDG.properties
source masDG-script-functions.bash

echo ""
echo ""

# Debug Info
# -----------------------------------------------------------------------------
echo "Cluster name ................. $CLUSTER_NAME"
echo "OCP version .................. $OCP_VERSION"
echo "IBM Cloud API key ............ $IBMCLOUD_APIKEY"
echo "IBM Cloud Resource Group ..... $IBMCLOUD_RESOURCEGROUP"
echo "ROKS zone .................... $ROKS_ZONE"
echo "ROKS flavor .................. $ROKS_FLAVOR"
echo "ROKS workers ................. $ROKS_WORKERS"
echo ""


# IBM Cloud Login
# -----------------------------------------------------------------------------

echo_h1 "Log into IBM Cloud"
echo ""
echo ""

ibmcloud login --apikey $IBMCLOUD_APIKEY -q --no-region

echo ""
echo ""
sleep 10

echo_h1 "Switch Resource Group"

ibmcloud target -g $IBMCLOUD_RESOURCEGROUP

echo ""
echo ""
sleep 10

echo_h1 "Lookup VLANS"

ibmcloud ks vlan ls --zone $ROKS_ZONE --output json

echo ""

echo_h1 "Set VLANS"

echo ""
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
echo_h2 "VLAN Public --> $VLAN_PUBLIC"
echo ""
echo ""
sleep 10

echo_h1 "Create OpenShift Cluster"
echo ""

#ibmcloud oc cluster create classic --hardware shared --entitlement cloud_pak --name $CLUSTER_NAME --version $OCP_VERSION --zone $ROKS_ZONE --flavor $ROKS_FLAVOR --workers $ROKS_WORKERS --public-vlan $VLAN_PB_ID

ibmcloud oc cluster create classic --hardware shared --entitlement cloud_pak --name $CLUSTER_NAME --version $OCP_VERSION --zone $ROKS_ZONE --flavor $ROKS_FLAVOR --workers $ROKS_WORKERS --private-vlan $VLAN_PR_ID --public-vlan $VLAN_PB_ID

echo ""

sleep 10

echo -e "${COLOR_GREEN}OpenShift Cluster Creation Initiated${COLOR_RESET}"
echo ""

echo ""

echo_h1 "Deploying OCP Cluster"
echo ""

echo " This will take about 1 hr"
echo ""


echo_h1 "${COLOR_GREEN}OpenShift Master Nodes Deploying.......: ${COLOR_RESET} "
echo ""
while [[ $(ibmcloud oc cluster get --cluster $CLUSTER_NAME | grep "Master State" | awk '{print $3}') != *"deployed"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo ""
echo ""
echo_h2 "${COLOR_GREEN}OCP Master Nodes Successfully Deployed${COLOR_RESET}"

echo ""
echo ""

echo_h1 "${COLOR_GREEN}OpenShift Worker Nodes Deploying.......: ${COLOR_RESET} "
echo ""

d=$(ibmcloud oc cluster get --cluster $CLUSTER_NAME | awk '{print $2}')
array=($d)
#echo ${array[3]}
d2=${array[3]}

while [[ $d2 != *"normal"* ]];do 

d=$(ibmcloud oc cluster get --cluster $CLUSTER_NAME | awk '{print $2}')
array=($d)
d2=${array[3]}
sleep 10; done &
showWorking $!
printf '\b'
echo ""
echo ""
echo -e "${COLOR_GREEN}OCP Cluster Successfully Deployed & in Normal State${COLOR_RESET}"


sleep 5

echo ""
echo_h1 "Worker Node Status"

ibmcloud oc worker ls -c $CLUSTER_NAME

echo ""

sleep 5

echo_h1 "Ingress Status"

echo ""

echo -n "${COLOR_GREEN}Ingress Deploying.......:${COLOR_RESET} "
while [[ $(ibmcloud oc cluster get --cluster $CLUSTER_NAME | grep "Ingress Subdomain" | awk '{print $3}') != *".appdomain.cloud"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"



echo ""

sleep 10

echo_h1 "Cluster Status"

echo ""

ibmcloud oc cluster get --cluster $CLUSTER_NAME

OCP_DOMAIN=$(ibmcloud oc cluster get --cluster $CLUSTER_NAME | grep Subdomain | awk '{print $3}')
OCP_URL=https://console-openshift-console.$OCP_DOMAIN
INGRESS_IP=$(ping -c 2 $OCP_DOMAIN| awk -F '[()]' '/PING/ {print $2}')


echo ""

echo_h1 "OpenShift Console"

echo ""

echo_h2 $OCP_URL

#exit 0

# Update CloudFlare DNS 

echo ""

echo_h1 "Create CloudFlare DNS A Record for Subdomain $SUBDOMAIN"

echo ""

curl -X POST "https://api.cloudflare.com/client/v4/zones/$DOMAIN_ZONE/dns_records" \
     -H "X-Auth-Email: $CLOUDFLAREID" \
     -H "X-Auth-Key: $CLOUDFLAREAPI" \
     -H "Content-Type: application/json" \
     --data '{"type":"'"$D_TYPE"'","name":"'"$SUBDOMAIN"'","content":"'"$INGRESS_IP"'","ttl":'"$TTL"',"proxied":'"$PROXIED"'}'


echo ""
echo ""
echo -e "${COLOR_GREEN}Sub Domain --> ${SUBDOMAIN} Registered with CloudFlare${COLOR_RESET}"

echo ""
echo ""

echo_h2 "${COLOR_GREEN}OCP Cluster Created & DNS Registered${COLOR_RESET}"
exit 0




