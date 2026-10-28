-- =========================================================================
-- Pruebas de 007: reserva pública (visitante sin cuenta, rol anon).
-- Usa su propio negocio (D) para no depender de otras pruebas. Las fechas
-- son relativas a hoy y el negocio abre todos los días, así que la prueba
-- no depende del día de la semana.
-- =========================================================================

\set ON_ERROR_STOP on

-- -------------------------------------------------------------------------
-- Datos de prueba (como superusuario, sin RLS)
-- -------------------------------------------------------------------------
-- D1: trabaja en el horario del negocio y hace todo.
-- D2: solo 14:00–16:00 y solo "Barba".
-- D3: de vacaciones. D4: inactivo.

insert into negocios (id, nombre, slug, apartado_monto, apartado_instrucciones,
                      intervalo_reserva_minutos, cancelacion_horas_minimas)
values ('44444444-4444-4444-4444-444444444444', 'Negocio D', 'negocio-d', 150,
        'Transferir a Banco D', 30, 24);

insert into horarios_negocio (negocio_id, dia_semana, hora_apertura, hora_cierre)
select '44444444-4444-4444-4444-444444444444', d, '09:00', '18:00'
  from generate_series(0, 6) as d;

insert into empleados (id, negocio_id, nombre, telefono, activo) values
  ('e4444444-4444-4444-4444-444444444401', '44444444-4444-4444-4444-444444444444', 'Barbero D1', '8095550000', true),
  ('e4444444-4444-4444-4444-444444444402', '44444444-4444-4444-4444-444444444444', 'Barbero D2', '8095550002', true),
  ('e4444444-4444-4444-4444-444444444403', '44444444-4444-4444-4444-444444444444', 'Barbero D3', '8095550003', true),
  ('e4444444-4444-4444-4444-444444444404', '44444444-4444-4444-4444-444444444444', 'Barbero D4', '8095550004', false);

insert into servicios (id, negocio_id, nombre, precio, duracion_minutos, activo) values
  ('54444444-4444-4444-4444-444444444401', '44444444-4444-4444-4444-444444444444', 'Corte', 500, 30, true),
  ('54444444-4444-4444-4444-444444444402', '44444444-4444-4444-4444-444444444444', 'Barba', 300, 45, true),
  ('54444444-4444-4444-4444-444444444403', '44444444-4444-4444-4444-444444444444', 'Tinte', 900, 60, false);

insert into horarios_empleado (negocio_id, empleado_id, dia_semana, hora_inicio, hora_fin)
select '44444444-4444-4444-4444-444444444444', 'e4444444-4444-4444-4444-444444444402', d, '14:00', '16:00'
  from generate_series(0, 6) as d;

insert into empleado_servicios (negocio_id, empleado_id, servicio_id)
values ('44444444-4444-4444-4444-444444444444', 'e4444444-4444-4444-4444-444444444402',
        '54444444-4444-4444-4444-444444444402');

insert into bloqueos_empleado (negocio_id, empleado_id, fecha_inicio, fecha_fin, motivo)
values ('44444444-4444-4444-4444-444444444444', 'e4444444-4444-4444-4444-444444444403',
        current_date - 2, current_date + 90, 'Vacaciones');

insert into clientes (id, negocio_id, nombre, telefono) values
  ('c4444444-4444-4444-4444-444444444401', '44444444-4444-4444-4444-444444444444', 'Cliente D', '8095559999');

-- Cita existente de D1 de 10:00 a 10:30 dentro de 7 días.
insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
values ('0c000000-0000-0000-0000-0000000000d1', '44444444-4444-4444-4444-444444444444',
        'c4444444-4444-4444-4444-444444444401', 'e4444444-4444-4444-4444-444444444401',
        '54444444-4444-4444-4444-444444444401', current_date + 7, '10:00', '10:30', 500);

-- -------------------------------------------------------------------------
-- Visitante sin cuenta
-- -------------------------------------------------------------------------
-- Sin JWT: visitante anónimo.
select set_config('request.jwt.claim.sub', '', false);
set role anon;

