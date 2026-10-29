-- =========================================================================
-- Pruebas de 017: suscripciones, cumplimiento, límite de barberos, panel de
-- administrador y soporte. Negocio propio (prefijo 80).
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id, email) values
  ('80000000-0000-0000-0000-000000000001', 'dueno80@example.com'),
  ('80000000-0000-0000-0000-000000000002', 'admin80@example.com');

insert into negocios (id, nombre, slug) values
  ('80808080-8080-8080-8080-808080808080', 'Negocio 80', 'negocio-80');

insert into perfiles (id, negocio_id, nombre, rol) values
  ('80000000-0000-0000-0000-000000000001', '80808080-8080-8080-8080-808080808080', 'Dueño 80', 'OWNER');

insert into plataforma_admins (user_id) values ('80000000-0000-0000-0000-000000000002');

insert into servicios (id, negocio_id, nombre, precio, duracion_minutos) values
  ('80000000-0000-0000-0000-0000000000a1', '80808080-8080-8080-8080-808080808080', 'Corte', 500, 30);
insert into clientes (id, negocio_id, nombre, telefono) values
  ('80000000-0000-0000-0000-0000000000c1', '80808080-8080-8080-8080-808080808080', 'Cliente 80', '8095558000');
insert into empleados (id, negocio_id, nombre) values
  ('80000000-0000-0000-0000-0000000000e1', '80808080-8080-8080-8080-808080808080', 'Barbero 80');
insert into horarios_negocio (negocio_id, dia_semana, hora_apertura, hora_cierre)
select '80808080-8080-8080-8080-808080808080', d, '08:00', '20:00' from generate_series(0, 6) d;

-- La suscripción de prueba se crea sola al registrar el negocio.
do $$ begin
  if not exists (
    select 1 from suscripciones
     where negocio_id = '80808080-8080-8080-8080-808080808080'
       and estado = 'PRUEBA' and plan = 'prueba'
       and prueba_hasta = current_date + 30
  ) then
    raise exception 'FALLO: no se creó la suscripción de prueba';
  end if;
  if not negocio_servicio_activo('80808080-8080-8080-8080-808080808080') then
    raise exception 'FALLO: un negocio en prueba debería estar activo';
  end if;
end $$;

-- Con servicio activo entran citas y el catálogo responde.
insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio) values
  ('80000000-0000-0000-0000-0000000000b1', '80808080-8080-8080-8080-808080808080',
   '80000000-0000-0000-0000-0000000000c1', '80000000-0000-0000-0000-0000000000e1',
   '80000000-0000-0000-0000-0000000000a1', current_date + 2, '10:00', '10:30', 500);
do $$ begin
  perform reserva_catalogo('negocio-80');
end $$;

-- Gracia: prueba vencida hace 5 días sigue activa; hace 8, no.
update suscripciones set prueba_hasta = current_date - 5
 where negocio_id = '80808080-8080-8080-8080-808080808080';
do $$ begin
  if not negocio_servicio_activo('80808080-8080-8080-8080-808080808080') then
    raise exception 'FALLO: dentro de la gracia debería seguir activo';
  end if;
end $$;
update suscripciones set prueba_hasta = current_date - 8
 where negocio_id = '80808080-8080-8080-8080-808080808080';
do $$ begin
  if negocio_servicio_activo('80808080-8080-8080-8080-808080808080') then
    raise exception 'FALLO: fuera de la gracia no debería estar activo';
  end if;
  if vencer_suscripciones() <> 1 then
    raise exception 'FALLO: vencer_suscripciones no venció la prueba';
  end if;
  if (select estado from suscripciones where negocio_id = '80808080-8080-8080-8080-808080808080') <> 'VENCIDA' then
    raise exception 'FALLO: la suscripción no quedó VENCIDA';
  end if;
end $$;

-- Suspendida (por el admin) bloquea citas y catálogo.
set role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', false);
select admin_activar('80808080-8080-8080-8080-808080808080', 'solo', current_date + 30);
select admin_suspender('80808080-8080-8080-8080-808080808080', 'Falta de pago');
reset role;

do $$ begin
  if (select estado from suscripciones where negocio_id = '80808080-8080-8080-8080-808080808080') <> 'SUSPENDIDA' then
    raise exception 'FALLO: admin_suspender no suspendió';
  end if;
  insert into citas (negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio)
  values ('80808080-8080-8080-8080-808080808080', '80000000-0000-0000-0000-0000000000c1',
          '80000000-0000-0000-0000-0000000000e1', '80000000-0000-0000-0000-0000000000a1',
          current_date + 3, '11:00', '11:30', 500);
  raise exception 'FALLO: se creó una cita con el servicio suspendido';
exception when sqlstate 'P0001' then
  if sqlerrm not like '%pausado%' then raise; end if;
end $$;
do $$ begin
  perform reserva_catalogo('negocio-80');
  raise exception 'FALLO: el catálogo respondió con el servicio suspendido';
exception when sqlstate 'P0001' then
  if sqlerrm not like '%no está recibiendo reservas%' then raise; end if;
