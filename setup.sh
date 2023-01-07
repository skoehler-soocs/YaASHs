#!/bin/bash
#
# Author: Stefan Koehler ( http://www.soocs.de )
# Description: Linux/Unix wrapper bash script to setup user in target database (= database that should be monitored) or setup user in repository database (= database that polls and stores the samples) 
#              including objects and PL/SQL code
# Use at your own risk!

PATH_SQLPLUS=`which sqlplus`
if [ $? -eq 0 ]
then
    echo "What kind of user do you want to deploy?"
    echo "* Enter 1 for user in target database (= database that should be monitored) - no objects will be installed in the database"
    echo "* Enter 2 for user in repository database (= database that polls and stores the samples) - objects and PL/SQL code will be installed in the database"
    read -p "Your choice: " CHOICE

    if [ ${CHOICE} -eq 1 ] ||  [ ${CHOICE} -eq 2 ]
    then
        read -p "Please enter the connect string with easy connect naming method (e.g. host[:port][/service_name]): " TNS_CONNECT_STRING
        read -p "Please enter an admin user with SYSDBA privileges (e.g. SYS): " TNS_CONNECT_USER
        read -p "Please enter the admin user password: " TNS_CONNECT_PASS
    fi
    if [ ${CHOICE} -eq 1 ]
    then
        echo "Deploying user yaashst in target database"
        ${PATH_SQLPLUS} ${TNS_CONNECT_USER}/${TNS_CONNECT_PASS}@${TNS_CONNECT_STRING} as sysdba @./sql/create_target.sql
    elif [ ${CHOICE} -eq 2 ]
    then
        echo "Deploying user yaashsr in repository database"
        ${PATH_SQLPLUS} ${TNS_CONNECT_USER}/${TNS_CONNECT_PASS}@${TNS_CONNECT_STRING} as sysdba @./sql/create_repository.sql
    else
        echo "Not a valid option in this dialog."
        exit 1
    fi
else
    echo "No SQL*Plus installation could be found. Please make sure that SQL*Plus is in the PATH and functional."
    exit 1
fi
