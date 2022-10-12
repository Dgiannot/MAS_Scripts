#!/bin/bash


############################################
############ Oracle 19c Operators #############
############################################

source masDG-script-functions.bash
source masDG.properties

ORA_VERSION=19c
#ORA_VERSION=21c

echo ""
echo ""
echo -n "${COLOR_CYAN}Create Oracle $ORA_VERSION Database Container${COLOR_RESET}"
echo ""
echo ""


oc project "db-${ORA_VERSION}" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "db-${ORA_VERSION}" --display-name "Oracle dB (${ORA_VERSION})" > /dev/null 2>&1
fi

OCPROJECT=$(oc config view --minify -o 'jsonpath={..namespace}')
ORA_NAME=${OCPROJECT}

oc create serviceaccount ${ORA_NAME}
oc adm policy add-scc-to-user privileged -n ${OCPROJECT} -z ${ORA_NAME}

echo ""
echo ""
echo "${COLOR_CYAN}Create Oracle $ORA_VERSION Config Map${COLOR_RESET}"
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: oraproperties
  namespace: ${OCPROJECT}
data:
  INIT_SGA_SIZE: '6000'
  INIT_PGA_SIZE: '6000'
  INIT_CPU_COUNT: '8'
  ORACLE_SID: MAXDB
  ORACLE_PDB: MXDB
  ORACLE_CHARACTERSET: AL32UTF8
  ORACLE_PWD: ${ORA_PASS}
  ORACLE_EDITION: enterprise
  ENABLE_ARCHIVELOG: 'true'
EOF

echo ""
echo ""
echo "${COLOR_CYAN}Create Oracle $ORA_NAME Services${COLOR_RESET}"
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${ORA_NAME}-cip
spec:
  type: ClusterIP
  selector:
    app: ${ORA_NAME}
  ports:
    - name: ${ORA_NAME}-http
      protocol: TCP
      port: 1521
      targetPort: 1521
    - name: ${ORA_NAME}-em
      protocol: TCP
      port: 5500
      targetPort: 5500
EOF

echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${ORA_NAME}-lb
spec:
  selector:
    app: ${ORA_NAME}
  type: LoadBalancer
  ports:
    - name: ${ORA_NAME}-http
      protocol: TCP
      port: 1521
      targetPort: 1521
    - name: ${ORA_NAME}-em
      protocol: TCP
      port: 5500
      targetPort: 5500
EOF

echo ""
echo ""
echo "${COLOR_CYAN}Create Oracle $ORA_VERSION StatefulSet${COLOR_RESET}"
echo ""
echo ""

cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${ORA_NAME} 
spec:
  serviceName: ${ORA_NAME}
  replicas: 1
  selector:
    matchLabels:
      app: ${ORA_NAME}
  template:
    metadata:
      labels:
        app: ${ORA_NAME}
    spec:
      serviceAccount: ${ORA_NAME}
      volumes:
         - name: dshm
           emptyDir:
             medium: Memory
      containers:
        - name: ${ORA_NAME}
          securityContext:
             privileged: true
          image: dgianno/db:19c
          imagePullPolicy: IfNotPresent
          resources:
            requests:
              memory: 4Gi
          ports:
            - name: ${ORA_NAME}-http
              containerPort: 1521
            - name: ${ORA_NAME}-em
              containerPort: 5500
          volumeMounts:
            - name: dshm
              mountPath: "/dev/shm"
            - name: ora-data
              mountPath: "/opt/oracle/oradata"
            - name: ora-setup
              mountPath: "/opt/oracle/scripts/setup"
            - name: ora-startup
              mountPath: "/opt/oracle/scripts/startup"
          env:
            - name: ORACLE_SID
              valueFrom:
                configMapKeyRef:
                  name: oraproperties
                  key: ORACLE_SID
            - name: ORACLE_PDB
              valueFrom:
                configMapKeyRef:
                  name: oraproperties
                  key: ORACLE_PDB
            - name: ORACLE_PWD
              valueFrom:
                configMapKeyRef:
                  name: oraproperties
                  key: ORACLE_PWD
            - name: ENABLE_ARCHIVELOG
              valueFrom:
                configMapKeyRef:
                  name: oraproperties
                  key: ENABLE_ARCHIVELOG
            - name: ORACLE_CHARACTERSET
              valueFrom:
                configMapKeyRef:
                  name: oraproperties
                  key: ORACLE_CHARACTERSET
            - name: ORACLE_EDITION
              valueFrom:
                configMapKeyRef:
                  name: oraproperties
                  key: ORACLE_EDITION
            - name: INIT_SGA_SIZE
              valueFrom:
                configMapKeyRef:
                  name: oraproperties
                  key: INIT_SGA_SIZE
            - name: INIT_PGA_SIZE
              valueFrom:
                configMapKeyRef:
                  name: oraproperties
                  key: INIT_PGA_SIZE
            - name: INIT_CPU_COUNT
              valueFrom:
                configMapKeyRef:
                  name: oraproperties
                  key: INIT_CPU_COUNT
  volumeClaimTemplates:
  - metadata:
      name: ora-startup 
    spec:
      storageClassName: ${SC_RWO}
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi
  - metadata:
      name: ora-setup
    spec:
      storageClassName: ${SC_RWO}
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi
  - metadata:
      name: ora-data
    spec:
      storageClassName: ${SC_RWO}
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 100Gi
EOF