-- anon no lee tablas directamente.
do $$ begin
  if (select count(*) from clientes) <> 0
     or (select count(*) from citas) <> 0
     or (select count(*) from apartados) <> 0
     or (select count(*) from negocios) <> 0
     or (select count(*) from empleados) <> 0
     or (select count(*) from horarios_negocio) <> 0 then
    raise exception 'FALLO: anon puede leer tablas directamente';
  end if;
end $$;

-- anon no puede llamar las funciones internas.
do $$ declare ok boolean := false; begin
  begin
    perform reserva_priv_ahora('UTC');
  exception when insufficient_privilege then ok := true;
  end;
  if not ok then
    raise exception 'FALLO: anon pudo ejecutar una función interna';
  end if;
end $$;

-- Catálogo
do $$
declare
  v jsonb;
  e jsonb;
begin
  v := reserva_catalogo('negocio-d');

  if v->'negocio'->>'nombre' <> 'Negocio D' then
    raise exception 'FALLO: el catálogo no trae el negocio';
  end if;
  if (v->'negocio'->>'apartado_monto')::numeric <> 150 then
    raise exception 'FALLO: el catálogo no trae el monto del apartado';
  end if;
  if jsonb_array_length(v->'servicios') <> 2 then
    raise exception 'FALLO: el catálogo debe traer solo los 2 servicios activos';
  end if;
  if jsonb_array_length(v->'empleados') <> 3 then
    raise exception 'FALLO: el catálogo debe traer solo los 3 barberos activos';
  end if;
  if jsonb_array_length(v->'horarios') <> 7 then
    raise exception 'FALLO: el catálogo no trae el horario del negocio';
  end if;
  if v::text like '%809555%' or v::text like '%Cliente D%' then
    raise exception 'FALLO: el catálogo expone teléfonos o clientes';
  end if;

  select x into e from jsonb_array_elements(v->'empleados') x
   where x->>'id' = 'e4444444-4444-4444-4444-444444444402';
  if e->'servicio_ids' <> '["54444444-4444-4444-4444-444444444402"]'::jsonb then
    raise exception 'FALLO: servicio_ids de D2 incorrecto: %', e->'servicio_ids';
  end if;
  if e ? 'telefono' then
    raise exception 'FALLO: el catálogo trae el teléfono del barbero';
  end if;

  select x into e from jsonb_array_elements(v->'empleados') x
   where x->>'id' = 'e4444444-4444-4444-4444-444444444401';
  if jsonb_typeof(e->'servicio_ids') <> 'null' then
    raise exception 'FALLO: D1 hace todos los servicios; servicio_ids debe ser null';
  end if;
end $$;

-- Slug inexistente
do $$ declare ok boolean := false; begin
  begin
    perform reserva_catalogo('no-existe');
  exception when sqlstate 'P0001' then ok := true;
  end;
  if not ok then
    raise exception 'FALLO: un slug inexistente no dio error';
  end if;
end $$;

-- Horas disponibles
do $$
declare
  v jsonb;
