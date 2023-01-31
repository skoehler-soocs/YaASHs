CREATE OR REPLACE PACKAGE BODY yaashsr.ut_yaashs AS
    /*
    Author: Stefan Koehler ( http://www.soocs.de )
    Description: PL/SQL package body for unit testing YaASHs with utPLSQL
    Use at your own risk!
    */


    gc_ashs_job_name   CONSTANT user_scheduler_jobs.job_name%TYPE := 'YAASHS_SAMPLE_ASH_T1911DB_1_2181059197';
    gc_db_link_name    CONSTANT targets.db_link_name%TYPE := 'DBL_T1911DB_1_2181059197';
    gc_dbid            CONSTANT targets.dbid%TYPE := 2181059197;
    gc_host_name       CONSTANT targets.host_name%TYPE := 'OEL85';
    gc_instance_number CONSTANT targets.instance_number%TYPE := 1;
    gc_instance_name   CONSTANT targets.instance_name%TYPE := NULL;
    gc_listener_port   CONSTANT targets.listener_port%TYPE := 1521;
    gc_name            CONSTANT targets.name%TYPE := 'T1911DB';
    gc_password        CONSTANT VARCHAR2(400) := 'yaashst';
    gc_sampling_type   CONSTANT targets.sampling_type%TYPE := 'STANDARD';
    gc_service_name    CONSTANT targets.service_name%TYPE := 'T1911DB';
    gc_username        CONSTANT VARCHAR2(400) := 'yaashst';
    gc_version         CONSTANT v$instance.version%TYPE := '19.0';


    PROCEDURE ut_check_repo_maintenance IS
        l_count NUMBER;
    BEGIN
        SELECT count(*) INTO l_count FROM user_scheduler_jobs WHERE job_name = 'YAASHS_REPO_MAINTENANCE' AND enabled = 'TRUE'; 
        ut.expect(l_count,'Maintenance job YAASHS_REPO_MAINTENANCE is missing.').to_equal(1);
    END ut_check_repo_maintenance;
    
    
    PROCEDURE ut_alter_configuration_failure IS
        l_count NUMBER;
    BEGIN
        repo.alter_config('WRONGPARAM',100);
        SELECT count(*) INTO l_count FROM messages WHERE message like '%invalid parameter%WRONGPARAM%'; 
        ut.expect(l_count,'Invalid/wrong configuration parameter was not identified.').to_equal(1);
        
        repo.alter_config('SAMPLEDURA_SEC','xx');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%invalid value%xx%SAMPLEDURA_SEC%';
        ut.expect(l_count,'Invalid/wrong value for parameter SAMPLEDURA_SEC was not identified.').to_equal(1);
        
        repo.alter_config('SAMPLEDURA_SEC','3600');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%SAMPLEFREQ_SEC x SAMPLEDURA_SEC needs to be less than 3600 seconds but also a full minute value%';
        ut.expect(l_count,'Invalid/wrong value for parameter SAMPLEDURA_SEC was not identified.').to_equal(1);
    
        repo.alter_config('SAMPLEDURA_SEC','400');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%SAMPLEFREQ_SEC x SAMPLEDURA_SEC needs to be less than 3600 seconds but also a full minute value%';
        ut.expect(l_count,'Invalid/wrong value for parameter SAMPLEDURA_SEC was not identified.').to_equal(2);
        
        repo.alter_config('SAMPLEFREQ_SEC','aa');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%invalid value%aa%SAMPLEFREQ_SEC%';
        ut.expect(l_count,'Invalid/wrong value for parameter SAMPLEFREQ_SEC was not identified.').to_equal(1);
        
        repo.alter_config('RETENTION_DAYS','DAILY');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%invalid value%DAILY%RETENTION_DAYS%';
        ut.expect(l_count,'Invalid/wrong value for parameter RETENTION_DAYS was not identified.').to_equal(1);

        repo.alter_config('RETENTION_DAYS','40');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%invalid value%40%RETENTION_DAYS%';
        ut.expect(l_count,'Invalid/wrong value for parameter RETENTION_DAYS was not identified.').to_equal(1);
        
        repo.alter_config('SAMPLE_IDLE','donot');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%invalid value%donot%SAMPLE_IDLE%';
        ut.expect(l_count,'Invalid/wrong value for parameter SAMPLE_IDLE was not identified.').to_equal(1);
        
        DELETE FROM messages;
        COMMIT;
    END ut_alter_configuration_failure;


    PROCEDURE ut_alter_configuration_success IS
        l_value configuration.value%TYPE;
    BEGIN
        -- SAMPLEFREQ_SEC needs to be altered and tested first (due to deployed default values and restriction of SAMPLEFREQ_SEC x SAMPLEDURA_SEC < 3600 plus the need of to be full minute value)
        repo.alter_config('SAMPLEFREQ_SEC','2');
        SELECT value INTO l_value FROM configuration WHERE name = 'SAMPLEFREQ_SEC';
        ut.expect(l_value,'Value SAMPLEFREQ_SEC was not changed successfully.').to_equal('2');

        repo.alter_config('SAMPLEDURA_SEC','30');
        SELECT value INTO l_value FROM configuration WHERE name = 'SAMPLEDURA_SEC';
        ut.expect(l_value,'Value SAMPLEDURA_SEC was not changed successfully.').to_equal('30');  
                
        repo.alter_config('RETENTION_DAYS','3');
        SELECT value INTO l_value FROM configuration WHERE name = 'RETENTION_DAYS';
        ut.expect(l_value,'Value RETENTION_DAYS was not changed successfully.').to_equal('3');
  
        repo.alter_config('SAMPLE_IDLE','YES');
        SELECT value INTO l_value FROM configuration WHERE name = 'SAMPLE_IDLE';
        ut.expect(l_value,'Value SAMPLE_IDLE was not changed successfully.').to_equal('YES');
        
        DELETE FROM messages;
        COMMIT;
    END ut_alter_configuration_success;
    
 
    PROCEDURE ut_add_target_single_instance IS
        l_count NUMBER;
    BEGIN
        repo.add_target(gc_name,gc_host_name,gc_listener_port,gc_service_name,gc_instance_number,gc_instance_name,gc_username,gc_password);
        SELECT count(*) INTO l_count FROM targets WHERE name = gc_name AND instance_number = gc_instance_number AND dbid = gc_dbid;
        ut.expect(l_count,'Missing entry in table targets for new target database.').to_equal(1);
        
        SELECT count(*) INTO l_count FROM user_db_links WHERE db_link = gc_db_link_name;
        ut.expect(l_count,'Missing database link for new target database.').to_equal(1);
        
        SELECT count(*) INTO l_count FROM user_scheduler_jobs WHERE job_name = gc_ashs_job_name AND enabled = 'TRUE'; 
        ut.expect(l_count,'ASH sampling job for target database is not defined.').to_equal(1);
        
        SELECT count(*) INTO l_count FROM messages;
        ut.expect(l_count,'Errors in table messages while adding new target database.').to_equal(0);
        
        DELETE FROM messages;
        COMMIT;
    END ut_add_target_single_instance;
    
 
    PROCEDURE ut_duplicate_target_single_instance IS
        l_count NUMBER;
    BEGIN
        repo.add_target(gc_name,gc_host_name,gc_listener_port,gc_service_name,gc_instance_number,gc_instance_name,gc_username,gc_password);
        SELECT count(*) INTO l_count FROM messages WHERE message = 'Error during adding database ' || gc_name || ' to repository: -1';
        ut.expect(l_count,'Failure was not detected during adding an already existing target database.').to_equal(1);
        
        DELETE FROM messages;
        COMMIT;        
    END ut_duplicate_target_single_instance;


    PROCEDURE ut_disable_target IS
        l_count NUMBER;
    BEGIN
        repo.change_target_status(gc_name,gc_instance_number,gc_dbid,'DISABLED');
        SELECT count(*) INTO l_count FROM targets WHERE name = gc_name AND instance_number = gc_instance_number AND dbid = gc_dbid AND status = 'DISABLED';
        ut.expect(l_count,'Target database has a different state than DISABLED in table targets.').to_equal(1);
        
        SELECT count(*) INTO l_count FROM user_scheduler_jobs WHERE job_name = gc_ashs_job_name AND enabled = 'TRUE'; 
        ut.expect(l_count,'ASH sampling job for target database is still defined.').to_equal(0);
        
        DELETE FROM messages;
        COMMIT;
    END ut_disable_target;


    PROCEDURE ut_enable_target IS
        l_count NUMBER;
    BEGIN
        repo.change_target_status(gc_name,gc_instance_number,gc_dbid,'ENABLED');
        SELECT count(*) INTO l_count FROM targets WHERE name = gc_name AND instance_number = gc_instance_number AND dbid = gc_dbid AND status = 'ENABLED';
        ut.expect(l_count,'Target database has a different state than ENABLED in table targets.').to_equal(1);
        
        SELECT count(*) INTO l_count FROM user_scheduler_jobs WHERE job_name = gc_ashs_job_name AND enabled = 'TRUE'; 
        ut.expect(l_count,'ASH sampling job for target database is not defined.').to_equal(1);
        
        DELETE FROM messages;
        COMMIT;
    END ut_enable_target;
    

    PROCEDURE ut_get_db_version IS
        l_version   v$instance.version%TYPE;
    BEGIN
        l_version := ashs.get_db_version(gc_name,gc_instance_number,gc_dbid);
        ut.expect(l_version,'Target database is not version 19.0.').to_equal(gc_version);
        
        DELETE FROM messages;
        COMMIT;
    END ut_get_db_version;
    

    PROCEDURE ut_check_target IS
        l_count NUMBER;
    BEGIN
        UPDATE targets SET is_pluggable='CDB' WHERE name = gc_name AND instance_number = gc_instance_number AND dbid = gc_dbid;
        UPDATE targets SET is_rac='YES' WHERE name = gc_name AND instance_number = gc_instance_number AND dbid = gc_dbid;
        UPDATE targets SET dbid=dbid+1 WHERE name = gc_name AND instance_number = gc_instance_number AND dbid = gc_dbid;
        repo.check_target(gc_name,gc_instance_number,gc_dbid+1);
        
        SELECT count(*) INTO l_count FROM messages WHERE message like 'Found inconsistency between stored meta-information (PDB)%' || gc_name || '%';
        ut.expect(l_count,'Inconsistency check for Non-CDB/CDB/PDB type is not working.').to_equal(1);
        
        SELECT count(*) INTO l_count FROM messages WHERE message like 'Found inconsistency between stored meta-information (database id)%' || gc_name || '%';
        ut.expect(l_count,'Inconsistency check for database id is not working.').to_equal(1);
        
        SELECT count(*) INTO l_count FROM messages WHERE message like 'Found inconsistency between stored meta-information (RAC)%' || gc_name || '%';
        ut.expect(l_count,'Inconsistency check for RAC type is not working.').to_equal(1);
        
        ROLLBACK;
        DELETE FROM messages;
        COMMIT;
    END ut_check_target;


    PROCEDURE ut_ash_sql_samples_success IS
        l_count NUMBER;
    BEGIN
        dbms_session.sleep(80);
        SELECT count(*) INTO l_count FROM active_session_history_daily WHERE name = gc_name AND inst_id = gc_instance_number AND dbid = gc_dbid AND sample_time BETWEEN SYSDATE-80/24/60/60 AND SYSDATE;
        ut.expect(l_count,'No ASH samples were collected.').to_be_greater_or_equal(1);

        SELECT count(*) INTO l_count FROM sql;
        ut.expect(l_count,'No SQL ID samples were collected.').to_be_greater_or_equal(1);
        
        DELETE FROM messages;
        COMMIT;
    END ut_ash_sql_samples_success;


    PROCEDURE ut_ash_sql_samples_failure IS
        l_col_mapping_row col_mapping%ROWTYPE;
        l_count           NUMBER;
    BEGIN
        DELETE FROM col_mapping WHERE version = gc_version AND type = gc_sampling_type RETURNING version,type,col_sess,col_ashs INTO l_col_mapping_row;
        COMMIT;
        
        repo.change_target_status(gc_name,gc_instance_number,gc_dbid,'DISABLED');
        repo.change_target_status(gc_name,gc_instance_number,gc_dbid,'ENABLED');
    
        dbms_session.sleep(5);
        
        SELECT count(*) INTO l_count FROM messages WHERE message like '%column mapping in table col_mapping%'; 
        ut.expect(l_count,'Missing column mapping in table col_mapping was not identified.').to_equal(1);
        
        INSERT INTO col_mapping(version,type,col_sess,col_ashs) VALUES (l_col_mapping_row.version,l_col_mapping_row.type,l_col_mapping_row.col_sess,l_col_mapping_row.col_ashs);
        DELETE FROM messages;
        COMMIT;
    END ut_ash_sql_samples_failure;


    PROCEDURE ut_change_sampling_type_failure IS
        l_col_mapping_row col_mapping%ROWTYPE;
        l_count           NUMBER;
    BEGIN
        repo.change_target_type(gc_name,gc_dbid,'NOTVALIDVALUE');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%invalid option NOTVALIDVALUE%'; 
        ut.expect(l_count,'Invalid option for parameter p_sampling_type was not identified.').to_equal(1);
        
        repo.change_target_type(gc_name,gc_dbid,'ADVANCED');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%view SYS.YAASHS_V$SESSION is not available in target database%'; 
        ut.expect(l_count,'Missing view SYS.YAASHS_V$SESSION in target database was not identified.').to_equal(1); 
        
        -- Unit tester needs to manually execute the following procedure and its instructions within 100 seconds - otherwise all following unit tests will not be valid
        -- set serveroutput on;
        -- exec yaashsr.repo.generate_advanced_view_target(p_name => 'T1911DB', p_dbid => 2181059197);
        dbms_session.sleep(100);
        
        DELETE FROM col_mapping WHERE version = gc_version AND type = 'ADVANCED' RETURNING version,type,col_sess,col_ashs INTO l_col_mapping_row;
        COMMIT;
         
        repo.change_target_type(gc_name,gc_dbid,'ADVANCED');
        SELECT count(*) INTO l_count FROM messages WHERE message like '%no column mapping available for Oracle version%'; 
        ut.expect(l_count,'Missing advanced view mapping in table advanced_view_def was not identified.').to_equal(1);
        
        INSERT INTO col_mapping(version,type,col_sess,col_ashs) VALUES (l_col_mapping_row.version,l_col_mapping_row.type,l_col_mapping_row.col_sess,l_col_mapping_row.col_ashs);
        DELETE FROM messages;
        COMMIT;
        
        SELECT count(*) INTO l_count FROM targets WHERE name = gc_name AND dbid = gc_dbid AND sampling_type = 'ADVANCED';
        ut.expect(l_count,'Target database has wrong sampling type/mode.').to_equal(0);
    END ut_change_sampling_type_failure;


    PROCEDURE ut_change_sampling_type_success IS
        l_count NUMBER;
    BEGIN
        repo.change_target_type(gc_name,gc_dbid,'ADVANCED');
        SELECT count(*) INTO l_count FROM targets WHERE name = gc_name AND dbid = gc_dbid AND sampling_type = 'ADVANCED';
        ut.expect(l_count,'Target database has wrong sampling type/mode.').to_be_greater_or_equal(1);
        
        DELETE FROM messages;
        COMMIT;
    END ut_change_sampling_type_success;


    PROCEDURE ut_advanced_ash_samples_success IS
        l_count NUMBER;
    BEGIN
        dbms_session.sleep(20);
        SELECT count(*) INTO l_count FROM active_session_history_daily WHERE name = gc_name AND inst_id = gc_instance_number AND dbid = gc_dbid AND sample_time BETWEEN SYSDATE-20/24/60/60 AND SYSDATE
                                                                       AND sql_plan_hash_value IS NOT NULL AND time_model IS NOT NULL AND in_connection_mgmt IS NOT NULL AND in_parse IS NOT NULL AND in_hard_parse IS NOT NULL 
                                                                       AND in_sql_execution IS NOT NULL AND in_plsql_execution IS NOT NULL AND in_plsql_rpc IS NOT NULL AND in_plsql_compilation IS NOT NULL 
                                                                       AND in_java_execution IS NOT NULL AND in_bind IS NOT NULL AND in_cursor_close IS NOT NULL AND in_sequence_load IS NOT NULL AND in_inmemory_query IS NOT NULL 
                                                                       AND in_inmemory_populate IS NOT NULL AND in_inmemory_prepopulate IS NOT NULL AND in_inmemory_repopulate IS NOT NULL AND in_inmemory_trepopulate IS NOT NULL 
                                                                       AND in_tablespace_encryption IS NOT NULL;
        ut.expect(l_count,'No advanced ASH samples were collected.').to_be_greater_or_equal(1);
        
        DELETE FROM messages;
        COMMIT;
    END ut_advanced_ash_samples_success;


    PROCEDURE ut_export_target IS
        l_count NUMBER;
    BEGIN
        repo.transport_target_export(gc_name,gc_dbid);
      
        SELECT count(*) INTO l_count FROM messages;
        ut.expect(l_count,'Errors in table messages while exporting a target database.').to_equal(0);  
        
        DELETE FROM messages;
        COMMIT;
    END ut_export_target;


    PROCEDURE ut_delete_target_single_instance IS
        l_count NUMBER;
    BEGIN
        repo.delete_target(gc_name,gc_instance_number,gc_dbid);
        SELECT count(*) INTO l_count FROM targets WHERE name = gc_name AND instance_number = gc_instance_number AND dbid = gc_dbid;
        ut.expect(l_count,'Entry in table targets for target database still exists.').to_equal(0);
        
        SELECT count(*) INTO l_count FROM user_db_links WHERE db_link = gc_db_link_name;
        ut.expect(l_count,'Database link for target database still exists.').to_equal(0);
        
        SELECT count(*) INTO l_count FROM user_scheduler_jobs WHERE job_name = gc_ashs_job_name AND enabled = 'TRUE'; 
        ut.expect(l_count,'ASH sampling job for target database is still defined.').to_equal(0);  
        
        SELECT count(*) INTO l_count FROM messages;
        ut.expect(l_count,'Errors in table messages while deleting a target database.').to_equal(0);
        
        DELETE FROM messages;
        COMMIT;
    END ut_delete_target_single_instance;


    PROCEDURE ut_repo_maintenance IS
        l_count NUMBER;
    BEGIN
        UPDATE active_session_history_daily SET sample_time=SYSDATE-10 WHERE sql_id <> '229c5a3jfgp55' OR sql_id IS NULL;
        COMMIT;
        
        repo.repo_maintenance();
        
        SELECT count(*) INTO l_count FROM active_session_history_daily WHERE sql_id <> '229c5a3jfgp55';
        ut.expect(l_count,'ASH samples were not cleaned up properly.').to_equal(0);  
        
        SELECT count(*) INTO l_count FROM sql;
        ut.expect(l_count,'Sampled SQL IDs (and SQL text) were not cleaned up properly.').to_equal(1);  

        DELETE FROM messages;
        COMMIT;        
    END ut_repo_maintenance;

    
    PROCEDURE ut_import_target IS
        l_count           NUMBER;
        l_count_samples_b NUMBER;
        l_count_samples_a NUMBER;
    BEGIN
        SELECT count(*) INTO l_count_samples_b FROM active_session_history_daily WHERE name = gc_name AND inst_id = gc_instance_number AND dbid = gc_dbid;
        
        repo.transport_target_import(gc_name,gc_dbid);
      
        SELECT count(*) INTO l_count FROM messages;
        ut.expect(l_count,'Errors in table messages while importing a target database.').to_equal(0);  
        
        SELECT count(*) INTO l_count FROM targets WHERE name = gc_name AND instance_number = gc_instance_number AND dbid = gc_dbid AND status = 'IMPORTED';
        ut.expect(l_count,'Entry in table targets for imported target database does not exists.').to_equal(1);  

        SELECT count(*) INTO l_count FROM user_db_links WHERE db_link = gc_db_link_name;
        ut.expect(l_count,'Database link for imported target database does not exists.').to_equal(1);
        
        SELECT count(*) INTO l_count_samples_a FROM active_session_history_daily WHERE name = gc_name AND inst_id = gc_instance_number AND dbid = gc_dbid;
        ut.expect(l_count_samples_a,'Number of ASH samples for imported target database has not increased.').to_be_greater_than(l_count_samples_b);
        
        DELETE FROM messages;
        COMMIT;
    END ut_import_target;
END ut_yaashs;
/