-- =========================================================================
-- Barbería PRO — Borrar los datos de demostración
-- =========================================================================
-- Deshace lo que crea supabase/seed/demo.sql en un negocio:
--   * citas con "[demo]" en las notas (y sus apartados)
--   * clientes con "[demo]" en las notas que ya no tengan citas
--   * los 3 barberos y 6 servicios de la demo, solo si ya no tienen citas
--     y (los barberos) no tienen cuenta de acceso
-- El horario del negocio NO se borra (cámbialo desde la app si quieres).
--
-- OJO: si tu negocio ya tenía un servicio o barbero con el mismo nombre
-- que los de la demo y sin citas, también se borra.
--
-- Cambia 'mi-barberia' por el slug de tu negocio y pulsa Run.
-- =========================================================================

do $$
declare
  v_slug text := 'mi-barberia';   -- <<< CAMBIA ESTO por el slug de tu negocio

  v_negocio uuid;
  n_citas int;
  n_clientes int;
  n_barberos int;
  n_servicios int;
begin
  select id into v_negocio from negocios where slug = v_slug;
  if v_negocio is null then
    raise exception 'No existe ningún negocio con el slug "%".', v_slug;
  end if;

  -- Los apartados se borran solos con su cita.
  delete from citas
   where negocio_id = v_negocio and notas like '[demo]%';
  get diagnostics n_citas = row_count;

  delete from clientes c
   where c.negocio_id = v_negocio
     and c.notas like '[demo]%'
     and not exists (select 1 from citas x where x.cliente_id = c.id);
  get diagnostics n_clientes = row_count;

  delete from empleados e
   where e.negocio_id = v_negocio
     and e.perfil_id is null
     and e.nombre in ('Carlos Peña', 'Luis Martínez', 'José "Junior" Rodríguez')
     and not exists (select 1 from citas x where x.empleado_id = e.id);
  get diagnostics n_barberos = row_count;

  delete from servicios s
   where s.negocio_id = v_negocio
     and s.nombre in ('Corte de cabello', 'Corte + barba', 'Barba', 'Cerquillo', 'Tinte', 'Corte de niño')
     and not exists (select 1 from citas x where x.servicio_id = s.id);
  get diagnostics n_servicios = row_count;

  raise notice 'Borrado en "%": % citas, % clientes, % barberos y % servicios de demostración.',
    v_slug, n_citas, n_clientes, n_barberos, n_servicios;
end;
$$;