begin
  -- Corte (30 min), cualquier barbero: solo D1 (D2 no lo hace, D3 de
  -- vacaciones, D4 inactivo). 09:00–17:30 = 18 horas menos la de las 10:00.
  v := reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444401', current_date + 7);
  if jsonb_array_length(v) <> 17 then
    raise exception 'FALLO: se esperaban 17 horas para Corte y hay %', jsonb_array_length(v);
  end if;
  if exists (select 1 from jsonb_array_elements(v) x
              where x->>'empleado_id' <> 'e4444444-4444-4444-4444-444444444401') then
    raise exception 'FALLO: se ofreció Corte con un barbero que no corresponde';
  end if;
  if exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' = '10:00') then
    raise exception 'FALLO: se ofreció una hora ocupada';
  end if;
  if not exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' = '09:00')
     or not exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' = '17:30')
     or exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' = '18:00') then
    raise exception 'FALLO: las horas no respetan el horario del negocio';
  end if;

  -- Barba (45 min) con D2: solo 14:00–16:00.
  v := reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444402', current_date + 7,
                                 'e4444444-4444-4444-4444-444444444402');
  if (select array_agg(x->>'hora_inicio' order by x->>'hora_inicio') from jsonb_array_elements(v) x)
     is distinct from array['14:00', '14:30', '15:00'] then
    raise exception 'FALLO: las horas de D2 no respetan su horario: %', v;
  end if;

  -- Barba (45 min) con D1: 09:30 chocaría con la cita de las 10:00.
  v := reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444402', current_date + 7,
                                 'e4444444-4444-4444-4444-444444444401');
  if exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' in ('09:30', '10:00'))
     or not exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' = '09:00')
     or not exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' = '10:30')
     or exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' > '17:15') then
    raise exception 'FALLO: las horas de Barba con D1 no respetan las citas o el cierre: %', v;
  end if;

  -- Barba, cualquier barbero: 15 horas, sin duplicar las de D2.
  v := reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444402', current_date + 7);
  if jsonb_array_length(v) <> 15 then
    raise exception 'FALLO: se esperaban 15 horas para Barba y hay %', jsonb_array_length(v);
  end if;

  -- D3 está de vacaciones.
  v := reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444401', current_date + 7,
                                 'e4444444-4444-4444-4444-444444444403');
  if jsonb_array_length(v) <> 0 then
    raise exception 'FALLO: se ofrecieron horas de un barbero bloqueado';
  end if;
end $$;

-- Horas: errores de validación
do $$
declare
  fallos int := 0;
begin
  begin
    perform reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444401', current_date + 7,
                                      'e4444444-4444-4444-4444-444444444402');
  exception when sqlstate 'P0001' then fallos := fallos + 1;
  end;
  begin
    perform reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444403', current_date + 7);
  exception when sqlstate 'P0001' then fallos := fallos + 1;
  end;
  begin
    perform reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444401', current_date + 90);
  exception when sqlstate 'P0001' then fallos := fallos + 1;
  end;
  begin
    perform reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444401', current_date - 2);
  exception when sqlstate 'P0001' then fallos := fallos + 1;
  end;
  if fallos <> 4 then
    raise exception 'FALLO: solo % de 4 validaciones de horas dieron error', fallos;
  end if;
end $$;

-- Crear reserva
do $$
declare
  v jsonb;
begin
  v := reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null, current_date + 7, '11:00',
                     'Ana Pérez', '(809) 555-1234', 'ana@example.com', 'Primera vez');

  if v->>'estado' <> 'PENDIENTE' or v->>'hora_inicio' <> '11:00' or v->>'hora_fin' <> '11:30' then
    raise exception 'FALLO: la reserva no quedó PENDIENTE de 11:00 a 11:30: %', v;
  end if;
  if v->>'empleado_id' <> 'e4444444-4444-4444-4444-444444444401' then
    raise exception 'FALLO: no se asignó el barbero libre';
  end if;
  if (v->'apartado'->>'monto')::numeric <> 150
     or v->'apartado'->>'instrucciones' <> 'Transferir a Banco D' then
    raise exception 'FALLO: la reserva no trae el apartado: %', v;
  end if;

  perform set_config('prueba.token_ana', v->>'token_publico', false);

  -- Mismo teléfono con otro formato: reutiliza el cliente.
  v := reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401',
                     'e4444444-4444-4444-4444-444444444401', current_date + 7, '12:00',
                     'Ana P.', '809-555-1234');
  perform set_config('prueba.token_ana2', v->>'token_publico', false);
end $$;

-- Doble reserva y datos inválidos
do $$
declare
  choques int := 0;
  invalidos int := 0;
