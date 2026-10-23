-- Least-privilege database roles for Kaduna AMR Watch.
--
-- Run this as a PostgreSQL superuser (or a role with CREATEROLE). Run it after
-- sql/schema.sql for existing-object grants, or before schema.sql and then run
-- schema.sql as amr_admin so that role owns the objects. Passwords are supplied
-- at run time and are never stored here.
--
-- Bash:
--   psql -d kaduna_amr \
--     -v analyst_password="$AMR_ANALYST_PASSWORD" \
--     -v loader_password="$AMR_LOADER_PASSWORD" \
--     -v admin_password="$AMR_ADMIN_PASSWORD" \
--     -f sql/roles.sql
--
-- PowerShell:
--   psql -d kaduna_amr `
--     -v analyst_password="$env:AMR_ANALYST_PASSWORD" `
--     -v loader_password="$env:AMR_LOADER_PASSWORD" `
--     -v admin_password="$env:AMR_ADMIN_PASSWORD" `
--     -f sql/roles.sql
--
-- Re-running is safe: roles are created if absent, passwords are reset, and
-- grants are re-applied. The script never drops a role or any data.

\if :{?analyst_password}
\else
  \echo 'ERROR: missing psql variable analyst_password'
  \quit
\endif

\if :{?loader_password}
\else
  \echo 'ERROR: missing psql variable loader_password'
  \quit
\endif

\if :{?admin_password}
\else
  \echo 'ERROR: missing psql variable admin_password'
  \quit
\endif

\if :{?database_name}
\else
  \set database_name kaduna_amr
\endif

SELECT format('CREATE ROLE amr_analyst LOGIN PASSWORD %L', :'analyst_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'amr_analyst')
\gexec

SELECT format('CREATE ROLE amr_loader LOGIN PASSWORD %L', :'loader_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'amr_loader')
\gexec

SELECT format('CREATE ROLE amr_admin LOGIN CREATEROLE PASSWORD %L', :'admin_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'amr_admin')
\gexec

ALTER ROLE amr_analyst WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'analyst_password';
ALTER ROLE amr_loader  WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'loader_password';
ALTER ROLE amr_admin   WITH LOGIN NOSUPERUSER NOCREATEDB CREATEROLE PASSWORD :'admin_password';

-- Start from a known state so re-running cannot leave old privileges behind.
REVOKE ALL PRIVILEGES ON DATABASE :"database_name" FROM amr_analyst, amr_loader, amr_admin;
REVOKE ALL PRIVILEGES ON SCHEMA public FROM amr_analyst, amr_loader;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM amr_analyst, amr_loader;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM amr_analyst, amr_loader;

GRANT CONNECT ON DATABASE :"database_name" TO amr_analyst, amr_loader, amr_admin;
GRANT USAGE ON SCHEMA public TO amr_analyst, amr_loader, amr_admin;

-- PostgreSQL 14 and earlier let PUBLIC create objects in the public schema.
-- Remove that so schema changes are restricted to amr_admin.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Analysts and dashboard tools may read, but never write.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO amr_analyst;

-- The loader writes data, but cannot delete it or change the schema.
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO amr_loader;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO amr_loader;

-- The admin role is for controlled schema changes only. It is not a superuser.
GRANT CREATE ON SCHEMA public TO amr_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO amr_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO amr_admin;

-- Cover objects created later by the role running this script.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO amr_analyst;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE ON TABLES TO amr_loader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO amr_loader;

-- Cover objects created later by the admin role itself.
ALTER DEFAULT PRIVILEGES FOR ROLE amr_admin IN SCHEMA public
  GRANT SELECT ON TABLES TO amr_analyst;
ALTER DEFAULT PRIVILEGES FOR ROLE amr_admin IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE ON TABLES TO amr_loader;
ALTER DEFAULT PRIVILEGES FOR ROLE amr_admin IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO amr_loader;
