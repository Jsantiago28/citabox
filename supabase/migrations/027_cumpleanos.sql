-- =========================================================================
-- Citabox — Cumpleaños del cliente
-- Requiere haber aplicado 001–026 sobre la misma base.
-- =========================================================================
--
-- Día y mes (sin año: no hace falta saber la edad). Opcional; si se pone,
-- van los dos. Al anonimizar un cliente también se borra.
-- =========================================================================

alter table clientes
  add column if not exists cumple_mes smallint,
  add column if not exists cumple_dia smallint,
  add constraint clientes_cumple_valido check (
    (cumple_mes is null and cumple_dia is null)
    or (cumple_mes between 1 and 12
        and cumple_dia between 1 and
          case when cumple_mes = 2 then 29
               when cumple_mes in (4, 6, 9, 11) then 30
               else 31 end)
  );

-- 016 más el cumpleaños.
create or replace function anonimizar_cliente(p_cliente_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not auth_es_owner() then
    raise exception 'Solo el dueño puede anonimizar clientes.' using errcode = '42501';
  end if;

  update clientes
     set nombre = 'Cliente anonimizado',
         telefono = null,
         email = null,
         notas = null,
         activo = false,
         consentimiento_at = null,
         cumple_mes = null,
         cumple_dia = null
   where id = p_cliente_id
     and negocio_id = auth_negocio_id();

  if not found then
    raise exception 'Cliente no encontrado.' using errcode = 'P0002';
  end if;
end;
$$;
