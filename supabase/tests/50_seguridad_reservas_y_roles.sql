-- =========================================================================
-- Pruebas de 010: límites del barbero, perfiles, apartados, vencimiento de
-- reservas públicas y zona horaria. Negocio propio (E).
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id) values
  ('e0000000-0000-0000-0000-00000000000e'),
  ('e0000000-0000-0000-0000-0000000000e1'),
  ('e0000000-0000-0000-0000-0000000000f9');

insert into negocios (id, nombre, slug) values
  ('55555555-5555-5555-5555-555555555555', 'Negocio E', 'negocio-e');

insert into perfiles (id, negocio_id, nombre, rol) values
  ('e0000000-0000-0000-0000-00000000000e', '55555555-5555-5555-5555-555555555555', 'Dueño E', 'OWNER'),
  ('e0000000-0000-0000-0000-0000000000e1', '55555555-5555-5555-5555-555555555555', 'Barbero E1', 'EMPLOYEE');

insert into empleados (id, negocio_id, perfil_id, nombre) values
  ('e5555555-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555',
   'e0000000-0000-0000-0000-0000000000e1', 'Barbero E1'),
  ('e5555555-0000-0000-0000-000000000002', '55555555-5555-5555-5555-555555555555',
   null, 'Barbero E2');

insert into servicios (id, negocio_id, nombre, precio, duracion_minutos) values
  ('55555555-0000-0000-0000-00000000005e', '55555555-5555-5555-5555-555555555555', 'Corte', 500, 30);

insert into clientes (id, negocio_id, nombre, telefono, activo) values
  ('c5555555-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555', 'Cliente E', '8095550001', true),
  ('c5555555-0000-0000-0000-000000000002', '55555555-5555-5555-5555-555555555555', 'Vetado', '8095550002', false);

insert into horarios_negocio (negocio_id, dia_semana, hora_apertura, hora_cierre)
select '55555555-5555-5555-5555-555555555555', d, '08:00', '20:00' from generate_series(0, 6) d;

-- Cita del barbero E1 y cita del barbero E2 (creadas por el servidor).
insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio) values
  ('0e000000-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555',
   'c5555555-0000-0000-0000-000000000001', 'e5555555-0000-0000-0000-000000000001',
   '55555555-0000-0000-0000-00000000005e', current_date + 3, '10:00', '10:30', 500),
  ('0e000000-0000-0000-0000-000000000002', '55555555-5555-5555-5555-555555555555',
   'c5555555-0000-0000-0000-000000000001', 'e5555555-0000-0000-0000-000000000002',
   '55555555-0000-0000-0000-00000000005e', current_date + 3, '10:00', '10:30', 500);

insert into apartados (id, negocio_id, cita_id, monto) values
  ('a5555555-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555',
   '0e000000-0000-0000-0000-000000000001', 100);

-- Reserva pública vieja con apartado sin reportar (debe vencer) y otra reciente.
insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio, origen, created_at) values
  ('0e000000-0000-0000-0000-0000000000a1', '55555555-5555-5555-5555-555555555555',
   'c5555555-0000-0000-0000-000000000001', 'e5555555-0000-0000-0000-000000000002',
   '55555555-0000-0000-0000-00000000005e', current_date + 4, '11:00', '11:30', 500, 'PUBLICA', now() - interval '4 hours'),
  ('0e000000-0000-0000-0000-0000000000a2', '55555555-5555-5555-5555-555555555555',
   'c5555555-0000-0000-0000-000000000001', 'e5555555-0000-0000-0000-000000000002',
   '55555555-0000-0000-0000-00000000005e', current_date + 4, '12:00', '12:30', 500, 'PUBLICA', now());

insert into apartados (negocio_id, cita_id, monto) values
  ('55555555-5555-5555-5555-555555555555', '0e000000-0000-0000-0000-0000000000a1', 100),
  ('55555555-5555-5555-5555-555555555555', '0e000000-0000-0000-0000-0000000000a2', 100);

do $$ begin
  if vencer_reservas_sin_pago() <> 1 then
    raise exception 'FALLO: no venció exactamente la reserva pública vieja sin pago';
  end if;
  if (select estado from citas where id = '0e000000-0000-0000-0000-0000000000a1') <> 'CANCELADA'
     or (select estado from apartados where cita_id = '0e000000-0000-0000-0000-0000000000a1') <> 'CANCELADO' then
    raise exception 'FALLO: la reserva vencida no quedó cancelada con su apartado';
  end if;
  if (select estado from citas where id = '0e000000-0000-0000-0000-0000000000a2') <> 'PENDIENTE' then
    raise exception 'FALLO: se venció una reserva reciente';
  end if;
