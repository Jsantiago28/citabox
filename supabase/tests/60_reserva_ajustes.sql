-- =========================================================================
-- Pruebas de 011: horas disponibles al reprogramar (p_token) y texto por
-- defecto de la política del apartado. Usa su propio negocio (G).
-- =========================================================================

\set ON_ERROR_STOP on

-- -------------------------------------------------------------------------
-- Datos de prueba (como superusuario, sin RLS)
-- -------------------------------------------------------------------------
-- G1 y G2 trabajan todo el día y hacen todo. Abre todos los días 09–12.

insert into negocios (id, nombre, slug, intervalo_reserva_minutos)
values ('77777777-7777-7777-7777-777777777777', 'Negocio G', 'negocio-g', 30);

insert into horarios_negocio (negocio_id, dia_semana, hora_apertura, hora_cierre)
select '77777777-7777-7777-7777-777777777777', d, '09:00', '12:00'
  from generate_series(0, 6) as d;

insert into empleados (id, negocio_id, nombre, activo) values
  ('e7777777-7777-7777-7777-777777777701', '77777777-7777-7777-7777-777777777777', 'Barbero G1', true),
  ('e7777777-7777-7777-7777-777777777702', '77777777-7777-7777-7777-777777777777', 'Barbero G2', true);

insert into servicios (id, negocio_id, nombre, precio, duracion_minutos) values
  ('67777777-7777-7777-7777-777777777701', '77777777-7777-7777-7777-777777777777', 'Corte', 500, 60),
  ('67777777-7777-7777-7777-777777777702', '77777777-7777-7777-7777-777777777777', 'Barba', 300, 30);

insert into clientes (id, negocio_id, nombre, telefono) values
  ('c7777777-7777-7777-7777-777777777701', '77777777-7777-7777-7777-777777777777', 'Cliente G', '8095551111');

-- Cita de G1, Corte de 10:00 a 11:00 dentro de 5 días.
insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha,
                   hora_inicio, hora_fin, precio, token_publico)
values ('0c000000-0000-0000-0000-0000000000e1', '77777777-7777-7777-7777-777777777777',
        'c7777777-7777-7777-7777-777777777701', 'e7777777-7777-7777-7777-777777777701',
        '67777777-7777-7777-7777-777777777701', current_date + 5, '10:00', '11:00', 500,
        'a0000000-0000-0000-0000-0000000000e1');

-- Texto por defecto nuevo, sin plazo fijo.
do $$ begin
  if (select apartado_politica from negocios where slug = 'negocio-g') like '%24 horas%' then
    raise exception 'FALLO: la política por defecto todavía dice "24 horas"';
  end if;
  if (select apartado_politica from negocios where slug = 'negocio-g') not like '%plazo permitido%' then
    raise exception 'FALLO: la política por defecto no es la nueva';
  end if;
end $$;

-- -------------------------------------------------------------------------
-- Visitante sin cuenta
-- -------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '', false);
set role anon;

do $$
declare
  v jsonb;
  horas text[];
begin
  -- Sin token, Corte (60 min) con G1: 09:00 y 11:00; 09:30, 10:00 y
  -- 10:30 se cruzan con la cita de 10:00 a 11:00.
  v := reserva_horas_disponibles('negocio-g', '67777777-7777-7777-7777-777777777701',
                                 current_date + 5, 'e7777777-7777-7777-7777-777777777701');
  select array_agg(x->>'hora_inicio' order by x->>'hora_inicio') into horas
    from jsonb_array_elements(v) x;
  if horas is distinct from array['09:00', '11:00'] then
    raise exception 'FALLO: horas de G1 sin token: %', horas;
  end if;

  -- Con token: la propia cita no ocupa; aparece 10:00 y 10:30, y usa G1
  -- aunque no se indique barbero.
  v := reserva_horas_disponibles('negocio-g', '67777777-7777-7777-7777-777777777701',
                                 current_date + 5, null, 'a0000000-0000-0000-0000-0000000000e1');
  select array_agg(x->>'hora_inicio' order by x->>'hora_inicio') into horas
    from jsonb_array_elements(v) x;
  if horas is distinct from array['09:00', '09:30', '10:00', '10:30', '11:00'] then
    raise exception 'FALLO: horas con token: %', horas;
  end if;
  if exists (select 1 from jsonb_array_elements(v) x
              where x->>'empleado_id' <> 'e7777777-7777-7777-7777-777777777701') then
    raise exception 'FALLO: con token debe ofrecer solo el barbero de la cita';
  end if;

  -- Llamada con nombres sin p_token (como la app antes de 011) sigue igual.
  v := reserva_horas_disponibles(p_slug => 'negocio-g',
                                 p_servicio_id => '67777777-7777-7777-7777-777777777702',
                                 p_fecha => current_date + 5);
  if jsonb_array_length(v) = 0 then
    raise exception 'FALLO: sin token no devuelve horas';
  end if;
