-- =========================================================================
-- Barbería PRO — Seguridad de perfiles
-- Requiere haber aplicado 001, 002 y 003 sobre la misma base.
-- =========================================================================
--
-- PROBLEMAS QUE CORRIGE
--
-- 1. Escalada de privilegios. La política "perfiles_update_propio_o_owner"
--    deja que cada usuario actualice SU PROPIO perfil sin limitar columnas.
--    Un EMPLOYEE podía ejecutar:
--        update perfiles set rol = 'OWNER' where id = auth.uid();
--    y pasar a ser dueño del negocio. Lo mismo con "activo": un perfil
--    desactivado podía reactivarse solo.
--
-- 2. Perfiles inactivos con acceso. auth_negocio_id() no miraba "activo",
--    así que un barbero desactivado seguía leyendo y escribiendo clientes,
--    citas y apartados del negocio.
--
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Columnas protegidas de perfiles
-- -------------------------------------------------------------------------
-- Reglas:
--   - Solo un OWNER activo puede cambiar "rol" o "activo".
--   - Un OWNER no puede quitarse su propio rol ni desactivarse (evita que el
--     negocio quede sin dueño por error).
--   - Nadie puede cambiar "negocio_id" desde el cliente (el WITH CHECK de la
--     política ya lo impide; aquí queda explícito).
-- Las operaciones del servidor (service_role / SQL Editor, sin auth.uid())
-- no se ven afectadas.

create or replace function perfiles_proteger_columnas()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  if new.negocio_id is distinct from old.negocio_id then
    raise exception 'No se puede cambiar el negocio de un perfil.'
      using errcode = '42501';
  end if;

  if new.rol is distinct from old.rol or new.activo is distinct from old.activo then
    if not auth_es_owner() then
      raise exception 'Solo el dueño del negocio puede cambiar el rol o el estado de un perfil.'
        using errcode = '42501';
    end if;

    if old.id = auth.uid() then
      raise exception 'No puedes cambiar tu propio rol ni desactivar tu propia cuenta.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_perfiles_proteger_columnas
  before update on perfiles
  for each row execute function perfiles_proteger_columnas();

-- -------------------------------------------------------------------------
-- 2. Un perfil inactivo pierde el acceso al negocio
-- -------------------------------------------------------------------------
-- Todas las políticas dependen de auth_negocio_id(); al devolver NULL para
-- un perfil inactivo, ninguna política le concede filas.

create or replace function auth_negocio_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select negocio_id from perfiles where id = auth.uid() and activo = true;
$$;

-- El usuario siempre puede leer su propio perfil, aunque esté inactivo, para
-- que la app le muestre "perfil inactivo" en lugar del formulario de registro.
create policy perfiles_select_propio on perfiles
  for select using (id = auth.uid());
