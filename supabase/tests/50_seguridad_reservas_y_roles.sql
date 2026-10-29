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

-- Desde 014 ni siquiera la ve (0 filas); antes el trigger daba 42501.
do $$ begin
  update citas set notas = 'x' where id = '0e000000-0000-0000-0000-000000000002';
  if found then
    raise exception 'FALLO: el barbero modificó la cita de otro barbero';
  end if;
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
                        current_date + 6, v_hora, 'Vetado', '809-555-0002', p_acepta_privacidad => true);
  raise exception 'FALLO: un cliente desactivado reservó en línea';
exception when sqlstate 'P0001' then
  if sqlerrm not like 'No es posible reservar en línea%' then
    raise;
  end if;
end $$;

reset role;

\echo 'Todas las pruebas de seguridad de 010 pasaron.'

-- -------------------------------------------------------------------------
-- 013: fotos de servicios en Storage
-- -------------------------------------------------------------------------
set role authenticated;

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-00000000000e', false);
insert into storage.objects (bucket_id, name)
values ('servicios', '55555555-5555-5555-5555-555555555555/corte.jpg');

do $$ begin
  insert into storage.objects (bucket_id, name)
  values ('servicios', '11111111-1111-1111-1111-111111111111/intruso.jpg');
  raise exception 'FALLO: el dueño subió una foto a la carpeta de otro negocio';
exception when insufficient_privilege then null;
end $$;

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-0000000000e1', false);
do $$ begin
  insert into storage.objects (bucket_id, name)
  values ('servicios', '55555555-5555-5555-5555-555555555555/barbero.jpg');
  raise exception 'FALLO: un barbero subió una foto de servicio';
exception when insufficient_privilege then null;
end $$;

reset role;
update servicios set imagen_url = 'https://ejemplo.supabase.co/storage/v1/object/public/servicios/x.jpg'
 where id = '55555555-0000-0000-0000-00000000005e';
do $$ begin
  if (select reserva_catalogo('negocio-e')->'servicios'->0->>'imagen_url') is null then
    raise exception 'FALLO: reserva_catalogo no devuelve la foto del servicio';
  end if;
end $$;

\echo 'Pruebas de fotos de servicios pasaron.'

-- -------------------------------------------------------------------------
-- 014: el barbero solo ve sus citas y apartados; el dueño ve todo
-- -------------------------------------------------------------------------
set role authenticated;

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-0000000000e1', false);
do $$ begin
  if (select count(*) from citas) = 0 then
    raise exception 'FALLO: el barbero no ve sus propias citas';
  end if;
  if (select count(*) from citas where empleado_id <> 'e5555555-0000-0000-0000-000000000001') <> 0 then
    raise exception 'FALLO: el barbero ve citas de otro barbero';
  end if;
  if (select count(*) from apartados a join citas c on c.id = a.cita_id
       where c.empleado_id <> 'e5555555-0000-0000-0000-000000000001') <> 0
     or (select count(*) from apartados
          where cita_id in ('0e000000-0000-0000-0000-000000000002',
                            '0e000000-0000-0000-0000-0000000000a1',
                            '0e000000-0000-0000-0000-0000000000a2')) <> 0 then
    raise exception 'FALLO: el barbero ve apartados de citas de otro barbero';
  end if;
  if (select count(*) from clientes) = 0 then
    raise exception 'FALLO: el barbero ya no ve los clientes del negocio';
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-00000000000e', false);
do $$ begin
  if (select count(distinct empleado_id) from citas) < 2 then
    raise exception 'FALLO: el dueño no ve las citas de todos sus barberos';
  end if;
end $$;

reset role;

\echo 'Pruebas de visibilidad por barbero pasaron.'

-- -------------------------------------------------------------------------
-- 015: cobro cerrado para el barbero, auditoría y privilegios
-- -------------------------------------------------------------------------
set role authenticated;
select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-0000000000e1', false);

-- La cita 1 de E1 está COMPLETADA (450): no puede deshacerla ni cambiar el cobro.
do $$ begin
  update citas set estado = 'LLEGO' where id = '0e000000-0000-0000-0000-000000000001';
  raise exception 'FALLO: el barbero deshizo una cita cobrada';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update citas set propina = 999 where id = '0e000000-0000-0000-0000-000000000001';
  raise exception 'FALLO: el barbero cambió la propina de una cita cobrada';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  insert into citas (negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio, estado)
  values ('55555555-5555-5555-5555-555555555555', 'c5555555-0000-0000-0000-000000000001',
          'e5555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-00000000005e',
          current_date + 9, '15:00', '15:30', 1, 'COMPLETADA');
  raise exception 'FALLO: el barbero creó una cita ya cobrada';
exception when insufficient_privilege then null;
end $$;

-- Al crear, el precio es el del servicio aunque mande otro.
insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
values ('0e000000-0000-0000-0000-0000000000b9', '55555555-5555-5555-5555-555555555555',
        'c5555555-0000-0000-0000-000000000001', 'e5555555-0000-0000-0000-000000000001',
        '55555555-0000-0000-0000-00000000005e', current_date + 9, '16:00', '16:30', 1);

do $$ begin
  if (select precio from citas where id = '0e000000-0000-0000-0000-0000000000b9') <> 500 then
    raise exception 'FALLO: el barbero creó una cita con otro precio';
  end if;
  update clientes set activo = false where id = 'c5555555-0000-0000-0000-000000000001';
  raise exception 'FALLO: el barbero desactivó un cliente';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  if (select count(*) from auditoria) <> 0 then
    raise exception 'FALLO: el barbero puede leer la auditoría';
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-00000000000e', false);
do $$ begin
  if not exists (select 1 from auditoria
                  where tabla = 'citas' and fila_id = '0e000000-0000-0000-0000-0000000000b9'
                    and accion = 'INSERT' and usuario_id = 'e0000000-0000-0000-0000-0000000000e1') then
    raise exception 'FALLO: la auditoría no registró quién creó la cita';
  end if;
end $$;

do $$ begin
  delete from auditoria;
  if found then
    raise exception 'FALLO: el dueño pudo borrar la auditoría';
  end if;
exception when insufficient_privilege then null;
end $$;

do $$ begin
  delete from perfiles where id = 'e0000000-0000-0000-0000-00000000000e';
  raise exception 'FALLO: el dueño borró su propio perfil';
exception when insufficient_privilege then null;
end $$;

do $$ begin
  update negocios set logo = 'javascript:alert(1)' where id = '55555555-5555-5555-5555-555555555555';
  raise exception 'FALLO: se aceptó un logo sin https';
exception when check_violation then null;
end $$;

reset role;

do $$ begin
  if has_table_privilege('anon', 'citas', 'truncate')
     or has_table_privilege('authenticated', 'clientes', 'truncate') then
    raise exception 'FALLO: los roles de la API tienen TRUNCATE';
  end if;
end $$;

\echo 'Pruebas de 015 pasaron.'