begin
  begin
    perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401',
                          'e4444444-4444-4444-4444-444444444401', current_date + 7, '11:00',
                          'Pedro', '8095557777');
  exception when exclusion_violation then choques := choques + 1;
  end;
  begin
    perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null,
                          current_date + 7, '11:00', 'Pedro', '8095557777');
  exception when exclusion_violation then choques := choques + 1;
  end;
  begin
    -- Barba de 45 min a las 10:30 (hasta 11:15) chocaría con la de las 11:00.
    perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444402',
                          'e4444444-4444-4444-4444-444444444401', current_date + 7, '10:30',
                          'Pedro', '8095557777');
  exception when exclusion_violation then choques := choques + 1;
  end;
  if choques <> 3 then
    raise exception 'FALLO: solo % de 3 dobles reservas fueron rechazadas', choques;
  end if;

  begin
    perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null,
                          current_date + 7, '13:00', 'Pedro', '12345');
  exception when sqlstate 'P0001' then invalidos := invalidos + 1;
  end;
  begin
    perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null,
                          current_date + 7, '13:00', '  ', '8095557777');
  exception when sqlstate 'P0001' then invalidos := invalidos + 1;
  end;
  begin
    perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null,
                          current_date + 7, '13:00', 'Pedro', '8095557777', 'no-es-correo');
  exception when sqlstate 'P0001' then invalidos := invalidos + 1;
  end;
  if invalidos <> 3 then
    raise exception 'FALLO: solo % de 3 datos inválidos fueron rechazados', invalidos;
  end if;
end $$;

-- Consultar
do $$
declare
  v jsonb;
  ok boolean := false;
begin
  v := reserva_consultar(current_setting('prueba.token_ana')::uuid);

  if v->>'estado' <> 'PENDIENTE'
     or v->>'hora_inicio' <> '11:00'
     or v->>'hora_fin' <> '11:30'
     or (v->>'precio')::numeric <> 500
     or v->'servicio'->>'nombre' <> 'Corte'
     or v->'barbero'->>'nombre' <> 'Barbero D1'
     or v->'negocio'->>'slug' <> 'negocio-d'
     or v->'apartado'->>'estado' <> 'PENDIENTE'
     or not (v->>'puede_cancelar')::boolean
     or not (v->>'puede_reprogramar')::boolean then
    raise exception 'FALLO: la consulta de la cita no es correcta: %', v;
  end if;
  if v::text like '%Ana%' or v::text like '%8095551234%' or v::text like '%555-1234%' then
    raise exception 'FALLO: la consulta expone datos del cliente o del barbero';
  end if;

  begin
    perform reserva_consultar('00000000-0000-0000-0000-000000000000');
  exception when sqlstate 'P0001' then ok := true;
  end;
  if not ok then
    raise exception 'FALLO: un token inexistente no dio error';
  end if;
end $$;

-- Reportar pago
do $$
declare
  v jsonb;
  ok boolean := false;
begin
  v := reserva_reportar_pago(current_setting('prueba.token_ana')::uuid, '  REF-123 ');
  if v->'apartado'->>'referencia' <> 'REF-123' or v->'apartado'->>'estado' <> 'PENDIENTE' then
    raise exception 'FALLO: no se guardó la referencia del pago: %', v;
  end if;

  begin
    perform reserva_reportar_pago(current_setting('prueba.token_ana')::uuid, 'ab');
  exception when sqlstate 'P0001' then ok := true;
  end;
  if not ok then
    raise exception 'FALLO: se aceptó una referencia demasiado corta';
  end if;
end $$;

-- Reprogramar
do $$
declare
  v jsonb;
  choques int := 0;
  ok boolean := false;