end $$;

-- Token con otro servicio, otro barbero, otro negocio o inexistente: P0001.
do $$
declare
  n integer := 0;
begin
  begin
    perform reserva_horas_disponibles('negocio-g', '67777777-7777-7777-7777-777777777702',
                                      current_date + 5, null, 'a0000000-0000-0000-0000-0000000000e1');
  exception when sqlstate 'P0001' then n := n + 1;
  end;
  begin
    perform reserva_horas_disponibles('negocio-g', '67777777-7777-7777-7777-777777777701',
                                      current_date + 5, 'e7777777-7777-7777-7777-777777777702',
                                      'a0000000-0000-0000-0000-0000000000e1');
  exception when sqlstate 'P0001' then n := n + 1;
  end;
  begin
    perform reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444401',
                                      current_date + 5, null, 'a0000000-0000-0000-0000-0000000000e1');
  exception when sqlstate 'P0001' then n := n + 1;
  end;
  begin
    perform reserva_horas_disponibles('negocio-g', '67777777-7777-7777-7777-777777777701',
                                      current_date + 5, null, gen_random_uuid());
  exception when sqlstate 'P0001' then n := n + 1;
  end;
  if n <> 4 then
    raise exception 'FALLO: solo % de 4 tokens inválidos dieron P0001', n;
  end if;
end $$;

-- Lo que ofrece con token es lo que acepta reserva_reprogramar.
do $$
declare
  v jsonb;
begin
  v := reserva_reprogramar('a0000000-0000-0000-0000-0000000000e1', current_date + 5, '10:30');
  if v->>'hora_inicio' <> '10:30' or v->>'hora_fin' <> '11:30' then
    raise exception 'FALLO: no se reprogramó a una hora ofrecida: %', v;
  end if;
end $$;

-- La firma vieja de 4 parámetros ya no existe (PostgREST no queda ambiguo).
reset role;
do $$ begin
  if exists (
    select 1 from pg_proc p
     where p.proname = 'reserva_horas_disponibles'
       and p.pronargs <> 5
  ) then
    raise exception 'FALLO: quedó otra versión de reserva_horas_disponibles';
  end if;
  if not has_function_privilege('anon',
       'reserva_horas_disponibles(text, uuid, date, uuid, uuid)', 'execute') then
    raise exception 'FALLO: anon no puede ejecutar reserva_horas_disponibles';
  end if;
end $$;

\echo 'Todas las pruebas de ajustes de la reserva pasaron.'

-- 012: el catálogo público devuelve el ícono del servicio.
reset role;
update servicios set icono = 'secador'
 where negocio_id = (select id from negocios where slug = 'negocio-g');
do $$ begin
  if (select reserva_catalogo('negocio-g')->'servicios'->0->>'icono') is distinct from 'secador' then
    raise exception 'FALLO: reserva_catalogo no devuelve el ícono del servicio';
  end if;
end $$;
do $$ begin
  update servicios set icono = 'Mal Ícono!' where negocio_id = (select id from negocios where slug = 'negocio-g');
  raise exception 'FALLO: se aceptó una clave de ícono inválida';
exception when check_violation then null;
end $$;
