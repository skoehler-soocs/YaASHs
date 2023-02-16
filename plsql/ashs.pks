CREATE OR REPLACE PACKAGE yaashsr.ashs AS
    /*
    Author: Stefan Koehler ( http://www.soocs.de )
    Description: PL/SQL package specification for ashs package
                 The ashs PL/SQL package contains the functionality for sampling, (de-)scheduling and storing the ASH samples from a target database
                 Description of commonly used parameters in functions and procedures:
                    * p_name = Database name
                    * p_instance_number = Database instance number
                    * p_dbid = Database ID
    Use at your own risk!
    */


    -- Drops the ASH sampling dbms_scheduler job for a particular target database, if the target database status is DISABLED or DESCHEDULED 
    PROCEDURE deschedule_ash_sampling (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER);
    
    -- Returns the database version (as 4-digit number, e.g. 19.0 or 12.2) of the target database
    FUNCTION  get_db_version (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER) RETURN VARCHAR2;
    
    -- Creates the ASH sampling dbms_scheduler job for a particular target database, if the target database status is ENABLED
    PROCEDURE schedule_ash_sampling (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER);
    
    -- Samples data from v$session on the target database, copies it via database link and stores it into repository database
    PROCEDURE sample_ash (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER);
    
    -- Samples data from v$sqlarea on the target database for specific SQL IDs in a given time period (start and end time of procedure sample_ash), copies it via database link and stores it into repository database
    PROCEDURE sample_sqltext (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER, p_sample_start DATE, p_sample_end DATE);
END ashs;
/