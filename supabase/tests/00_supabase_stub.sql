-- =========================================================================
-- Imitación mínima de Supabase para probar las migraciones en un
-- PostgreSQL limpio (CI). NO se aplica en el proyecto real.
-- =========================================================================

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;

create table auth.users (id uuid primary key);

-- Igual que en Supabase: el id del usuario sale del JWT de la petición.
create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- Privilegios por defecto que Supabase da sobre "public"; RLS decide el resto.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
-- Igual que Supabase: toda función nueva en "public" es ejecutable por los
-- roles de la API salvo que la migración lo revoque explícitamente.
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;