echo ""
echo ""
echo -e "${COLOR_GREEN}Waiting for Oracle Database setup to complete${COLOR_RESET}"

sleep 20m

echo ""
echo ""
echo "${COLOR_CYAN}Obtain Oracle LoadBalancer IP Address${COLOR_RESET}"
echo ""
echo ""


ORACLE_SVC_IP=$(oc get service -n ${OCPROJECT} | grep -i LoadBalancer | awk '{printf $4}')
ORACLE_SVC_PORT=1521


echo ""
echo ""


cd $ORACLE_HOME/network/admin

rm -Rf tnsnames.ora

cat <<EOF >> tnsnames.ora
$jdbcsid =
  (DESCRIPTION =
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL = TCP)(HOST = $ORACLE_SVC_IP)(PORT = $ORACLE_SVC_PORT))
    )
    (CONNECT_DATA =
      (SERVICE_NAME = $jdbcsid)
    )
  )
EOF

sleep 2m


echo "${COLOR_CYAN}Add Oracle Text to Database${COLOR_RESET}"


cd $HOME/MASStuff/dg-installs

echo ""
echo ""

export ORA_USER_PASS=${ORA_PASS}
#alter session set container = MXDB;
# create user c##Maximo identified by xxx;

sqlplus /nolog << EOF
CONNECT sys/${ORA_PASS}@MAXDB as SYSDBA
SPOOL /home/dgianno/MASStuff/dg-installs/logs/oratxt.lst
set echo off 
alter session set "_ORACLE_SCRIPT"=true;
@$ORACLE_HOME/ctx/admin/catctx.sql CTXSYS SYSAUX TEMP NOLOCK;
alter session set "_ORACLE_SCRIPT"=true;
ALTER USER CTXSYS ACCOUNT UNLOCK;
ALTER USER CTXSYS IDENTIFIED BY $ORA_USER_PASS; 
commit;
exit;
EOF


echo ""
echo ""
echo -e "${COLOR_GREEN}Oracle Text Successfully Configured${COLOR_RESET}"
echo ""
echo ""

echo "${COLOR_CYAN}Create Oracle Text Lexer's${COLOR_RESET}"

echo ""
echo ""

sqlplus /nolog << EOF
CONNECT CTXSYS/${ORA_PASS}@MAXDB
SPOOL /home/dgianno/MASStuff/dg-installs/logs/oralexer.lst
set echo off 
alter session set "_ORACLE_SCRIPT"=true;
@$ORACLE_HOME/ctx/admin/defaults/drdefus.sql;
exit;
EOF

echo ""
echo ""
echo "${COLOR_CYAN}Add Maximo User & Create Tablespaces ${COLOR_RESET}"
echo ""
echo ""

