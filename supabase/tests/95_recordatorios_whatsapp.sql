-- =========================================================================
-- Pruebas de 022: recordatorios por WhatsApp. Negocio propio (prefijo a2).
-- Las citas son "mañana a las 10:00" en la zona del negocio con 48 h de
-- anticipación, así siempre caen en la ventana sin depender de la hora.
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id) values
  ('a2000000-0000-0000-0000-00000000000a'),
  ('a2000000-0000-0000-0000-0000000000b1');

insert into negocios (id, nombre, slug, recordatorio_whatsapp, recordatorio_horas) values
  ('a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Negocio Recordatorios', 'negocio-recordatorios', true, 48);

insert into perfiles (id, negocio_id, nombre, rol) values
  ('a2000000-0000-0000-0000-00000000000a', 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Dueño R', 'OWNER'),
  ('a2000000-0000-0000-0000-0000000000b1', 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Barbero R', 'EMPLOYEE');

insert into servicios (id, negocio_id, nombre, precio, duracion_minutos) values
  ('a2000000-0000-0000-0000-0000000000a1', 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Corte', 500, 30);
insert into empleados (id, negocio_id, nombre) values
  ('a2000000-0000-0000-0000-0000000000e1', 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Barbero R1'),
  ('a2000000-0000-0000-0000-0000000000e2', 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Barbero R2'),
  ('a2000000-0000-0000-0000-0000000000e3', 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Barbero R3'),
  ('a2000000-0000-0000-0000-0000000000e4', 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Barbero R4');
insert into clientes (id, negocio_id, nombre, telefono) values
  ('a2000000-0000-0000-0000-0000000000c1', 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Con teléfono', '809-555-0001'),
  ('a2000000-0000-0000-0000-0000000000c2', 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'Sin teléfono', null);

-- c1: reservada hace días (debe salir). c2: reservada ahora, ya dentro de la
-- ventana (no). c3: cancelada (no). c4: cliente sin teléfono (no).
insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id,
                   fecha, hora_inicio, hora_fin, precio, created_at)
select v.id::uuid, 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', v.cliente::uuid, v.empleado::uuid,
       'a2000000-0000-0000-0000-0000000000a1',
       (now() at time zone 'America/Santo_Domingo')::date + 1, '10:00', '10:30', 500, v.creada
  from (values
    ('a2000000-0000-0000-0000-0000000000d1', 'a2000000-0000-0000-0000-0000000000c1', 'a2000000-0000-0000-0000-0000000000e1', now() - interval '5 days'),
    ('a2000000-0000-0000-0000-0000000000d2', 'a2000000-0000-0000-0000-0000000000c1', 'a2000000-0000-0000-0000-0000000000e2', now()),
    ('a2000000-0000-0000-0000-0000000000d3', 'a2000000-0000-0000-0000-0000000000c1', 'a2000000-0000-0000-0000-0000000000e3', now() - interval '5 days'),
    ('a2000000-0000-0000-0000-0000000000d4', 'a2000000-0000-0000-0000-0000000000c2', 'a2000000-0000-0000-0000-0000000000e4', now() - interval '5 days')
  ) as v(id, cliente, empleado, creada);

update citas set estado = 'CANCELADA' where id = 'a2000000-0000-0000-0000-0000000000d3';

create or replace function pg_temp.pendientes()
returns setof uuid language sql as $$
  select (x ->> 'cita_id')::uuid
    from jsonb_array_elements(recordatorios_pendientes()) x
   where (x ->> 'cita_id') like 'a2000000-%';
$$;

do $$
declare
  v uuid[] := array(select pg_temp.pendientes());
begin
  if v is distinct from array['a2000000-0000-0000-0000-0000000000d1'::uuid] then
    raise exception 'FALLO: pendientes esperadas solo d1, salió %', v;
  end if;
end $$;

-- Apagado: no sale nada.
update negocios set recordatorio_whatsapp = false where id = 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2';
do $$ begin
  if exists (select pg_temp.pendientes()) then
    raise exception 'FALLO: con recordatorios apagados salieron pendientes';
  end if;
end $$;
update negocios set recordatorio_whatsapp = true where id = 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2';

-- Horas fuera de rango.
do $$ begin
  update negocios set recordatorio_horas = 0 where id = 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2';
  raise exception 'FALLO: aceptó 0 horas';
exception when check_violation then null;
end $$;

-- Tres fallos: se deja de intentar.
select registrar_recordatorio('a2000000-0000-0000-0000-0000000000d1',
       (now() at time zone 'America/Santo_Domingo')::date + 1, '10:00', false, null, 'error 1');
select registrar_recordatorio('a2000000-0000-0000-0000-0000000000d1',
       (now() at time zone 'America/Santo_Domingo')::date + 1, '10:00', false, null, 'error 2');
do $$ begin
  if not exists (select pg_temp.pendientes()) then
    raise exception 'FALLO: tras 2 fallos debería reintentar';
  end if;
end $$;
select registrar_recordatorio('a2000000-0000-0000-0000-0000000000d1',
       (now() at time zone 'America/Santo_Domingo')::date + 1, '10:00', false, null, 'error 3');
do $$ begin
  if exists (select pg_temp.pendientes()) then
    raise exception 'FALLO: tras 3 fallos no debería reintentar';
  end if;
end $$;

-- Reprogramada a las 11:00: toca otro recordatorio; se envía bien.
update citas set hora_inicio = '11:00', hora_fin = '11:30'
 where id = 'a2000000-0000-0000-0000-0000000000d1';
select registrar_recordatorio('a2000000-0000-0000-0000-0000000000d1',
       (now() at time zone 'America/Santo_Domingo')::date + 1, '11:00', true, 'wamid.1', null);
do $$ begin
  if exists (select pg_temp.pendientes()) then
    raise exception 'FALLO: ya enviado, no debería quedar pendiente';
  end if;
  if (select extra from recordatorios_whatsapp
       where cita_id = 'a2000000-0000-0000-0000-0000000000d1' and hora = '11:00') then
    raise exception 'FALLO: dentro del cupo no es extra';
  end if;
end $$;

-- Prueba con cupo 1 (ya usado): otra cita no sale.
update planes set whatsapp_cupo = 1 where codigo = 'prueba';
update citas set hora_inicio = '12:00', hora_fin = '12:30', created_at = now() - interval '5 days'
 where id = 'a2000000-0000-0000-0000-0000000000d2';
do $$ begin
  if exists (select pg_temp.pendientes()) then
    raise exception 'FALLO: la prueba no debería pasar del cupo';
  end if;
end $$;

-- En un plan pago sí sale y cuenta como extra.
update suscripciones set plan = 'solo', estado = 'ACTIVA', pagado_hasta = current_date + 30
 where negocio_id = 'a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2';
update planes set whatsapp_cupo = 1 where codigo = 'solo';
do $$ begin
  if not exists (select pg_temp.pendientes()) then
    raise exception 'FALLO: un plan pago debería enviar pasado el cupo';
  end if;
end $$;
select registrar_recordatorio('a2000000-0000-0000-0000-0000000000d2',
       (now() at time zone 'America/Santo_Domingo')::date + 1, '12:00', true, 'wamid.2', null);
do $$ begin
  if not (select extra from recordatorios_whatsapp
           where cita_id = 'a2000000-0000-0000-0000-0000000000d2') then
    raise exception 'FALLO: pasado el cupo debería ser extra';
  end if;
end $$;
update planes set whatsapp_cupo = 30 where codigo = 'prueba';
update planes set whatsapp_cupo = 150 where codigo = 'solo';

-- El dueño ve su uso; el barbero no.
set role authenticated;
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-00000000000a', false);
do $$
declare
  u jsonb := uso_whatsapp_mes('a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2');
begin
  if (u ->> 'enviados')::int <> 2 or (u ->> 'cupo')::int <> 150 or (u ->> 'extra')::int <> 0 then
    raise exception 'FALLO: uso del mes inesperado: %', u;
  end if;
  if (select count(*) from recordatorios_whatsapp) <> 3 then
    raise exception 'FALLO: el dueño debería ver sus 3 registros';
  end if;
end $$;

do $$ begin
  perform recordatorios_pendientes();
  raise exception 'FALLO: un usuario pidió los pendientes';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  perform registrar_recordatorio('a2000000-0000-0000-0000-0000000000d4', current_date, '10:00', true);
  raise exception 'FALLO: un usuario registró un envío';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  insert into recordatorios_whatsapp (negocio_id, cita_id, fecha, hora, estado)
  values ('a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2', 'a2000000-0000-0000-0000-0000000000d4',
          current_date, '10:00', 'ENVIADO');
  raise exception 'FALLO: un usuario insertó un envío';
exception when insufficient_privilege then null;
end $$;

select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-0000000000b1', false);
do $$ begin
  perform uso_whatsapp_mes('a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2');
  raise exception 'FALLO: el barbero vio el uso de WhatsApp';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  if exists (select 1 from recordatorios_whatsapp) then
    raise exception 'FALLO: el barbero ve los envíos';
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '', false);
