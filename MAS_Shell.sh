#!/bin/bash


#Script to kick off each MAS install Part

# Doug G Modified

source masDG.properties
source masDG-script-functions.bash
CP4D_INSTALL="Y"

# Record Start Time
start=`date +%s`

if  [  "$CP4D_INSTALL"  =  "Y"  ]
then

# Install CP4D

./$HOME/MASStuff/dg-installs/CP4D/1_ControlPlane.sh

sleep 10

else

# Install IBM Catalogs, Cert Manager, Common Services

./C1.sh

sleep 10

fi

# Install  DB2 Database (IoT, Predict, Monitor)

./$HOME/MASStuff/dg-installs/CP4D/2_DB2_Ansible.sh

sleep 10

# Install Watson Applications for CP4D

if  [  "$CP4D_INSTALL"  =  "Y"  ]
then

./$HOME/MASStuff/dg-installs/CP4D/3_Watson.sh

fi

# Install Oracle Database (Manage)

./$HOME/MASStuff/dg-installs/Oracle_Deployment.sh
sleep 10

# Install MAS Pre-Reqs

./C2_PreReqs.sh
sleep 10

# Install Maximo Application Suite

./C3_MAS.sh
sleep 10

# Install Maximo Application Suite Components

## Install IoT Platform

./$HOME/MASStuff/dg-installs/C4_IoT.sh
sleep 10

## Install Monitor

./$HOME/MASStuff/dg-installs/C4_Monitor.sh
sleep 10

## Install Manage

./$HOME/MASStuff/dg-installs/C4_Manage.sh
sleep 10

## Install Optimization

./$HOME/MASStuff/dg-installs/C4_Optimizer.sh
sleep 10

## Install Predict

./$HOME/MASStuff/dg-installs/C4_Predict.sh
sleep 10

## Install HPU

#./$HOME/MASStuff/dg-installs/C4_HPU.sh

# Install Grafana

./$HOME/MASStuff/dg-installs/C4_Predict.sh
sleep 10

# Record End Date
end=`date +%s`

# Calc Total Time
runtime=$((end-start))

echo_h2 "${COLOR_GREEN}Installation of MAS - Manage Successfully Completed${COLOR_RESET}"
echo ""
echo ""

echo" It took $runtime to complete"
