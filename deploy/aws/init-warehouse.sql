-- Idempotent warehouse setup on RDS, run by deploy.sh with the RDS master login (which rotates, so it is
-- used for nothing else). Mirrors docker/postgres/init/01-roles.sh for the local stack.
--   juan_loader  owns raw/staging/core/marts (dlt + dbt + Dagster)
--   juan_reader  SELECT on core + marts only (Lightdash, Cube, reviewers)
select format('create role juan_loader login password %L', :'loader_pw')
where not exists (select 1 from pg_roles where rolname = 'juan_loader') \gexec
select format('create role juan_reader login password %L', :'reader_pw')
where not exists (select 1 from pg_roles where rolname = 'juan_reader') \gexec
alter role juan_loader password :'loader_pw';
alter role juan_reader password :'reader_pw';

grant juan_loader to current_user;  -- RDS master isn't a superuser; it needs membership to set ownership

-- Dagster's own run/event storage (D-033), owned by the pipeline role.
select 'create database dagster owner juan_loader'
where not exists (select 1 from pg_database where datname = 'dagster') \gexec
grant create, connect on database juan to juan_loader;
grant connect on database juan to juan_reader;

create schema if not exists raw authorization juan_loader;
create schema if not exists staging authorization juan_loader;
create schema if not exists core authorization juan_loader;
create schema if not exists marts authorization juan_loader;

grant usage on schema core, marts to juan_reader;
grant select on all tables in schema core, marts to juan_reader;
-- dbt (as juan_loader) recreates tables every run: future tables must be readable too.
alter default privileges for role juan_loader in schema core, marts grant select on tables to juan_reader;
