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
        SELECT status INTO l_status FROM targets WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;
        -- The status DISABLED is set by the end user and the status DESCHEDULED is set during repository maintenance activity
        IF l_status = 'DISABLED' OR l_status = 'DESCHEDULED' THEN
            dbms_scheduler.drop_job(job_name => 'yaashs_sample_ash_' || p_name || '_' || p_instance_number || '_' ||  p_dbid, force => TRUE);
        END IF;                 
     EXCEPTION
        WHEN OTHERS THEN
            repo.error_message(p_name,p_instance_number,p_dbid,'Error during dropping the ASH sampling job: ' || SQLCODE);
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
            repo.error_message(p_name,p_instance_number,p_dbid,'Error during determining Oracle version: ' || SQLCODE);
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

        SELECT status INTO l_status FROM targets WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;
        IF l_status = 'ENABLED' THEN
            l_sqltext := 'BEGIN ashs.sample_ash(''' || p_name || ''',' || p_instance_number || ',' || p_dbid || '); END;';
            dbms_scheduler.create_job(job_name => 'yaashs_sample_ash_' || p_name || '_' || p_instance_number || '_' ||  p_dbid, job_type => 'PLSQL_BLOCK', job_action => l_sqltext, start_date => SYSDATE, repeat_interval => 'FREQ=MINUTELY; INTERVAL=' || l_job_duration_m, enabled=> TRUE);
        END IF;                 
     EXCEPTION
        WHEN OTHERS THEN
            repo.error_message(p_name,p_instance_number,p_dbid,'Error during creating the ASH sampling job: ' || SQLCODE);
    END schedule_ash_sampling;

    
    PROCEDURE sample_ash (p_name VARCHAR2, p_instance_number NUMBER, p_dbid NUMBER) IS
        l_col_ashs_a         col_mapping.col_ashs%TYPE DEFAULT NULL;
        l_col_sess_a         col_mapping.col_sess%TYPE DEFAULT NULL;
        l_col_ashs_s         col_mapping.col_ashs%TYPE;
        l_col_sess_s         col_mapping.col_sess%TYPE;
        l_count_slow_sample  NUMBER DEFAULT 0;
        l_date_start         DATE;
        l_date_end           DATE;
        l_dbid               targets.dbid%TYPE;
        l_dyn_samplefreq_s   NUMBER;
        l_db_link_name       targets.db_link_name%TYPE;
        l_sample_idle        configuration.value%TYPE;
        l_sampledura_s       configuration.value%TYPE;
        l_samplefreq_s       configuration.value%TYPE;
        l_sampleid           NUMBER;
        l_sampling_type      targets.sampling_type%TYPE;
        l_sqltext            VARCHAR2(4000);
        l_sqltext_where      VARCHAR2(100) DEFAULT '1 = 1';
        l_time_after_sample  NUMBER; 
        l_time_before_sample NUMBER;
        l_time_durat_sample  NUMBER;
        l_username           user_db_links.username%TYPE;
        l_version            col_mapping.version%TYPE;
    BEGIN
        l_date_start := SYSDATE;
        l_version := get_db_version(p_name,p_instance_number,p_dbid);
        SELECT value INTO l_sample_idle FROM configuration WHERE name = 'SAMPLE_IDLE';
        SELECT value INTO l_samplefreq_s FROM configuration WHERE name = 'SAMPLEFREQ_SEC';
        SELECT value INTO l_sampledura_s FROM configuration WHERE name = 'SAMPLEDURA_SEC';
        SELECT db_link_name, dbid, sampling_type INTO l_db_link_name, l_dbid, l_sampling_type FROM targets WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;
        SELECT username INTO l_username FROM user_db_links WHERE db_link = l_db_link_name;
        
        IF l_sample_idle = 'NO' THEN
            -- Additional predicate "OR state <> 'WAITING'" is needed in older Oracle releases for cases like hard parsing (and running on CPU) as wait_class is still Idle in such cases
            l_sqltext_where := 'status = ''ACTIVE'' AND (wait_class <> ''Idle'' OR state <> ''WAITING'')';
        END IF;
        
        SELECT col_ashs, col_sess INTO l_col_ashs_s, l_col_sess_s FROM col_mapping WHERE version = l_version AND type = 'STANDARD';
        
        IF l_sampling_type = 'ADVANCED' THEN
            SELECT col_ashs, col_sess INTO l_col_ashs_a, l_col_sess_a FROM col_mapping WHERE version = l_version AND type = 'ADVANCED';
        END IF;
    
        l_sqltext := 'INSERT INTO active_session_history_daily(name,dbid,inst_id,sample_id,sample_time,' || l_col_ashs_s || l_col_ashs_a ||
                     ') SELECT :val1, :val2, :val3, :val4, :val5, ' || l_col_sess_s || l_col_sess_a || ' FROM v$session@' || l_db_link_name || 
                     ' WHERE ' || l_sqltext_where || ' AND username <> :val6';
                  
        FOR counter in 1 .. l_sampledura_s
        LOOP
            l_time_before_sample := dbms_utility.get_time();
            
            SELECT sample_id.nextval INTO l_sampleid FROM dual;
            EXECUTE IMMEDIATE l_sqltext USING p_name, l_dbid, p_instance_number, l_sampleid, SYSDATE, l_username;
            COMMIT;
            
            l_time_after_sample := dbms_utility.get_time();
            l_time_durat_sample := (l_time_after_sample - l_time_before_sample) / 100; 
            
            IF l_time_durat_sample >= l_samplefreq_s THEN
                l_count_slow_sample := l_count_slow_sample + 1;
                l_dyn_samplefreq_s := l_samplefreq_s;
            ELSE
                l_dyn_samplefreq_s := l_samplefreq_s - l_time_durat_sample;
            END IF;
            
            -- Sleeping frequency is dynamically calculated for each ASH sample to keep the scheduling time window of SAMPLEFREQ_SEC x SAMPLEDURA_SEC (USER_SCHEDULER_JOB_RUN_DETAILS.RUN_DURATION) as remote query itself takes several milliseconds depending on data volume
            dbms_session.sleep(l_dyn_samplefreq_s);
        END LOOP;
        l_date_end := SYSDATE;
            
        sample_sqltext(p_name,p_instance_number,p_dbid,l_date_start,l_date_end);
        
        IF l_count_slow_sample > 0 THEN
            repo.error_message(p_name,p_instance_number,p_dbid,l_count_slow_sample || ' ASH samples took longer than ' || l_samplefreq_s || ' second(s) during ASH sampling');
        END IF;
     EXCEPTION
        WHEN NO_DATA_FOUND THEN
            repo.error_message(p_name,p_instance_number,p_dbid,'Error during ASH sampling - target database version ' || l_version || ' has no (complete) column mapping in table col_mapping');
        WHEN OTHERS THEN
            repo.error_message(p_name,p_instance_number,p_dbid,'Error during ASH sampling for database: ' || SQLCODE);
    END sample_ash;


    PROCEDURE sample_sqltext (p_name VARCHAR2, p_instance_number NUMBER, p_dbid NUMBER, p_sample_start DATE, p_sample_end DATE) IS
        l_db_link_name  targets.db_link_name%TYPE;
        l_sqltext       VARCHAR2(4000);
    BEGIN
        SELECT db_link_name INTO l_db_link_name FROM targets WHERE name = p_name AND instance_number = p_instance_number AND dbid = p_dbid;

        -- SQL hint is necessary to guarantee stable performance as some fixed objects use cardinality defaults (e.g. check MOS ID #1637294.1) which can result in an inadequate execution plan
        l_sqltext := 'MERGE INTO sql reposql USING ' ||
                     '(SELECT /*+ LEADING("ASHD") USE_HASH("VSQL") */ DISTINCT vsql.sql_id, vsql.sql_text FROM v$sqlarea@' || l_db_link_name || ' vsql, active_session_history_daily ashd ' || 
                     'WHERE ashd.sql_id = vsql.sql_id AND ashd.sample_time BETWEEN :val1 AND :val2 AND ashd.name = :val3 AND ashd.inst_id = :val4 AND ashd.dbid = :val5) ' ||
                     'rsql ON (rsql.sql_id = reposql.sql_id) ' ||
                     'WHEN NOT MATCHED THEN INSERT (reposql.sql_id, reposql.sql_text) VALUES (rsql.sql_id, rsql.sql_text)';
        EXECUTE IMMEDIATE l_sqltext USING p_sample_start, p_sample_end, p_name, p_instance_number, p_dbid;
        COMMIT;
     EXCEPTION
        WHEN OTHERS THEN
            repo.error_message(p_name,p_instance_number,p_dbid,'Error during sampling SQL IDs/text: ' || SQLCODE);        
    END sample_sqltext;
END ashs;
/