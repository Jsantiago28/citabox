-- =========================================================================
-- Barbería PRO — El barbero solo ve sus propias citas y apartados
-- Requiere haber aplicado 001–013 sobre la misma base.
-- =========================================================================
--
-- Hasta ahora la app mostraba al barbero solo "Mi agenda", pero la base le
-- dejaba leer las citas y apartados de todo el negocio. Desde aquí:
--   - El dueño ve todo su negocio (sin cambios).
--   - El barbero (EMPLOYEE) solo ve las citas de su ficha de empleado y los
--     apartados de esas citas.
-- Los clientes siguen siendo del negocio: cualquier barbero puede buscarlos
-- para darles cita. Las funciones de reserva pública no se ven afectadas.
-- =========================================================================

-- Ficha de empleado del usuario actual en su negocio (null si no tiene).
create or replace function auth_empleado_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select e.id
    from empleados e
   where e.perfil_id = auth.uid()
     and e.negocio_id = auth_negocio_id()
   limit 1;
$$;

-- Igual que auth_negocio_id(): las políticas la evalúan también para
-- visitantes (anon), a quienes siempre devuelve null.
grant execute on function auth_empleado_id() to anon, authenticated;

drop policy citas_select_mismo_negocio on citas;

create policy citas_select_owner_o_propias on citas
  for select using (
    negocio_id = auth_negocio_id()
    and (auth_es_owner() or empleado_id = auth_empleado_id())
  );

drop policy apartados_select_mismo_negocio on apartados;

create policy apartados_select_owner_o_propios on apartados
  for select using (
    negocio_id = auth_negocio_id()
    and (
      auth_es_owner()
      or exists (
        select 1
          from citas c
         where c.id = apartados.cita_id
           and c.empleado_id = auth_empleado_id()
      )
    )
  );
