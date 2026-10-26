-- Role permission checks for Kaduna AMR Watch.
--
-- Run after sql/schema.sql and sql/roles.sql, as a PostgreSQL superuser:
--   psql -d kaduna_amr -f sql/test_roles.sql
--
-- The "permission denied" messages below are expected. They prove that the
-- analyst cannot modify data and the loader cannot change the schema.

\set ON_ERROR_STOP off

\echo '== Analyst can read =='
SET ROLE amr_analyst;
SELECT current_user AS role, count(*) AS isolates_visible FROM isolates;

\echo '== Analyst DELETE must fail =='
DELETE FROM isolates WHERE false;

\echo '== Analyst UPDATE must fail =='
UPDATE isolates SET ward = ward WHERE false;
RESET ROLE;

\echo '== Loader can read and write, but cannot change the schema =='
SET ROLE amr_loader;
SELECT current_user AS role, count(*) AS isolates_visible FROM isolates;
CREATE TABLE __role_test_should_fail (id integer);
RESET ROLE;

\echo '== Privilege summary =='
SELECT current_user AS checked_by,
       has_table_privilege('amr_analyst', 'public.isolates', 'SELECT') AS analyst_can_select,
       has_table_privilege('amr_analyst', 'public.isolates', 'INSERT') AS analyst_can_insert,
       has_table_privilege('amr_analyst', 'public.isolates', 'UPDATE') AS analyst_can_update,
       has_table_privilege('amr_analyst', 'public.isolates', 'DELETE') AS analyst_can_delete,
       has_table_privilege('amr_loader', 'public.isolates', 'SELECT') AS loader_can_select,
       has_table_privilege('amr_loader', 'public.isolates', 'INSERT') AS loader_can_insert,
       has_table_privilege('amr_loader', 'public.isolates', 'UPDATE') AS loader_can_update,
       has_table_privilege('amr_loader', 'public.isolates', 'DELETE') AS loader_can_delete;
