/*
Author: Stefan Koehler ( http://www.soocs.de )
Description: SQL script for creating a database user in the target database with needed privileges - no objects are installed
Use at your own risk!
*/

-- WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET VERIFY OFF

accept YAASHS_USER default yaashst prompt "Please enter the username (default yaashst): "
prompt Database user &YAASHS_USER will be dropped (if it already exists) and created
accept OK_PROMPT prompt "Press any key to continue ..."
accept YAASHS_PASS default yaashst prompt "Please enter the &YAASHS_USER user password (default yaashst): "
accept YAASHS_TBS default users prompt "Please enter the default tablespace for user &YAASHS_USER (default users): "

---------------------------------------------------------------------------------------------
-- (Re-)Create user
---------------------------------------------------------------------------------------------
DROP USER &YAASHS_USER CASCADE;
CREATE USER &YAASHS_USER IDENTIFIED BY &YAASHS_PASS DEFAULT TABLESPACE &YAASHS_TBS;

---------------------------------------------------------------------------------------------
-- Permissions
---------------------------------------------------------------------------------------------
GRANT CREATE SESSION TO &YAASHS_USER;
GRANT CREATE SYNONYM TO &YAASHS_USER;
GRANT SELECT ON v_$database TO &YAASHS_USER;
GRANT SELECT ON v_$instance TO &YAASHS_USER;
GRANT SELECT ON v_$mystat TO &YAASHS_USER;
GRANT SELECT ON v_$parameter TO &YAASHS_USER;
GRANT SELECT ON v_$pdbs TO &YAASHS_USER;
GRANT SELECT ON v_$session TO &YAASHS_USER;
GRANT SELECT ON v_$sql TO &YAASHS_USER;

quit;
