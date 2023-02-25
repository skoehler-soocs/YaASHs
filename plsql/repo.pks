CREATE OR REPLACE PACKAGE yaashsr.repo AS
    /*
    Author: Stefan Koehler ( http://www.soocs.de )
    Description: PL/SQL package specification for repo package
                 The repo PL/SQL package contains the functionality for managing the target databases, altering the configuration and logging messages/errors in the repository database
                 Description of commonly used parameters in functions and procedures:
                    * p_name = Database name
                    * p_instance_number = Database instance number
                    * p_dbid = Database ID
    Use at your own risk!
    */


    -- Adds a new target database to the repository database and enables/creates collecting ASH/SQL samples for this database / instance
    PROCEDURE add_target (p_name VARCHAR2, p_host_name VARCHAR2, p_listener_port NUMBER DEFAULT 1521, p_service_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_instance_name VARCHAR2 DEFAULT NULL, p_username VARCHAR2, p_password VARCHAR2);

    -- Alters the configuration in the repository database and validates its parameters and values
    PROCEDURE alter_config (p_name VARCHAR2, p_value VARCHAR2);
    
    -- Checks the stored meta-information for a target database in the repository database with the currently configuration/attributes (e.g. multitenant, RAC, etc.) of this target database
    PROCEDURE check_target (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER);
    
    -- Deletes target database from the repository database and disables/drops collecting ASH/SQL samples for this database / instance
    PROCEDURE delete_target (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER);
    
    -- Changes the status of a particular target database in the repository database and enables/disables or delays the ASH samples collection (p_status can be DISABLED, ENABLED or DESCHEDULED)
    PROCEDURE change_target_status (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER, p_status VARCHAR2);

    -- Changes the ASH sampling type of a particular target database in the repository database (p_sampling_type can be 'STANDARD' or 'ADVANCED')
    PROCEDURE change_target_type (p_name VARCHAR2, p_dbid NUMBER, p_sampling_type VARCHAR2); 
    
    -- General (error) logging procedure that stores the call stack and error message and is used by all other functions/procedures
    PROCEDURE error_message (p_name VARCHAR2, p_instance_number NUMBER DEFAULT 1, p_dbid NUMBER, p_message VARCHAR2);

    -- Generates the commands to create the advanced view SYS.YAASHS_V$SESSION for a particular target database
    PROCEDURE generate_advanced_view_target (p_name VARCHAR2, p_dbid NUMBER); 
    
    -- Repository database maintenance procedure that is scheduled daily at 00:00:01 (yaashs_repo_maintenance) and renames objects, cleans up old ASH/SQL samples and (error) messages  
    PROCEDURE repo_maintenance;

    -- Exports all target databases or a particular target database (including all corresponding ASH and SQL ID/text samples) from the repository database with Data Pump
    PROCEDURE transport_target_export (p_name VARCHAR2, p_dbid NUMBER); 

    -- Imports all target databases or a particular target database (with status IMPORTED) into the repository database with Data Pump
    PROCEDURE transport_target_import (p_name VARCHAR2, p_dbid NUMBER); 
END repo;
/
