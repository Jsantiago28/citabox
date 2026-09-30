-- =========================================================================
-- Barbería PRO — Fase 2: Bootstrap seguro de negocio + OWNER
-- Requiere haber aplicado 001_initial_schema.sql y
-- 002_hardening_multitenant.sql sobre la misma base.
-- =========================================================================
--
-- CONTEXTO / POR QUÉ ES NECESARIA ESTA FUNCIÓN
--
-- Con las políticas actuales (Fase 1 / 1.1):
--   - "negocios" no tiene ninguna política de INSERT.
--   - "perfiles_insert_owner" exige auth_es_owner(), que a su vez exige
--     que YA exista un perfil OWNER para el usuario autenticado.
--
-- Esto es intencional: nadie puede insertar negocios/perfiles "a mano"
-- desde el cliente. Pero significa que un usuario recién registrado en
-- Supabase Auth (sin perfil todavía) NO PUEDE crear su propio negocio ni
-- su propio perfil por la vía normal (RLS se lo impide, correctamente).
--
-- La función bootstrap_negocio_owner() resuelve esto de forma controlada:
-- corre como SECURITY DEFINER (con los privilegios del rol que la creó,
-- que en Supabase es dueño de las tablas y por tanto no está sujeto a
-- RLS), pero:
--   1. Solo puede ejecutarla un usuario ya autenticado (auth.uid() no
--      nulo) — no hay ejecución anónima.
--   2. Valida que ese usuario NO tenga ya un perfil (evita que el mismo
--      usuario cree negocios adicionales reutilizando la función).
--   3. Crea el negocio y el perfil OWNER usando exclusivamente
--      auth.uid() como id del perfil — el usuario nunca puede pasar un
--      id distinto ni elegir su propio rol.
--   4. No expone ninguna otra operación (no permite update/delete de
--      negocios o perfiles arbitrarios).
--
-- No se le otorga permiso de ejecución a "anon": el usuario debe haberse
-- registrado primero mediante supabase.auth.signUp() (lo que crea su fila
-- en auth.users y, si el proyecto no exige confirmación de correo, una
-- sesión autenticada) y luego llamar a esta función ya autenticado.
--
-- LIMITACIÓN CONOCIDA (reportada al arquitecto en la entrega de esta
-- fase): si el proyecto de Supabase tiene activada la confirmación de
-- correo obligatoria, signUp() no entrega sesión inmediata y por lo
-- tanto esta función no podrá ejecutarse hasta que el usuario confirme
-- su correo e inicie sesión. El flujo para retomar el registro después
-- de confirmar el correo (guardar temporalmente nombre de negocio,
-- slug, teléfono, etc.) NO está resuelto en esta fase y requiere una
-- decisión de producto explícita del arquitecto.
--
-- =========================================================================

create or replace function bootstrap_negocio_owner(
  p_negocio_nombre text,
  p_negocio_slug text,
  p_negocio_telefono text,
  p_owner_nombre text,
  p_owner_telefono text
)
returns table (negocio_id uuid, negocio_slug text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_negocio_id uuid;
begin
  -- 1. Debe existir un usuario autenticado.
  if v_uid is null then
    raise exception 'Debes iniciar sesión antes de registrar un negocio.'
      using errcode = '28000';
  end if;

  -- 2. El usuario autenticado no debe tener ya un perfil (impide crear
  --    negocios adicionales reutilizando la misma cuenta).
  if exists (select 1 from perfiles where id = v_uid) then
    raise exception 'Esta cuenta ya tiene un negocio/perfil asociado.'
      using errcode = 'P0001';
  end if;

  -- 3. Validaciones básicas de entrada (la base de datos sigue siendo
  --    la autoridad final vía los CHECK/UNIQUE de 001_initial_schema.sql;
  --    esto solo da mensajes de error más claros antes de intentarlo).
  if coalesce(trim(p_negocio_nombre), '') = '' then
    raise exception 'El nombre del negocio es obligatorio.';
  end if;

  if coalesce(trim(p_owner_nombre), '') = '' then
    raise exception 'El nombre del propietario es obligatorio.';
  end if;

  if p_negocio_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'El slug del negocio no tiene un formato válido.';
  end if;

  -- 4. Crear el negocio.
  insert into negocios (nombre, slug, telefono)
  values (trim(p_negocio_nombre), p_negocio_slug, nullif(trim(p_negocio_telefono), ''))
  returning id into v_negocio_id;

  -- 5. Crear el perfil OWNER, forzando id = auth.uid() y rol = 'OWNER'.
  --    El usuario nunca puede elegir su propio rol ni id.
  insert into perfiles (id, negocio_id, nombre, telefono, rol, activo)
  values (v_uid, v_negocio_id, trim(p_owner_nombre), nullif(trim(p_owner_telefono), ''), 'OWNER', true);

  return query select v_negocio_id, p_negocio_slug;

exception
  when unique_violation then
    raise exception 'El slug del negocio ya está en uso. Elige otro.'
      using errcode = '23505';
end;
$$;

-- Nadie puede ejecutar esta función de forma anónima; solo usuarios ya
-- autenticados. Se revoca explícitamente de "public" y "anon" y se
-- concede solo a "authenticated".
revoke all on function bootstrap_negocio_owner(text, text, text, text, text) from public;
revoke all on function bootstrap_negocio_owner(text, text, text, text, text) from anon;
grant execute on function bootstrap_negocio_owner(text, text, text, text, text) to authenticated;

-- -------------------------------------------------------------------------
-- Verificación de disponibilidad de slug (para validar en el formulario
-- de registro antes de intentar crear el negocio). Es solo lectura de
-- un booleano; no expone ninguna fila de "negocios".
-- -------------------------------------------------------------------------

create or replace function negocio_slug_disponible(p_slug text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (select 1 from negocios where slug = p_slug);
$$;

revoke all on function negocio_slug_disponible(text) from public;
grant execute on function negocio_slug_disponible(text) to anon, authenticated;
