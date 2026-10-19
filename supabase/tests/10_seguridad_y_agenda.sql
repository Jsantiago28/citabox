-- =========================================================================
-- Pruebas de seguridad multi-negocio y de agenda.
-- Se ejecutan en CI después de aplicar todas las migraciones.
-- Cada bloque falla con "FALLO: ..." si la regla no se cumple.
-- =========================================================================

\set ON_ERROR_STOP on

-- -------------------------------------------------------------------------
-- Datos de prueba (como superusuario, sin RLS)
-- -------------------------------------------------------------------------
-- Negocio A: dueño A y barbero A. Negocio B: dueño B.

insert into auth.users (id) values
  ('a0000000-0000-0000-0000-00000000000a'),
  ('a0000000-0000-0000-0000-0000000000b0'),
  ('b0000000-0000-0000-0000-00000000000b');

insert into negocios (id, nombre, slug) values
  ('11111111-1111-1111-1111-111111111111', 'Negocio A', 'negocio-a'),
  ('22222222-2222-2222-2222-222222222222', 'Negocio B', 'negocio-b');

insert into perfiles (id, negocio_id, nombre, rol) values
  ('a0000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'Dueño A', 'OWNER'),
  ('a0000000-0000-0000-0000-0000000000b0', '11111111-1111-1111-1111-111111111111', 'Barbero A', 'EMPLOYEE'),
  ('b0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'Dueño B', 'OWNER');

insert into empleados (id, negocio_id, perfil_id, nombre) values
  ('e1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111',
   'a0000000-0000-0000-0000-0000000000b0', 'Barbero A');

insert into servicios (id, negocio_id, nombre, precio, duracion_minutos) values
  ('51111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Corte', 500, 45);

insert into clientes (id, negocio_id, nombre) values
  ('c1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Cliente A');

set role authenticated;

-- -------------------------------------------------------------------------
-- Barbero A
-- -------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000b0', false);

do $$ begin
  update perfiles set rol = 'OWNER' where id = auth.uid();
  raise exception 'FALLO: el barbero pudo hacerse OWNER';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update perfiles set nombre = 'Barbero A (editado)' where id = auth.uid();
  if not found then
    raise exception 'FALLO: el barbero no pudo editar su propio nombre';
  end if;
end $$;

-- -------------------------------------------------------------------------
-- Dueño A
-- -------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-00000000000a', false);

do $$ begin
  update perfiles set activo = false where id = auth.uid();
  raise exception 'FALLO: el dueño pudo desactivarse a sí mismo';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update perfiles set rol = 'EMPLOYEE' where id = auth.uid();
  raise exception 'FALLO: el dueño pudo quitarse el rol OWNER';
exception when insufficient_privilege then null;
end $$;

-- Agenda: no se permiten citas solapadas del mismo barbero.
insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
values ('0c000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'c1111111-1111-1111-1111-111111111111', 'e1111111-1111-1111-1111-111111111111',
        '51111111-1111-1111-1111-111111111111', '2026-10-20', '10:00', '10:45', 500);

do $$ begin
  insert into citas (negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
  values ('11111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
          'e1111111-1111-1111-1111-111111111111', '51111111-1111-1111-1111-111111111111',
          '2026-10-20', '10:30', '11:00', 500);
  raise exception 'FALLO: se creó una cita que se solapa con otra';
exception when exclusion_violation then null;
end $$;

do $$ begin
  insert into citas (negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
  values ('11111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
          'e1111111-1111-1111-1111-111111111111', '51111111-1111-1111-1111-111111111111',
          '2026-10-20', '10:00', '10:30', 500);
  raise exception 'FALLO: se creó una cita a la misma hora de inicio que otra';
exception when exclusion_violation then null;
end $$;

-- Una cita que empieza justo cuando termina la otra sí cabe.
insert into citas (negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
values ('11111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
        'e1111111-1111-1111-1111-111111111111', '51111111-1111-1111-1111-111111111111',
        '2026-10-20', '10:45', '11:30', 500);

-- Una cita cancelada libera su horario.
update citas set estado = 'CANCELADA' where id = '0c000000-0000-0000-0000-000000000001';
insert into citas (negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
values ('11111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111',
        'e1111111-1111-1111-1111-111111111111', '51111111-1111-1111-1111-111111111111',
        '2026-10-20', '10:00', '10:30', 500);

-- El dueño sí puede desactivar al barbero.
do $$ begin
  update perfiles set activo = false where id = 'a0000000-0000-0000-0000-0000000000b0';
  if not found then
    raise exception 'FALLO: el dueño no pudo desactivar al barbero';
  end if;
end $$;

-- -------------------------------------------------------------------------
-- Barbero A desactivado
-- -------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000b0', false);

do $$ begin
  if (select count(*) from clientes) <> 0 or (select count(*) from citas) <> 0 then
    raise exception 'FALLO: un perfil inactivo sigue viendo datos del negocio';
  end if;
  if (select count(*) from perfiles where id = auth.uid()) <> 1 then
    raise exception 'FALLO: un perfil inactivo no puede leer su propio perfil';
  end if;
end $$;

do $$ begin
  update perfiles set activo = true where id = auth.uid();
  if found then
    raise exception 'FALLO: un perfil inactivo pudo reactivarse solo';
  end if;
exception when insufficient_privilege then null;
end $$;

-- -------------------------------------------------------------------------
-- Dueño B (otro negocio)
-- -------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-00000000000b', false);

do $$ begin
  if (select count(*) from clientes) <> 0
     or (select count(*) from citas) <> 0
     or (select count(*) from perfiles) <> 1
     or (select count(*) from negocios) <> 1 then
    raise exception 'FALLO: el negocio B ve datos del negocio A';
  end if;
end $$;

do $$ begin
  insert into clientes (negocio_id, nombre)
  values ('11111111-1111-1111-1111-111111111111', 'Intruso');
  raise exception 'FALLO: el negocio B pudo crear un cliente en el negocio A';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update clientes set nombre = 'Hackeado' where negocio_id = '11111111-1111-1111-1111-111111111111';
  if found then
    raise exception 'FALLO: el negocio B pudo editar clientes del negocio A';
  end if;
end $$;

reset role;

\echo 'Todas las pruebas de seguridad y agenda pasaron.'
