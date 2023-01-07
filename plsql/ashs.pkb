CREATE OR REPLACE PACKAGE BODY yaashsr.ashs AS
    /*
    Author: Stefan Koehler ( http://www.soocs.de )
    Description: PL/SQL package body for ashs package
                 The ashs PL/SQL package contains the functionality for sampling, (de-)scheduling and storing the ASH samples from a target database
    Use at your own risk!
    */


    PROCEDURE deschedule_ash_sampling (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER) IS
        l_status    targets.status%TYPE;
    BEGIN
        SELECT status INTO l_status FROM targets WHERE name = p_name and instance_number = p_instance_number AND dbid = p_dbid;
        -- The status DISABLED is set by the end user and the status DESCHEDULED is set during repository maintenance activity
        IF l_status = 'DISABLED' OR l_status = 'DESCHEDULED' THEN
            dbms_scheduler.drop_job(job_name => 'yaashs_sample_ash_' || p_name || '_' || p_instance_number || '_' ||  p_dbid, force => TRUE);
        END IF;                 
     EXCEPTION
        WHEN OTHERS THEN
            repo.error_message('Error during dropping the ASH sampling job for database ' || p_name || ': ' || SQLCODE);
    END deschedule_ash_sampling;


    FUNCTION get_db_version (p_name VARCHAR2, p_instance_number NUMBER, p_dbid NUMBER) RETURN VARCHAR2 IS
        l_db_link_name targets.db_link_name%TYPE;
        l_sqltext      VARCHAR2(4000);
        l_version      v$instance.version%TYPE;
    BEGIN
        SELECT db_link_name INTO l_db_link_name FROM targets WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;
        l_sqltext := q'[SELECT substr(version,0,4) FROM v$instance@]' || l_db_link_name;
        EXECUTE IMMEDIATE l_sqltext INTO l_version; 
        RETURN l_version;
    EXCEPTION
        WHEN OTHERS THEN
            repo.error_message('Error during determining Oracle version of target database ' || p_name || ': ' || SQLCODE);
    END get_db_version;


    PROCEDURE schedule_ash_sampling (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER) IS
        l_sampledura_s   configuration.value%TYPE;
        l_samplefreq_s   configuration.value%TYPE;
        l_job_duration_m NUMBER;
        l_sqltext        VARCHAR2(4000);
        l_status         targets.status%TYPE;
    BEGIN
        SELECT value INTO l_samplefreq_s FROM configuration WHERE name = 'SAMPLEFREQ_SEC';
        SELECT value INTO l_sampledura_s FROM configuration WHERE name = 'SAMPLEDURA_SEC';
        l_job_duration_m := (l_samplefreq_s * l_sampledura_s) / 60;

        SELECT status INTO l_status FROM targets WHERE name = p_name and instance_number = p_instance_number AND dbid = p_dbid;
        IF l_status = 'ENABLED' THEN
            l_sqltext := 'BEGIN ashs.sample_ash(''' || p_name || ''',' || p_instance_number || ',' || p_dbid || '); END;';
            dbms_scheduler.create_job(job_name => 'yaashs_sample_ash_' || p_name || '_' || p_instance_number || '_' ||  p_dbid, job_type => 'PLSQL_BLOCK', job_action => l_sqltext, start_date => SYSDATE, repeat_interval => 'FREQ=MINUTELY; INTERVAL=' || l_job_duration_m, enabled=> TRUE);
        END IF;                 
     EXCEPTION
        WHEN OTHERS THEN
            repo.error_message('Error during creating the ASH sampling job for database ' || p_name || ': ' || SQLCODE);
    END schedule_ash_sampling;

    
    PROCEDURE sample_ash (p_name VARCHAR2, p_instance_number NUMBER, p_dbid NUMBER) IS
        l_col_ashs      col_mapping.col_ashs%TYPE;
        l_col_sess      col_mapping.col_sess%TYPE;    
        l_date_start    DATE;
        l_date_end      DATE;
        l_dbid          targets.dbid%TYPE;
        l_db_link_name  targets.db_link_name%TYPE;
        l_sample_idle   configuration.value%TYPE;
        l_sampledura_s  configuration.value%TYPE;
        l_samplefreq_s  configuration.value%TYPE;
        l_sampleid      NUMBER;
        l_sqltext       VARCHAR2(4000);
        l_sqltext_where VARCHAR2(50) DEFAULT '1 = 1';
        l_username      user_db_links.username%TYPE;
        l_version       col_mapping.version%TYPE;          
    BEGIN
        l_date_start := SYSDATE;
        l_version := get_db_version(p_name,p_instance_number,p_dbid);
        SELECT value INTO l_sample_idle FROM configuration WHERE name = 'SAMPLE_IDLE';
        SELECT value INTO l_samplefreq_s FROM configuration WHERE name = 'SAMPLEFREQ_SEC';
        SELECT value INTO l_sampledura_s FROM configuration WHERE name = 'SAMPLEDURA_SEC';
        SELECT db_link_name, dbid INTO l_db_link_name, l_dbid FROM targets WHERE name = p_name and instance_number = p_instance_number AND dbid = p_dbid;
        SELECT col_ashs, col_sess INTO l_col_ashs, l_col_sess FROM col_mapping WHERE version = l_version;
        SELECT username INTO l_username FROM user_db_links WHERE db_link = l_db_link_name;
        
        IF l_sample_idle = 'NO' THEN
            l_sqltext_where := 'status = ''ACTIVE'' AND wait_class <> ''Idle''';
        END IF;
                  
        FOR counter in 1 .. l_sampledura_s
        LOOP
            SELECT sample_id.nextval INTO l_sampleid FROM dual;
                
            l_sqltext := 'INSERT INTO active_session_history_daily(name,dbid,inst_id,sample_id,sample_time,' || l_col_ashs || 
                         ') SELECT :val1, :val2, :val3, :val4, :val5, ' || l_col_sess || ' FROM v$session@' || l_db_link_name || ' WHERE ' || l_sqltext_where ||
                         ' AND username <> :val6';
            EXECUTE IMMEDIATE l_sqltext USING p_name, l_dbid, p_instance_number, l_sampleid, SYSDATE, l_username;
            COMMIT;
                
            dbms_session.sleep(l_samplefreq_s);
        END LOOP;
        l_date_end := SYSDATE;
            
        sample_sqltext(p_name,p_instance_number,p_dbid,l_date_start,l_date_end);
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
            repo.error_message('Error during ASH sampling for database ' || p_name || ' - target database version ' || l_version || ' has no (complete) column mapping in table col_mapping');
        WHEN OTHERS THEN
            repo.error_message('Error during ASH sampling for database ' || p_name || ': ' || SQLCODE);
    END sample_ash;


    PROCEDURE sample_sqltext (p_name VARCHAR2, p_instance_number NUMBER, p_dbid NUMBER, p_sample_start DATE, p_sample_end DATE) IS
        l_db_link_name  targets.db_link_name%TYPE;
        l_sqltext       VARCHAR2(4000);
    BEGIN
        SELECT db_link_name INTO l_db_link_name FROM targets WHERE name = p_name and instance_number = p_instance_number AND dbid = p_dbid;

        l_sqltext := 'MERGE INTO sql reposql USING ' ||
                     '(SELECT DISTINCT vsql.sql_id, vsql.sql_text FROM v$sql@' || l_db_link_name || ' vsql, active_session_history_daily ashd ' || 
                     'WHERE ashd.sql_id = vsql.sql_id AND ashd.sample_time BETWEEN :val1 AND :val2 and ashd.name = :val3 and ashd.inst_id = :val4 and ashd.dbid = :val5) ' ||
                     'rsql ON (rsql.sql_id = reposql.sql_id) ' ||
                     'WHEN NOT MATCHED THEN INSERT (reposql.sql_id, reposql.sql_text) VALUES (rsql.sql_id, rsql.sql_text)';
        EXECUTE IMMEDIATE l_sqltext USING p_sample_start, p_sample_end, p_name, p_instance_number, p_dbid;
        COMMIT;
     EXCEPTION
        WHEN OTHERS THEN
            repo.error_message('Error during sampling SQL IDs/text for database ' || p_name || ': ' || SQLCODE);        
    END sample_sqltext;
END ashs;
/