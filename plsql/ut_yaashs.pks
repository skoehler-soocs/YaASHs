CREATE OR REPLACE PACKAGE yaashsr.ut_yaashs AS
    /*
    Author: Stefan Koehler ( http://www.soocs.de )
    Description: PL/SQL package specification for unit testing YaASHs with utPLSQL
    Use at your own risk!
    */


    --%suite(Unit Testing YaASHs - Yet another ASH simulator)
    --%rollback(manual)
    
    -- Unit test that checks if the daily maintenance job YAASHS_REPO_MAINTENANCE exists
    --%test(Case of success: Check for maintenance job in repository database)
    PROCEDURE ut_check_repo_maintenance;

    -- Unit test that alters configuration parameters in the repository database with invalid parameter names or values - all configuration changes should produce an error
    --%test(Case of failure: Altering the configuration in the repository database)
    PROCEDURE ut_alter_configuration_failure;

    -- Unit test that alters configuration parameters in the repository database with valid parameter names or values - all configuration changes should succeed here
    --%test(Case of success: Altering the configuration in the repository database)
    PROCEDURE ut_alter_configuration_success;

    -- Unit test that adds a new target database and creates the ASH sampling job for it
    --%test(Case of success: Adding a single instance target database)
    PROCEDURE ut_add_target_single_instance;

    -- Unit test that adds the same target database again - should fail in this case due to duplicate target database
    --%test(Case of failure: Adding a duplicate single instance target database)
    PROCEDURE ut_duplicate_target_single_instance;

    -- Unit test that disables the previously added target database and drops the ASH sampling job for it
    --%test(Case of success: Disabling an added target database)
    PROCEDURE ut_disable_target;

    -- Unit test that enables the previously disabled target database and creates the ASH sampling job for it
    --%test(Case of success: Enabling an added target database)
    PROCEDURE ut_enable_target;

    -- Unit test that checks the function for determining the database version in 4-digit format (e.g. 19.0)
    --%test(Case of success: Determining database version of target database)
    PROCEDURE ut_get_db_version;

    -- Unit test that cross-checks the stored metadata in the repository database with the currently used configuration (e.g. multitenant, RAC, etc.) of the target database - all checks should produce an error as stored metadata was modified before checks
    --%test(Case of failure: Cross-checking stored meta-information for target database in the repository)
    PROCEDURE ut_check_target;

    -- Unit test that sleeps for 80 seconds (because of previous configuration change of SAMPLEFREQ_SEC and SAMPLEDURA_SEC) and checks for ASH and SQL samples afterwards
    --%test(Case of success: Collecting and checking for ASH/SQL samples for target database in sample period)
    PROCEDURE ut_ash_sql_samples_success;

    -- Unit test that deletes the column mapping (needed for ASH sampling) first and checks for failure afterwards
    --%test(Case of failure: Collecting ASH/SQL samples for target database but missing/incomplete column mapping)
    PROCEDURE ut_ash_sql_samples_failure;

    -- Unit test that changes the ASH sampling type/mode for the target database with an invalid value, an invalid database version (missing advanced column mapping) or missing view SYS.YAASHS_V$SESSION - all attempts should produce an error
    --%test(Case of failure: Changing ASH sampling type/mode for target database *** Read code first. Manual steps required ***)
    --%disabled
    PROCEDURE ut_change_sampling_type_failure;

    -- Unit test that changes the ASH sampling type/mode for the target database - all should succeed here
    --%test(Case of success: Changing ASH sampling type/mode for target database)
    --%disabled
    PROCEDURE ut_change_sampling_type_success;

    -- Unit test that sleeps for 20 seconds and checks for advanced ASH samples afterwards
    --%test(Case of success: Collecting and checking for advanced ASH samples for target database)
    --%disabled
    PROCEDURE ut_advanced_ash_samples_success;

    -- Unit test that exports the previously added target database (including all corresponding ASH and SQL ID/text samples) with Data Pump
    --%test(Case of success: Exporting target database with Data Pump)
    PROCEDURE ut_export_target;

    -- Unit test that deletes the previously added target database and drops the ASH sampling job for it
    --%test(Case of success: Deleting a single instance target database)
    PROCEDURE ut_delete_target_single_instance;

    -- Unit test that "ages" almost all ASH sample data (older than RETENTION_DAYS) first and checks for cleaned up data (ASH samples, SQL samples and messages) afterwards
    --%test(Case of success: Performing daily maintenance operations inside repository database)
    PROCEDURE ut_repo_maintenance;
    
    -- Unit test that imports the previously exported target database (including all corresponding ASH and SQL ID/text samples) with Data Pump
    --%test(Case of success: Importing target database with Data Pump)
    PROCEDURE ut_import_target;    
END ut_yaashs;
/