end $$;

-- Zona horaria inválida.
do $$ begin
  update negocios set zona_horaria = 'Marte/Olympus' where id = '55555555-5555-5555-5555-555555555555';
  raise exception 'FALLO: se aceptó una zona horaria inválida';
exception when check_violation then null;
end $$;

-- Funciones internas no ejecutables por visitantes.
do $$ begin
  if has_function_privilege('anon', 'vencer_reservas_sin_pago()', 'execute')
     or has_function_privilege('anon', 'reserva_priv_cita_json(uuid)', 'execute')
     or has_function_privilege('authenticated', 'reserva_priv_cita_json(uuid)', 'execute') then
    raise exception 'FALLO: una función interna es ejecutable por visitantes';
  end if;
end $$;

set role authenticated;

-- -------------------------------------------------------------------------
-- Barbero E1
-- -------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-0000000000e1', false);

do $$ begin
  insert into citas (negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
  values ('55555555-5555-5555-5555-555555555555', 'c5555555-0000-0000-0000-000000000001',
          'e5555555-0000-0000-0000-000000000002', '55555555-0000-0000-0000-00000000005e',
          current_date + 5, '09:00', '09:30', 500);
  raise exception 'FALLO: el barbero creó una cita en la agenda de otro';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update citas set notas = 'x' where id = '0e000000-0000-0000-0000-000000000002';
  raise exception 'FALLO: el barbero modificó la cita de otro barbero';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update citas set precio = 0 where id = '0e000000-0000-0000-0000-000000000001';
  raise exception 'FALLO: el barbero bajó el precio de su cita';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update apartados set estado = 'PAGADO' where id = 'a5555555-0000-0000-0000-000000000001';
  if found then
    raise exception 'FALLO: el barbero validó un apartado';
  end if;
end $$;

-- Sí puede cobrar su propia cita (cambiar precio al completarla).
update citas set estado = 'LLEGO' where id = '0e000000-0000-0000-0000-000000000001';
update citas set estado = 'COMPLETADA', precio = 450, metodo_pago = 'EFECTIVO'
 where id = '0e000000-0000-0000-0000-000000000001';

do $$ begin
  if (select precio from citas where id = '0e000000-0000-0000-0000-000000000001') <> 450 then
    raise exception 'FALLO: el barbero no pudo cobrar su cita';
  end if;
end $$;

-- -------------------------------------------------------------------------
-- Dueño E
-- -------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-00000000000e', false);

do $$ begin
  insert into perfiles (id, negocio_id, nombre, rol)
  values ('e0000000-0000-0000-0000-0000000000f9', '55555555-5555-5555-5555-555555555555', 'Ajeno', 'OWNER');
  raise exception 'FALLO: el dueño creó un perfil a mano';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update perfiles set id = 'e0000000-0000-0000-0000-0000000000f9'
   where id = 'e0000000-0000-0000-0000-0000000000e1';
  raise exception 'FALLO: el dueño cambió el id de un perfil';
exception when insufficient_privilege then null;
end $$;

-- Cancelar la cita de E2 cancela su apartado pendiente.
insert into apartados (negocio_id, cita_id, monto)
values ('55555555-5555-5555-5555-555555555555', '0e000000-0000-0000-0000-000000000002', 100);
update citas set estado = 'CANCELADA' where id = '0e000000-0000-0000-0000-000000000002';

do $$ begin
  if (select estado from apartados where cita_id = '0e000000-0000-0000-0000-000000000002') <> 'CANCELADO' then
    raise exception 'FALLO: cancelar la cita no canceló su apartado';
  end if;
end $$;

-- -------------------------------------------------------------------------
-- Visitante: un cliente desactivado no reserva en línea
-- -------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;

do $$
declare v_hora time;
begin
  select (h->>'hora_inicio')::time into v_hora
    from jsonb_array_elements(reserva_horas_disponibles('negocio-e', '55555555-0000-0000-0000-00000000005e',
                                                       current_date + 6, null)) h
   limit 1;
  perform reserva_crear('negocio-e', '55555555-0000-0000-0000-00000000005e', null,
                        current_date + 6, v_hora, 'Vetado', '809-555-0002');
  raise exception 'FALLO: un cliente desactivado reservó en línea';
exception when sqlstate 'P0001' then
  if sqlerrm not like 'No es posible reservar en línea%' then
    raise;
  end if;
end $$;

reset role;

\echo 'Todas las pruebas de seguridad de 010 pasaron.'