sqlplus /nolog << EOF
CONNECT sys/${ORA_PASS}@MAXDB as SYSDBA
SPOOL /home/dgianno/MASStuff/dg-installs/logs/oratxt.lst
set echo off 
alter session set "_ORACLE_SCRIPT"=true;
CREATE TABLESPACE "MAX_DATA" DATAFILE '/opt/oracle/oradata/MAXDB/MAXDATA.dbf' SIZE 5000M NOLOGGING EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO;
CREATE TABLESPACE "MAX_INDEX" DATAFILE '/opt/oracle/oradata/MAXDB/MAXINDEX.dbf' SIZE 5000M NOLOGGING EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO; 
create user Maximo identified by $ORA_USER_PASS;
alter user Maximo default tablespace MAX_DATA quota unlimited on MAX_DATA;
alter user Maximo temporary tablespace temp;
alter user Maximo quota unlimited on MAX_INDEX;
grant create trigger to Maximo;
grant create session to Maximo;
grant create sequence to Maximo;
grant create synonym to Maximo;
grant create table to Maximo;
grant create view to Maximo;
grant create procedure to Maximo;
grant alter session to Maximo;
grant execute on ctxsys.ctx_ddl to Maximo;
grant create job to Maximo;
grant create user to Maximo;
grant drop user to Maximo;
grant create session to Maximo with ADMIN OPTION;
grant alter user to Maximo;
grant select any dictionary to Maximo;
grant create database link to Maximo;
grant create synonym to Maximo;
commit;
exit;
EOF

echo ""
echo ""

sqlplus /nolog << EOF
CONNECT Maximo/${ORA_PASS}@MAXDB
SPOOL /home/dgianno/MASStuff/dg-installs/logs/maxuser.lst
set echo off 
alter session set "_ORACLE_SCRIPT"=true;
call ctx_ddl.drop_preference('global_lexer');
call ctx_ddl.drop_preference('default_lexer');
call ctx_ddl.drop_preference('english_lexer');
call ctx_ddl.drop_preference('chinese_lexer');
call ctx_ddl.drop_preference('japanese_lexer');
call ctx_ddl.drop_preference('korean_lexer');
call ctx_ddl.drop_preference('german_lexer');
call ctx_ddl.drop_preference('dutch_lexer');
call ctx_ddl.drop_preference('swedish_lexer');
call ctx_ddl.drop_preference('french_lexer');
call ctx_ddl.drop_preference('italian_lexer');
call ctx_ddl.drop_preference('spanish_lexer');
call ctx_ddl.drop_preference('portu_lexer');
call ctx_ddl.create_preference('default_lexer','basic_lexer');
call ctx_ddl.create_preference('english_lexer','basic_lexer');
call ctx_ddl.create_preference('chinese_lexer','chinese_lexer');
call ctx_ddl.create_preference('japanese_lexer','japanese_lexer');
call ctx_ddl.create_preference('korean_lexer','korean_morph_lexer');
call ctx_ddl.create_preference('german_lexer','basic_lexer');
call ctx_ddl.create_preference('dutch_lexer','basic_lexer');
call ctx_ddl.create_preference('swedish_lexer','basic_lexer');
call ctx_ddl.create_preference('french_lexer','basic_lexer');
call ctx_ddl.create_preference('italian_lexer','basic_lexer');
call ctx_ddl.create_preference('spanish_lexer','basic_lexer');
call ctx_ddl.create_preference('portu_lexer','basic_lexer');
call ctx_ddl.create_preference('global_lexer', 'multi_lexer');
call ctx_ddl.add_sub_lexer('global_lexer','default','default_lexer');
call ctx_ddl.add_sub_lexer('global_lexer','english','english_lexer','en');
call ctx_ddl.add_sub_lexer('global_lexer','simplified chinese','chinese_lexer','zh');
call ctx_ddl.add_sub_lexer('global_lexer','japanese','japanese_lexer',null);
call ctx_ddl.add_sub_lexer('global_lexer','korean','korean_lexer',null);
call ctx_ddl.add_sub_lexer('global_lexer','german','german_lexer','de');
call ctx_ddl.add_sub_lexer('global_lexer','dutch','dutch_lexer',null);
call ctx_ddl.add_sub_lexer('global_lexer','swedish','swedish_lexer','sv');
call ctx_ddl.add_sub_lexer('global_lexer','french','french_lexer','fr');
call ctx_ddl.add_sub_lexer('global_lexer','italian','italian_lexer','it');
call ctx_ddl.add_sub_lexer('global_lexer','spanish','spanish_lexer','es');
call ctx_ddl.add_sub_lexer('global_lexer','portuguese','portu_lexer',null);
exit;
EOF

echo ""
echo ""
echo -e "${COLOR_GREEN}Maximo User / Tablespaces Successfully Created${COLOR_RESET}"
echo ""
echo ""


echo_h2 "${COLOR_GREEN}Installation & Configuration of Oracle ${ORA_VERSION} Complete${COLOR_RESET}"

exit 0