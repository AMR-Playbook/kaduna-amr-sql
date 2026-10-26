-- Role permission checks for Kaduna AMR Watch.
--
-- Run after sql/roles.sql (and sql/schema.sql, once it exists), as a
-- PostgreSQL superuser:
--   psql -d kaduna_amr -f sql/test_roles.sql
--
-- Every check prints PASS or stops with FAIL and a non-zero exit code, so it
-- can run in CI. Everything happens inside one transaction that is rolled
-- back, so the database is left exactly as it was.
--
-- This uses SET ROLE, which proves the grants but not the login itself.
-- See docs/privacy.md ("Check the analyst login") for the connection test.

\set ON_ERROR_STOP on

BEGIN;

-- Hide empty result rows; PASS/FAIL lines are notices and still show.
\o /dev/null

-- expect(role, sql, allowed): run sql as role and check it is allowed or denied.
CREATE FUNCTION pg_temp.expect(r text, stmt text, allowed boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  ok boolean := true;
BEGIN
  BEGIN
    PERFORM set_config('role', r, true);
    EXECUTE stmt;
  EXCEPTION WHEN insufficient_privilege THEN
    ok := false;
  END;
  PERFORM set_config('role', 'none', true);
  IF ok = allowed THEN
    RAISE NOTICE 'PASS  % %: %', r, CASE WHEN allowed THEN 'allowed' ELSE 'denied' END, stmt;
  ELSE
    RAISE EXCEPTION 'FAIL  % should be %: %', r, CASE WHEN allowed THEN 'allowed' ELSE 'denied' END, stmt;
  END IF;
END $$;

-- A scratch table created by amr_admin, so the test also proves that the
-- default privileges reach tables created later. It is rolled back at the end.
SET LOCAL ROLE amr_admin;
CREATE TABLE public.__role_test (id serial PRIMARY KEY, ward text);
INSERT INTO public.__role_test (ward) VALUES ('A');
RESET ROLE;

SELECT pg_temp.expect('amr_analyst', 'SELECT count(*) FROM public.__role_test', true);
SELECT pg_temp.expect('amr_analyst', 'INSERT INTO public.__role_test (ward) VALUES (''B'')', false);
SELECT pg_temp.expect('amr_analyst', 'UPDATE public.__role_test SET ward = ward', false);
SELECT pg_temp.expect('amr_analyst', 'DELETE FROM public.__role_test', false);
SELECT pg_temp.expect('amr_analyst', 'TRUNCATE public.__role_test', false);
SELECT pg_temp.expect('amr_analyst', 'CREATE TABLE public.__analyst_table (id int)', false);

SELECT pg_temp.expect('amr_loader', 'SELECT count(*) FROM public.__role_test', true);
SELECT pg_temp.expect('amr_loader', 'INSERT INTO public.__role_test (ward) VALUES (''B'')', true);
SELECT pg_temp.expect('amr_loader', 'UPDATE public.__role_test SET ward = ward', true);
SELECT pg_temp.expect('amr_loader', 'DELETE FROM public.__role_test', false);
SELECT pg_temp.expect('amr_loader', 'TRUNCATE public.__role_test', false);
SELECT pg_temp.expect('amr_loader', 'CREATE TABLE public.__loader_table (id int)', false);
SELECT pg_temp.expect('amr_loader', 'ALTER TABLE public.__role_test ADD COLUMN x int', false);

-- Every real table and view in public: the analyst may only read, and the
-- loader may never delete or truncate.
DO $$
DECLARE
  t record;
  bad int := 0;
BEGIN
  FOR t IN
    SELECT c.oid::regclass AS rel
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm', 'p')
      AND c.relname <> '__role_test'
  LOOP
    IF NOT has_table_privilege('amr_analyst', t.rel, 'SELECT') THEN
      RAISE WARNING 'amr_analyst cannot read %', t.rel; bad := bad + 1;
    END IF;
    IF has_table_privilege('amr_analyst', t.rel, 'INSERT, UPDATE, DELETE, TRUNCATE') THEN
      RAISE WARNING 'amr_analyst can write to %', t.rel; bad := bad + 1;
    END IF;
    IF has_table_privilege('amr_loader', t.rel, 'DELETE, TRUNCATE') THEN
      RAISE WARNING 'amr_loader can delete from %', t.rel; bad := bad + 1;
    END IF;
  END LOOP;
  IF bad > 0 THEN
    RAISE EXCEPTION 'FAIL  % privilege problem(s) on existing tables, see warnings above', bad;
  END IF;
  RAISE NOTICE 'PASS  existing tables: analyst read-only, loader cannot delete';
END $$;

-- No role here may be a superuser or create databases.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles
             WHERE rolname IN ('amr_analyst', 'amr_loader', 'amr_admin')
               AND (rolsuper OR rolcreatedb)) THEN
    RAISE EXCEPTION 'FAIL  an amr_* role is a superuser or can create databases';
  END IF;
  RAISE NOTICE 'PASS  no amr_* role is a superuser or can create databases';
END $$;

ROLLBACK;
\o

\echo 'All role checks passed.'
