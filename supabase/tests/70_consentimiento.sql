-- =========================================================================
-- Pruebas de 016: consentimiento al reservar y anonimización de clientes
-- (Ley 172-13). Negocio propio (H) y otro negocio (I) para el aislamiento.
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id) values
  ('f0000000-0000-0000-0000-00000000000a'),
  ('f0000000-0000-0000-0000-0000000000a1'),
  ('f0000000-0000-0000-0000-00000000000b');

insert into negocios (id, nombre, slug) values
  ('88888888-8888-8888-8888-888888888888', 'Negocio H', 'negocio-h'),
  ('99999999-9999-9999-9999-999999999998', 'Negocio I', 'negocio-i');

insert into perfiles (id, negocio_id, nombre, rol) values
  ('f0000000-0000-0000-0000-00000000000a', '88888888-8888-8888-8888-888888888888', 'Dueño H', 'OWNER'),
  ('f0000000-0000-0000-0000-0000000000a1', '88888888-8888-8888-8888-888888888888', 'Barbero H', 'EMPLOYEE'),
  ('f0000000-0000-0000-0000-00000000000b', '99999999-9999-9999-9999-999999999998', 'Dueño I', 'OWNER');

insert into empleados (id, negocio_id, nombre) values
  ('e8888888-0000-0000-0000-000000000001', '88888888-8888-8888-8888-888888888888', 'Barbero H');

insert into servicios (id, negocio_id, nombre, precio, duracion_minutos) values
  ('68888888-0000-0000-0000-000000000001', '88888888-8888-8888-8888-888888888888', 'Corte', 500, 30);

insert into horarios_negocio (negocio_id, dia_semana, hora_apertura, hora_cierre)
select '88888888-8888-8888-8888-888888888888', d, '08:00', '20:00' from generate_series(0, 6) d;

insert into clientes (id, negocio_id, nombre, telefono, email, notas, consentimiento_at) values
  ('c8888888-0000-0000-0000-000000000001', '88888888-8888-8888-8888-888888888888',
   'Cliente H', '8095558001', 'h@example.com', 'Nota privada', now());

insert into citas (id, negocio_id, cliente_id, empleado_id, servicio_id, fecha, hora_inicio, hora_fin, precio) values
  ('08888888-0000-0000-0000-000000000001', '88888888-8888-8888-8888-888888888888',
   'c8888888-0000-0000-0000-000000000001', 'e8888888-0000-0000-0000-000000000001',
   '68888888-0000-0000-0000-000000000001', current_date + 3, '10:00', '10:30', 500);

-- -------------------------------------------------------------------------
-- Visitante: reservar exige aceptar la política de privacidad
-- -------------------------------------------------------------------------
set role anon;

do $$
begin
  perform reserva_crear('negocio-h', '68888888-0000-0000-0000-000000000001', null,
                        current_date + 5, '11:00', 'Nuevo Cliente', '8095558002');
  raise exception 'FALLO: se reservó sin aceptar la política de privacidad';
exception when sqlstate 'P0001' then
  if sqlerrm not like 'Debes aceptar la política de privacidad%' then raise; end if;
end $$;

do $$
begin
  perform reserva_crear('negocio-h', '68888888-0000-0000-0000-000000000001', null,
                        current_date + 5, '11:00', 'Nuevo Cliente', '8095558002',
                        p_acepta_privacidad => false);
  raise exception 'FALLO: se reservó con la privacidad en false';
exception when sqlstate 'P0001' then
  if sqlerrm not like 'Debes aceptar la política de privacidad%' then raise; end if;
end $$;

-- Aceptando: se crea el cliente con consentimiento_at.
do $$
begin
  perform reserva_crear('negocio-h', '68888888-0000-0000-0000-000000000001', null,
                        current_date + 5, '11:00', 'Nuevo Cliente', '8095558002',
                        p_acepta_privacidad => true);
end $$;

-- Cliente existente que reserva de nuevo: se actualiza el consentimiento.
reset role;
update clientes set consentimiento_at = null
 where id = 'c8888888-0000-0000-0000-000000000001';
set role anon;

do $$
begin
  perform reserva_crear('negocio-h', '68888888-0000-0000-0000-000000000001', null,
                        current_date + 6, '11:00', 'Cliente H', '8095558001',
                        p_acepta_privacidad => true);
end $$;

reset role;

do $$
begin
  if (select consentimiento_at from clientes
       where negocio_id = '88888888-8888-8888-8888-888888888888'
         and telefono = '8095558002') is null then
    raise exception 'FALLO: no se guardó consentimiento_at del cliente nuevo';
  end if;
  if (select count(*) from clientes
       where negocio_id = '88888888-8888-8888-8888-888888888888'
         and telefono = '8095558001') <> 1 then
    raise exception 'FALLO: se duplicó el cliente existente';
  end if;
  if (select consentimiento_at from clientes
       where id = 'c8888888-0000-0000-0000-000000000001') is null then
    raise exception 'FALLO: no se actualizó consentimiento_at del cliente existente';
  end if;
end $$;

-- -------------------------------------------------------------------------
-- Anonimizar: solo el dueño del mismo negocio
-- -------------------------------------------------------------------------
set role authenticated;

-- Barbero: no puede.
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-0000000000a1', false);
do $$
begin
  perform anonimizar_cliente('c8888888-0000-0000-0000-000000000001');
  raise exception 'FALLO: un barbero anonimizó un cliente';
exception when insufficient_privilege then null;
end $$;

-- Dueño de otro negocio: no encuentra al cliente.
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-00000000000b', false);
do $$
begin
  perform anonimizar_cliente('c8888888-0000-0000-0000-000000000001');
  raise exception 'FALLO: el dueño de otro negocio anonimizó un cliente';
exception when sqlstate 'P0002' then null;
end $$;

-- Visitante sin sesión: sin permiso para ejecutar.
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
do $$
begin
  perform anonimizar_cliente('c8888888-0000-0000-0000-000000000001');
  raise exception 'FALLO: un visitante anonimizó un cliente';
exception when insufficient_privilege then null;
end $$;

-- Dueño del negocio: sí.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', 'f0000000-0000-0000-0000-00000000000a', false);
select anonimizar_cliente('c8888888-0000-0000-0000-000000000001');

reset role;
select set_config('request.jwt.claim.sub', '', false);

do $$
declare c clientes;
begin
  select * into c from clientes where id = 'c8888888-0000-0000-0000-000000000001';
  if c.nombre <> 'Cliente anonimizado' or c.telefono is not null or c.email is not null
     or c.notas is not null or c.activo or c.consentimiento_at is not null then
    raise exception 'FALLO: el cliente no quedó anonimizado';
  end if;
  if not exists (select 1 from citas where id = '08888888-0000-0000-0000-000000000001'
                    and cliente_id = c.id) then
    raise exception 'FALLO: la cita del cliente anonimizado no se conservó';
  end if;
end $$;

\echo 'Todas las pruebas de consentimiento (016) pasaron.'