begin
  v := reserva_reprogramar(current_setting('prueba.token_ana')::uuid, current_date + 7, '15:00');
  if v->>'hora_inicio' <> '15:00' or v->>'hora_fin' <> '15:30' then
    raise exception 'FALLO: la cita no se reprogramó: %', v;
  end if;

  -- Reprogramar sobre su propio horario (excluye la propia cita).
  v := reserva_reprogramar(current_setting('prueba.token_ana')::uuid, current_date + 7, '15:00');

  v := reserva_horas_disponibles('negocio-d', '54444444-4444-4444-4444-444444444401', current_date + 7,
                                 'e4444444-4444-4444-4444-444444444401');
  if not exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' = '11:00')
     or exists (select 1 from jsonb_array_elements(v) x where x->>'hora_inicio' in ('12:00', '15:00')) then
    raise exception 'FALLO: reprogramar no liberó u ocupó las horas correctas: %', v;
  end if;

  begin
    perform reserva_reprogramar(current_setting('prueba.token_ana')::uuid, current_date + 7, '10:00');
  exception when exclusion_violation then choques := choques + 1;
  end;
  begin
    perform reserva_reprogramar(current_setting('prueba.token_ana')::uuid, current_date + 7, '12:00');
  exception when exclusion_violation then choques := choques + 1;
  end;
  if choques <> 2 then
    raise exception 'FALLO: se reprogramó sobre una hora ocupada';
  end if;

  begin
    perform reserva_reprogramar(current_setting('prueba.token_ana')::uuid, current_date + 90, '10:00');
  exception when sqlstate 'P0001' then ok := true;
  end;
  if not ok then
    raise exception 'FALLO: se reprogramó fuera del rango de fechas';
  end if;
end $$;

-- Cancelar
do $$
declare
  v jsonb;
  fallos int := 0;
begin
  v := reserva_cancelar(current_setting('prueba.token_ana')::uuid);
  if v->>'estado' <> 'CANCELADA'
     or v->'apartado'->>'estado' <> 'CANCELADO'
     or (v->>'puede_cancelar')::boolean then
    raise exception 'FALLO: la cancelación no es correcta: %', v;
  end if;

  begin
    perform reserva_cancelar(current_setting('prueba.token_ana')::uuid);
  exception when sqlstate 'P0001' then fallos := fallos + 1;
  end;
  begin
    perform reserva_reprogramar(current_setting('prueba.token_ana')::uuid, current_date + 7, '16:00');
  exception when sqlstate 'P0001' then fallos := fallos + 1;
  end;
  begin
    perform reserva_reportar_pago(current_setting('prueba.token_ana')::uuid, 'REF-999');
  exception when sqlstate 'P0001' then fallos := fallos + 1;
  end;
  if fallos <> 3 then
    raise exception 'FALLO: una cita cancelada aceptó % de 3 cambios', 3 - fallos;
  end if;
end $$;

-- Citas para las pruebas de plazo, apartado pagado y límite.
do $$
declare
  v jsonb;
begin
  v := reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null, current_date + 3, '10:00',
                     'Luis', '8095553333');
  perform set_config('prueba.token_plazo', v->>'token_publico', false);

  v := reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null, current_date + 8, '10:00',
                     'Marta', '8095554444');
  perform set_config('prueba.token_pagado', v->>'token_publico', false);
end $$;

-- Límite: máximo 3 citas futuras activas por teléfono.
do $$
declare
  ok boolean := false;
begin
  perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null, current_date + 9, '09:00',
                        'Rosa', '8095552222');
  perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null, current_date + 9, '09:30',
                        'Rosa', '8095552222');
  perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null, current_date + 9, '10:00',
                        'Rosa', '809 555 2222');
  begin
    perform reserva_crear('negocio-d', '54444444-4444-4444-4444-444444444401', null, current_date + 9, '10:30',
                          'Rosa', '8095552222');
  exception when sqlstate 'P0001' then ok := true;
  end;
  if not ok then
    raise exception 'FALLO: se permitió una cuarta cita con el mismo teléfono';
  end if;
end $$;

-- -------------------------------------------------------------------------
-- Verificaciones como superusuario
-- -------------------------------------------------------------------------
reset role;

