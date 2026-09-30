#!/usr/bin/env bash
# Runs once, when the Postgres data volume is first initialised. RDS gets the same SQL via infra/ (P7).
# Creates the layer schemas and the least-privilege read-only role (docs/conventions/security.md).
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v reader="$POSTGRES_READER_USER" -v reader_pw="$POSTGRES_READER_PASSWORD" -v db="$POSTGRES_DB" <<'SQL'
create schema if not exists raw;
create schema if not exists staging;
create schema if not exists core;
create schema if not exists marts;

select format('create role %I login password %L', :'reader', :'reader_pw')
where not exists (select 1 from pg_roles where rolname = :'reader') \gexec

grant connect on database :"db" to :"reader";
grant usage on schema core, marts to :"reader";
grant select on all tables in schema core, marts to :"reader";
-- dbt (running as the owner) recreates tables on every build, so also grant on future tables.
alter default privileges in schema core, marts grant select on tables to :"reader";
SQL
