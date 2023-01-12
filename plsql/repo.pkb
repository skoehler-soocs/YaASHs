CREATE OR REPLACE PACKAGE BODY yaashsr.repo AS
    /*
    Author: Stefan Koehler ( http://www.soocs.de )
    Description: PL/SQL package body for repo package
                 The repo PL/SQL package contains the functionality for managing the target databases, altering the configuration and logging messages/errors in the repository database
    Use at your own risk!
    */


    PROCEDURE add_target (p_name VARCHAR2, p_host_name VARCHAR2, p_listener_port NUMBER, p_service_name VARCHAR2, p_instance_number NUMBER, p_instance_name VARCHAR2, p_username VARCHAR2, p_password VARCHAR2) IS
        l_db_dom_num       NUMBER;
        l_db_dom_value     global_name.global_name%TYPE;
        l_dbid             targets.dbid%TYPE;
        l_db_link_name     targets.db_link_name%TYPE;
        l_db_link_name_dom targets.db_link_name%TYPE;
        l_is_pdb           targets.is_pluggable%TYPE;
        l_is_rac           targets.is_rac%TYPE;
        l_sqltext          VARCHAR2(4000);
        l_version_num      NUMBER;
    BEGIN
        -- Temporary database link is needed because final attributes like dbid are not known yet (it must be a single instance if p_instance_name IS NULL)
        l_db_link_name := 'DBL_' || p_name || '_' || p_instance_number || '_TMP';
        IF p_instance_name IS NULL THEN
            l_sqltext := 'CREATE DATABASE LINK ' || l_db_link_name || ' CONNECT TO ' || p_username || ' IDENTIFIED BY "' || p_password || '" USING ''' 
                         || p_host_name || ':' || p_listener_port || '/' || p_service_name || '''';
        ELSE
            l_sqltext := 'CREATE DATABASE LINK ' || l_db_link_name || ' CONNECT TO ' || p_username || ' IDENTIFIED BY "' || p_password || '" USING ''' 
                         || p_host_name || ':' || p_listener_port || '/' || p_service_name || '/' || p_instance_name || '''';            
        END IF;
        EXECUTE IMMEDIATE l_sqltext;
        
        -- Database links are implicitly created with domain name if global_name includes FQDN
        SELECT instr(global_name, '.'), substr(global_name, instr(global_name, '.') + 1) INTO l_db_dom_num, l_db_dom_value FROM global_name;
        IF l_db_dom_num = 0 THEN
            l_db_link_name_dom := l_db_link_name;
        ELSE
            l_db_link_name_dom := l_db_link_name || '.' || l_db_dom_value;
        END IF;
        
        -- Work-around for determining if target database is NONCDB, CDB or PDB because sys_context() does not work over database link
        l_sqltext := 'SELECT to_number(substr(version,0,2)) FROM v$instance@' || l_db_link_name_dom;
        EXECUTE IMMEDIATE l_sqltext INTO l_version_num;
        IF l_version_num < 12 THEN
            l_is_pdb := 'NONCDB';
        ELSE
            l_sqltext := q'[SELECT CASE WHEN CON_ID = 0 THEN 'NONCDB' WHEN CON_ID = 1 THEN 'CDB' ELSE 'PDB' END is_pdb FROM v$session@]' || l_db_link_name_dom || 
                         q'[ WHERE sid IN (SELECT sid FROM v$mystat@]' || l_db_link_name_dom || ')';
            EXECUTE IMMEDIATE l_sqltext INTO l_is_pdb;    
        END IF;
        
        l_sqltext := q'[SELECT decode(value,'FALSE','NO','YES') FROM v$parameter@]' || l_db_link_name_dom || q'[ WHERE name = 'cluster_database']';
        EXECUTE IMMEDIATE l_sqltext INTO l_is_rac;

        IF l_is_pdb = 'PDB' THEN
            l_sqltext := q'[SELECT dbid FROM v$pdbs@]' || l_db_link_name_dom || q'[ WHERE name = ']' || p_name || q'[']' ;
        ELSE
            l_sqltext := q'[SELECT dbid FROM v$database@]' || l_db_link_name_dom;
        END IF;
        EXECUTE IMMEDIATE l_sqltext INTO l_dbid;
        
        l_sqltext := 'DROP DATABASE LINK ' || l_db_link_name;
        EXECUTE IMMEDIATE l_sqltext;
        
        l_db_link_name := 'DBL_' || p_name || '_' || p_instance_number || '_' || l_dbid;
        
        -- Database links are implicitly created with domain name if global_name includes FQDN
        IF l_db_dom_num = 0 THEN
            l_db_link_name_dom := l_db_link_name;
        ELSE
            l_db_link_name_dom := l_db_link_name || '.' || l_db_dom_value;
        END IF;
        
        INSERT INTO targets(name,dbid,is_pluggable,is_rac,host_name,listener_port,instance_number,service_name,instance_name,db_link_name,status)
                     VALUES(p_name,l_dbid,l_is_pdb,l_is_rac,p_host_name,p_listener_port,p_instance_number,p_service_name,p_instance_name,l_db_link_name_dom,'ADDED');
        COMMIT;
        
        IF l_is_rac = 'FALSE' THEN
            l_sqltext := 'CREATE DATABASE LINK ' || l_db_link_name || ' CONNECT TO ' || p_username || ' IDENTIFIED BY "' || p_password || '" USING ''' 
                         || p_host_name || ':' || p_listener_port || '/' || p_service_name || '''';
        ELSE
            l_sqltext := 'CREATE DATABASE LINK ' || l_db_link_name || ' CONNECT TO ' || p_username || ' IDENTIFIED BY "' || p_password || '" USING ''' 
                         || p_host_name || ':' || p_listener_port || '/' || p_service_name || '/' || p_instance_name || '''';            
        END IF;
        EXECUTE IMMEDIATE l_sqltext;
        
        change_target_status(p_name,p_instance_number,l_dbid,'ENABLED');
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            error_message('Error during adding database ' || p_name || ' to repository: ' || SQLCODE);
        WHEN OTHERS THEN
            error_message('Error during adding database ' || p_name || ' to repository: ' || SQLCODE);
            l_sqltext := 'DROP DATABASE LINK ' || l_db_link_name;
            EXECUTE IMMEDIATE l_sqltext;
    END add_target;


    PROCEDURE alter_config (p_name VARCHAR2, p_value VARCHAR2) IS
        l_config_value configuration.value%TYPE;
        l_count        NUMBER;
        l_valid_v      NUMBER DEFAULT 0;
    BEGIN
        SELECT count(*) INTO l_count FROM configuration where name = upper(p_name);
        IF l_count = 0 THEN
            error_message('Error during changing configuration in repository database - invalid parameter ' || p_name);
        ELSE
            CASE upper(p_name)
                WHEN 'RETENTION_DAYS' THEN
                    -- Be aware that validate_conversion() breaks the PL/SQL compiler ("PLS-00801 ASSERT at file pdz2.c, line 5383; The_Exp is null") in case of compile for debug
                    IF validate_conversion(p_value as NUMBER) = 1 AND p_value BETWEEN 1 AND 31 THEN
                        l_valid_v := 2;
                    END IF;          
                WHEN 'SAMPLE_IDLE' THEN
                    IF upper(p_value) = 'YES' OR upper(p_value) = 'NO' THEN
                        l_valid_v := 2;
                    END IF;
                WHEN 'SAMPLEFREQ_SEC' THEN
                    -- Be aware that validate_conversion() breaks the PL/SQL compiler ("PLS-00801 ASSERT at file pdz2.c, line 5383; The_Exp is null") in case of compile for debug                
                    IF validate_conversion(p_value as NUMBER) = 1 THEN
                        SELECT value INTO l_config_value FROM configuration WHERE name = 'SAMPLEDURA_SEC';
                        IF (l_config_value * p_value) >= 3600 OR mod(l_config_value * p_value,60) > 0 THEN
                            l_valid_v := 1;
                        ELSE
                            l_valid_v := 2;
                        END IF;
                    END IF;
                WHEN 'SAMPLEDURA_SEC' THEN
                    -- Be aware that validate_conversion() breaks the PL/SQL compiler ("PLS-00801 ASSERT at file pdz2.c, line 5383; The_Exp is null") in case of compile for debug                
                    IF validate_conversion(p_value as NUMBER) = 1 THEN
                        SELECT value INTO l_config_value FROM configuration WHERE name = 'SAMPLEFREQ_SEC';
                        -- Needs to be lower than 3600 seconds and a full minute value because of used dbms_scheduler job option "repeat_interval => FREQ=MINUTELY; INTERVAL=<X>"
                        IF (l_config_value * p_value) >= 3600 OR mod(l_config_value * p_value,60) > 0 THEN
                            l_valid_v := 1;
                        ELSE
                            l_valid_v := 2;
                        END IF;
                    END IF;                
            END CASE; 
            
            CASE l_valid_v
                WHEN 0 THEN
                    error_message('Error during changing configuration in repository database - invalid value ' || p_value || ' for parameter ' || p_name);
                WHEN 1 THEN
                    error_message('Error during changing configuration in repository database - invalid value ' || p_value || ' for parameter ' || p_name || '. SAMPLEFREQ_SEC x SAMPLEDURA_SEC needs to be less than 3600 seconds but also a full minute value');
                WHEN 2 THEN
                    UPDATE configuration SET value = upper(p_value) WHERE name = upper(p_name);
                    COMMIT;
            END CASE;
        END IF;
    END alter_config;

    
    PROCEDURE check_target (p_name VARCHAR2, p_instance_number NUMBER, p_dbid NUMBER) IS
        l_dbid        targets.dbid%TYPE;
        l_instance_n  targets.instance_number%TYPE;
        l_is_pdb      targets.is_pluggable%TYPE;
        l_is_rac      targets.is_rac%TYPE;
        l_sqltext     VARCHAR2(4000);
        l_targets_row targets%ROWTYPE;
        l_version_num NUMBER;
    BEGIN
        SELECT * INTO l_targets_row FROM targets WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;

        -- Work-around for determining if target database is NONCDB, CDB or PDB because sys_context() does not work over database link
        l_sqltext := 'SELECT to_number(substr(version,0,2)) FROM v$instance@' || l_targets_row.db_link_name;
        EXECUTE IMMEDIATE l_sqltext INTO l_version_num;
        IF l_version_num < 12 THEN
            l_is_pdb := 'NONCDB';
        ELSE
            l_sqltext := q'[SELECT CASE WHEN CON_ID = 0 THEN 'NONCDB' WHEN CON_ID = 1 THEN 'CDB' ELSE 'PDB' END is_pdb FROM v$session@]' || l_targets_row.db_link_name || 
                         q'[ WHERE sid IN (SELECT sid FROM v$mystat@]' || l_targets_row.db_link_name || ')';
            EXECUTE IMMEDIATE l_sqltext INTO l_is_pdb;    
        END IF;
        
        IF l_is_pdb != l_targets_row.is_pluggable THEN
            error_message('Found inconsistency between stored meta-information (PDB) in repository and current status for database ' || l_targets_row.name || ': ' || l_is_pdb || ' vs. ' || l_targets_row.is_pluggable);
        END IF;
        
        IF l_is_pdb = 'PDB' THEN
            l_sqltext := q'[SELECT dbid FROM v$pdbs@]' || l_targets_row.db_link_name || q'[ WHERE name = ']' || p_name || q'[']' ;
        ELSE
            l_sqltext := q'[SELECT dbid FROM v$database@]' || l_targets_row.db_link_name;
        END IF;
        EXECUTE IMMEDIATE l_sqltext INTO l_dbid; 
        
        IF l_dbid != l_targets_row.dbid THEN
            error_message('Found inconsistency between stored meta-information (database id) in repository and current status for database ' || l_targets_row.name || ': ' || l_dbid || ' vs. ' || l_targets_row.dbid);
        END IF;
        
        l_sqltext := q'[SELECT decode(VALUE,'FALSE','NO','YES') FROM v$parameter@]' || l_targets_row.db_link_name || q'[ WHERE name = 'cluster_database']';
        EXECUTE IMMEDIATE l_sqltext INTO l_is_rac;
        
        IF l_is_rac != l_targets_row.is_rac THEN
            error_message('Found inconsistency between stored meta-information (RAC) in repository and current status for database ' || l_targets_row.name || ': ' || l_is_rac || ' vs. ' || l_targets_row.is_rac);
        END IF;        
    
        l_sqltext := q'[SELECT instance_number FROM v$instance@]' || l_targets_row.db_link_name;
        EXECUTE IMMEDIATE l_sqltext INTO l_instance_n;
        
        IF l_instance_n != l_targets_row.instance_number THEN
            error_message('Found inconsistency between stored meta-information (instance number) in repository and current status for database ' || l_targets_row.name || ': ' || l_instance_n || ' vs. ' || l_targets_row.instance_number);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            error_message('Error during checking stored meta-information of target database ' || p_name || ': ' || SQLCODE);
    END check_target;


    PROCEDURE delete_target (p_name VARCHAR2, p_instance_number NUMBER, p_dbid NUMBER) IS
        l_db_link_name  targets.db_link_name%TYPE;
        l_sqltext       VARCHAR2(4000);
    BEGIN
        SELECT db_link_name INTO l_db_link_name FROM targets WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;
        
        change_target_status(p_name,p_instance_number,p_dbid,'DISABLED');
        
        l_sqltext := 'DROP DATABASE LINK ' || l_db_link_name;
        EXECUTE IMMEDIATE l_sqltext;
        
        DELETE FROM targets WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            error_message('Error during deleting database ' || p_name || ' from repository: ' || SQLCODE);
    END delete_target;
    
    
    PROCEDURE change_target_status (p_name VARCHAR2, p_instance_number NUMBER, p_dbid NUMBER, p_status VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        CASE upper(p_status)
            WHEN 'DISABLED' THEN
                UPDATE targets SET status = upper(p_status) WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;
                ashs.deschedule_ash_sampling(p_name,p_instance_number,p_dbid);
                COMMIT;
            WHEN 'ENABLED' THEN
                UPDATE targets SET status = upper(p_status) WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;
                ashs.schedule_ash_sampling(p_name,p_instance_number,p_dbid);
                COMMIT;
            WHEN 'DESCHEDULED' THEN
                UPDATE targets SET status = upper(p_status) WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;
                ashs.deschedule_ash_sampling(p_name,p_instance_number,p_dbid);
                COMMIT;
            ELSE
                error_message('Error during changing the state of target database ' || p_name || ' - invalid option ' || p_status);
        END CASE;
    EXCEPTION
        WHEN OTHERS THEN
            error_message('Error during changing the state of target database ' || p_name || ' in repository: ' || SQLCODE);
    END change_target_status;
        

    PROCEDURE error_message(p_message VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        l_callstack messages.stack%TYPE DEFAULT dbms_utility.format_call_stack;
    BEGIN
        INSERT INTO messages(time,stack,message) VALUES (SYSDATE,l_callstack,p_message);
        COMMIT;
    END error_message;
    

    PROCEDURE repo_maintenance IS
        l_day            VARCHAR2(2);
        l_retention      configuration.value%TYPE;
        l_retention_date DATE;
        l_sqltext        VARCHAR2(4000);
    BEGIN
        FOR l_all_targets IN (SELECT name, dbid, instance_number FROM targets WHERE status = 'ENABLED')
        LOOP
            change_target_status(l_all_targets.name,l_all_targets.instance_number,l_all_targets.dbid,'DESCHEDULED');
        END LOOP;
        
        SELECT to_number(to_char(SYSDATE, 'DD')) INTO l_day FROM dual;
        l_sqltext := 'CREATE OR REPLACE VIEW yaashsr.active_session_history_daily as select * from yaashsr.ash_samples_day_' || l_day;
        EXECUTE IMMEDIATE l_sqltext;
        
        FOR l_all_targets IN (SELECT name, dbid, instance_number FROM targets WHERE status = 'DESCHEDULED')
        LOOP
            change_target_status(l_all_targets.name,l_all_targets.instance_number,l_all_targets.dbid,'ENABLED');
            check_target(l_all_targets.name,l_all_targets.instance_number,l_all_targets.dbid);
        END LOOP;
        
        SELECT value INTO l_retention FROM configuration WHERE name = 'RETENTION_DAYS';
        l_retention_date := SYSDATE - l_retention;
        
        FOR l_counter IN 1..31 LOOP
            l_sqltext := 'DELETE FROM yaashsr.ash_samples_day_' || l_counter || ' WHERE sample_time < :val1';
            EXECUTE IMMEDIATE l_sqltext USING l_retention_date;
        END LOOP;
               
        DELETE FROM sql WHERE sql_id NOT IN (SELECT sql_id FROM active_session_history_all);
        
        DELETE FROM messages WHERE time < l_retention_date;
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            error_message('Error during daily repository database maintenance: ' || SQLCODE);
    END repo_maintenance;    
END repo;
/