do $$ begin
  if (select count(*) from clientes
       where negocio_id = '44444444-4444-4444-4444-444444444444'
         and regexp_replace(telefono, '\D', '', 'g') = '8095551234') <> 1 then
    raise exception 'FALLO: el mismo teléfono creó clientes duplicados';
  end if;
  if (select email from clientes
       where negocio_id = '44444444-4444-4444-4444-444444444444'
         and regexp_replace(telefono, '\D', '', 'g') = '8095551234') <> 'ana@example.com' then
    raise exception 'FALLO: no se guardó el correo del cliente';
  end if;
  if (select count(*) from clientes
       where negocio_id = '44444444-4444-4444-4444-444444444444'
         and regexp_replace(telefono, '\D', '', 'g') = '8095552222') <> 1 then
    raise exception 'FALLO: Rosa quedó duplicada';
  end if;
  if (select count(*) from citas c
        join clientes cl on cl.id = c.cliente_id
       where regexp_replace(cl.telefono, '\D', '', 'g') = '8095551234') <> 2 then
    raise exception 'FALLO: Ana debería tener 2 citas';
  end if;
  if exists (select 1 from apartados a join citas c on c.id = a.cita_id
              where c.token_publico = current_setting('prueba.token_ana')::uuid
                and (a.metodo_pago is distinct from 'TRANSFERENCIA' or a.referencia is distinct from 'REF-123')) then
    raise exception 'FALLO: el apartado no guardó método y referencia';
  end if;
  if (select count(distinct token_publico) from citas) <> (select count(*) from citas) then
    raise exception 'FALLO: hay tokens públicos repetidos';
  end if;
end $$;

-- El dueño valida el apartado de Marta → cita CONFIRMADA.
update apartados a
   set estado = 'PAGADO'
  from citas c
 where c.id = a.cita_id
   and c.token_publico = current_setting('prueba.token_pagado')::uuid;

-- El negocio exige 7 días de anticipación para cambios.
update negocios set cancelacion_horas_minimas = 168
 where id = '44444444-4444-4444-4444-444444444444';

set role anon;

-- Fuera de plazo (cita dentro de 3 días, plazo de 7 días).
do $$
declare
  v jsonb;
  fallos int := 0;
begin
  v := reserva_consultar(current_setting('prueba.token_plazo')::uuid);
  if (v->>'puede_cancelar')::boolean or (v->>'puede_reprogramar')::boolean then
    raise exception 'FALLO: una cita fuera de plazo aparece como cancelable';
  end if;

  begin
    perform reserva_cancelar(current_setting('prueba.token_plazo')::uuid);
  exception when sqlstate 'P0001' then fallos := fallos + 1;
  end;
  begin
    perform reserva_reprogramar(current_setting('prueba.token_plazo')::uuid, current_date + 20, '10:00');
  exception when sqlstate 'P0001' then fallos := fallos + 1;
  end;
  if fallos <> 2 then
    raise exception 'FALLO: se cambió una cita fuera de plazo';
  end if;
end $$;

reset role;
update negocios set cancelacion_horas_minimas = 24
 where id = '44444444-4444-4444-4444-444444444444';
set role anon;

-- Cancelar con apartado pagado: la cita se cancela, el apartado queda PAGADO.
do $$
declare
  v jsonb;
begin
  v := reserva_consultar(current_setting('prueba.token_pagado')::uuid);
  if v->>'estado' <> 'CONFIRMADA' or v->'apartado'->>'estado' <> 'PAGADO' then
    raise exception 'FALLO: pagar el apartado no confirmó la cita: %', v;
  end if;

  v := reserva_cancelar(current_setting('prueba.token_pagado')::uuid);
  if v->>'estado' <> 'CANCELADA' or v->'apartado'->>'estado' <> 'PAGADO' then
    raise exception 'FALLO: cancelar cambió un apartado pagado: %', v;
  end if;
end $$;

reset role;

do $$ begin
  if (select c.estado from citas c
       where c.token_publico = current_setting('prueba.token_plazo')::uuid) <> 'PENDIENTE' then
    raise exception 'FALLO: la cita fuera de plazo cambió de estado';
  end if;
end $$;

\echo 'Todas las pruebas de reserva pública pasaron.'
