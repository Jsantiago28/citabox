-- =========================================================================
-- Pruebas de 006: horarios, servicios por barbero, estados y apartado.
-- Usa su propio negocio (C) para no depender de otras pruebas.
-- =========================================================================

\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('c0000000-0000-0000-0000-00000000000c'),
  ('c0000000-0000-0000-0000-0000000000e0');

insert into negocios (id, nombre, slug) values
  ('33333333-3333-3333-3333-333333333333', 'Negocio C', 'negocio-c');

insert into perfiles (id, negocio_id, nombre, rol) values
  ('c0000000-0000-0000-0000-00000000000c', '33333333-3333-3333-3333-333333333333', 'Dueño C', 'OWNER'),
  ('c0000000-0000-0000-0000-0000000000e0', '33333333-3333-3333-3333-333333333333', 'Barbero C', 'EMPLOYEE');

insert into empleados (id, negocio_id, perfil_id, nombre) values
  ('e3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333',
   'c0000000-0000-0000-0000-0000000000e0', 'Barbero C');

insert into servicios (id, negocio_id, nombre, precio, duracion_minutos) values
  ('53333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'Corte', 500, 30);

insert into clientes (id, negocio_id, nombre) values
  ('c3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'Cliente C');

do $$ begin
  if (select apartado_monto from negocios where id = '33333333-3333-3333-3333-333333333333') <> 100 then
    raise exception 'FALLO: el monto del apartado por defecto no es 100';
  end if;
end $$;

set role authenticated;

-- -------------------------------------------------------------------------
-- Dueño C configura horarios y servicios
-- -------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-00000000000c', false);

insert into horarios_negocio (negocio_id, dia_semana, hora_apertura, hora_cierre)
values ('33333333-3333-3333-3333-333333333333', 1, '09:00', '18:00');

do $$ begin
  insert into horarios_negocio (negocio_id, dia_semana, hora_apertura, hora_cierre)
  values ('33333333-3333-3333-3333-333333333333', 2, '18:00', '09:00');
  raise exception 'FALLO: se guardó un horario que cierra antes de abrir';
exception when check_violation then null;
end $$;

insert into horarios_empleado (negocio_id, empleado_id, dia_semana, hora_inicio, hora_fin)
values ('33333333-3333-3333-3333-333333333333', 'e3333333-3333-3333-3333-333333333333', 1, '10:00', '16:00');

insert into bloqueos_empleado (negocio_id, empleado_id, fecha_inicio, fecha_fin, motivo)
values ('33333333-3333-3333-3333-333333333333', 'e3333333-3333-3333-3333-333333333333',
        '2026-12-24', '2026-12-26', 'Vacaciones');

insert into empleado_servicios (negocio_id, empleado_id, servicio_id)
values ('33333333-3333-3333-3333-333333333333', 'e3333333-3333-3333-3333-333333333333',
        '53333333-3333-3333-3333-333333333333');

update negocios set apartado_monto = 200, apartado_instrucciones = 'Transferir a Banco X'
 where id = '33333333-3333-3333-3333-333333333333';

-- -------------------------------------------------------------------------
-- Barbero C: lee, pero no modifica la configuración
-- -------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-0000000000e0', false);

do $$ begin
  if (select count(*) from horarios_negocio) <> 1
     or (select count(*) from horarios_empleado) <> 1
     or (select count(*) from empleado_servicios) <> 1 then
    raise exception 'FALLO: el barbero no ve los horarios de su negocio';
  end if;
end $$;

do $$ begin
  insert into horarios_negocio (negocio_id, dia_semana, hora_apertura, hora_cierre)
  values ('33333333-3333-3333-3333-333333333333', 3, '09:00', '18:00');
  raise exception 'FALLO: el barbero pudo crear un horario del negocio';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update horarios_empleado set hora_fin = '20:00';
  if found then
    raise exception 'FALLO: el barbero pudo cambiar su horario';
  end if;
end $$;

-- -------------------------------------------------------------------------
-- Estados de la cita y apartado
-- -------------------------------------------------------------------------
insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
values ('0c000000-0000-0000-0000-0000000000c1', '33333333-3333-3333-3333-333333333333',
        'c3333333-3333-3333-3333-333333333333', 'e3333333-3333-3333-3333-333333333333',
        '53333333-3333-3333-3333-333333333333', '2026-11-02', '10:00', '10:30', 500);

-- Apartado pagado → cita confirmada y fecha de pago registrada.
insert into apartados (negocio_id, cita_id, monto, metodo_pago)
values ('33333333-3333-3333-3333-333333333333', '0c000000-0000-0000-0000-0000000000c1', 200, 'TRANSFERENCIA');

update apartados set estado = 'PAGADO' where cita_id = '0c000000-0000-0000-0000-0000000000c1';

do $$ begin
  if (select estado from citas where id = '0c000000-0000-0000-0000-0000000000c1') <> 'CONFIRMADA' then
    raise exception 'FALLO: pagar el apartado no confirmó la cita';
  end if;
  if (select fecha_pago from apartados where cita_id = '0c000000-0000-0000-0000-0000000000c1') is null then
    raise exception 'FALLO: el apartado pagado no tiene fecha de pago';
  end if;
end $$;

update citas set estado = 'LLEGO' where id = '0c000000-0000-0000-0000-0000000000c1';
update citas set estado = 'COMPLETADA' where id = '0c000000-0000-0000-0000-0000000000c1';

do $$ begin
  update citas set estado = 'CANCELADA' where id = '0c000000-0000-0000-0000-0000000000c1';
  raise exception 'FALLO: se canceló una cita completada';
exception when check_violation then null;
end $$;

insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
values ('0c000000-0000-0000-0000-0000000000c2', '33333333-3333-3333-3333-333333333333',
        'c3333333-3333-3333-3333-333333333333', 'e3333333-3333-3333-3333-333333333333',
        '53333333-3333-3333-3333-333333333333', '2026-11-02', '11:00', '11:30', 500);

update citas set estado = 'CANCELADA' where id = '0c000000-0000-0000-0000-0000000000c2';

do $$ begin
  update citas set estado = 'LLEGO' where id = '0c000000-0000-0000-0000-0000000000c2';
  raise exception 'FALLO: una cita cancelada pasó a Llegó';
exception when check_violation then null;
end $$;

reset role;

\echo 'Todas las pruebas de horarios y reglas pasaron.'