end $$;

-- Reactivar y probar el límite de barberos del plan "solo" (1).
set role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', false);
select admin_activar('80808080-8080-8080-8080-808080808080', 'solo', current_date + 30);
reset role;
do $$ begin
  perform reserva_catalogo('negocio-80');
  insert into empleados (negocio_id, nombre)
  values ('80808080-8080-8080-8080-808080808080', 'Segundo barbero');
  raise exception 'FALLO: el plan solo permitió un segundo barbero activo';
exception when sqlstate 'P0001' then
  if sqlerrm not like '%Tu plan permite%' then raise; end if;
end $$;
-- Un barbero inactivo sí se puede crear.
insert into empleados (negocio_id, nombre, activo)
values ('80808080-8080-8080-8080-808080808080', 'Inactivo', false);

-- El admin ve la lista con correo del dueño; los demás no.
set role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', false);
do $$ declare v jsonb; begin
  v := admin_listar_negocios();
  if not exists (
    select 1 from jsonb_array_elements(v) x
     where x->>'slug' = 'negocio-80'
       and x->>'dueno_correo' = 'dueno80@example.com'
       and x->>'plan' = 'solo' and x->>'estado' = 'ACTIVA'
       and (x->>'barberos')::int = 1
  ) then
    raise exception 'FALLO: admin_listar_negocios no devolvió lo esperado';
  end if;
  perform admin_listar_soporte();
end $$;

-- Dueño (no admin): no puede usar las RPC, no modifica su suscripción.
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000001', false);
do $$ begin
  if es_admin_plataforma() then raise exception 'FALLO: el dueño es admin'; end if;
  begin perform admin_listar_negocios(); raise exception 'FALLO: dueño listó negocios';
  exception when insufficient_privilege then null; end;
  begin perform admin_listar_soporte(); raise exception 'FALLO: dueño leyó soporte';
  exception when insufficient_privilege then null; end;
  begin perform admin_activar('80808080-8080-8080-8080-808080808080', 'pro', current_date + 99);
    raise exception 'FALLO: dueño activó su plan';
  exception when insufficient_privilege then null; end;
  begin perform admin_suspender('80808080-8080-8080-8080-808080808080', 'x');
    raise exception 'FALLO: dueño suspendió';
  exception when insufficient_privilege then null; end;
end $$;

-- Lee SU suscripción, no puede modificarla ni leer plataforma_admins.
do $$ begin
  if (select count(*) from suscripciones) <> 1 then
    raise exception 'FALLO: el dueño debería ver solo su suscripción';
  end if;
  begin
    update suscripciones set estado = 'ACTIVA', pagado_hasta = current_date + 999;
    raise exception 'FALLO: el dueño modificó su suscripción';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from plataforma_admins;
    raise exception 'FALLO: el dueño leyó plataforma_admins';
  exception when insufficient_privilege then null; end;
end $$;

-- Soporte: inserta ok, no se lee, no se inserta a otro negocio.
insert into soporte (negocio_id, mensaje, contexto)
values ('80808080-8080-8080-8080-808080808080', 'No me carga la agenda', '{"pantalla":"agenda"}');
do $$ begin
  begin
    perform 1 from soporte;
    raise exception 'FALLO: el dueño leyó soporte';
  exception when insufficient_privilege then null; end;
  begin
    insert into soporte (negocio_id, mensaje)
    values ('80808080-8080-8080-8080-808080808080', 'abc');
    raise exception 'FALLO: se aceptó un mensaje corto';
  exception when check_violation then null; end;
  begin
    insert into soporte (negocio_id, mensaje)
    values ('55555555-5555-5555-5555-555555555555', 'Mensaje a otro negocio');
    raise exception 'FALLO: soporte en negocio ajeno';
  exception when insufficient_privilege then null; end;
end $$;

-- Visitante anónimo: nada.
reset role;
set role anon;
select set_config('request.jwt.claim.sub', '', false);
do $$ begin
  begin perform admin_listar_negocios(); raise exception 'FALLO: anon listó negocios';
  exception when insufficient_privilege then null; end;
  begin perform es_admin_plataforma(); raise exception 'FALLO: anon llamó es_admin_plataforma';
  exception when insufficient_privilege then null; end;
end $$;

-- El admin ve el mensaje de soporte.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-0000-0000-000000000002', false);
do $$ begin
  if not exists (select 1 from jsonb_array_elements(admin_listar_soporte()) x
                  where x->>'mensaje' = 'No me carga la agenda') then
    raise exception 'FALLO: el admin no ve el mensaje de soporte';
  end if;
end $$;
reset role;

-- 018: precios de lanzamiento
do $$ begin
  if (select precio_mensual from planes where codigo = 'solo') <> 400
     or (select precio_mensual from planes where codigo = 'barberia') <> 900
     or (select precio_mensual from planes where codigo = 'pro') <> 1600 then
    raise exception 'FALLO: precios de lanzamiento';
  end if;
end $$;
