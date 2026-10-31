-- =========================================================================
-- Pruebas de 026: métricas de uso del panel del administrador.
-- Negocio propio (prefijo a4).
-- =========================================================================

\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id, email, last_sign_in_at) values
  ('a4000000-0000-0000-0000-00000000000a', 'dueno-a4@example.com', now() - interval '2 hours'),
  ('a4000000-0000-0000-0000-0000000000ad', 'admin-a4@example.com', null);

insert into negocios (id, nombre, slug, tipo) values
  ('a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4', 'Negocio Métricas', 'negocio-metricas', 'spa');
insert into perfiles (id, negocio_id, nombre, rol) values
  ('a4000000-0000-0000-0000-00000000000a', 'a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4', 'Dueña', 'OWNER');
insert into plataforma_admins (user_id) values ('a4000000-0000-0000-0000-0000000000ad');

insert into servicios (id, negocio_id, nombre, precio, duracion_minutos) values
  ('a4000000-0000-0000-0000-0000000000a1', 'a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4', 'Masaje', 1500, 60);
insert into empleados (id, negocio_id, nombre) values
  ('a4000000-0000-0000-0000-0000000000e1', 'a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4', 'Terapeuta');
insert into clientes (id, negocio_id, nombre) values
  ('a4000000-0000-0000-0000-0000000000c1', 'a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4', 'Cliente 1'),
  ('a4000000-0000-0000-0000-0000000000c2', 'a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4', 'Cliente 2');

-- Una interna y una en línea, ambas recientes.
insert into citas (negocio_id, cliente_id, empleado_id, servicio_id, fecha,
                   hora_inicio, hora_fin, precio, origen) values
  ('a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4', 'a4000000-0000-0000-0000-0000000000c1',
   'a4000000-0000-0000-0000-0000000000e1', 'a4000000-0000-0000-0000-0000000000a1',
   current_date + 3, '10:00', '11:00', 1500, 'INTERNA'),
  ('a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4', 'a4000000-0000-0000-0000-0000000000c2',
   'a4000000-0000-0000-0000-0000000000e1', 'a4000000-0000-0000-0000-0000000000a1',
   current_date + 3, '12:00', '13:00', 1500, 'PUBLICA');

set role authenticated;
select set_config('request.jwt.claim.sub', 'a4000000-0000-0000-0000-0000000000ad', false);

do $$
declare
  n jsonb;
  r jsonb := admin_resumen_uso();
begin
  select x into n
    from jsonb_array_elements(admin_listar_negocios()) x
   where x ->> 'slug' = 'negocio-metricas';

  if n is null then raise exception 'FALLO: el negocio no aparece'; end if;
  if (n ->> 'citas_30d')::int <> 2 or (n ->> 'citas_en_linea_30d')::int <> 1 then
    raise exception 'FALLO: citas del negocio: %', n;
  end if;
  if (n ->> 'clientes')::int <> 2 or n ->> 'tipo' <> 'spa' then
    raise exception 'FALLO: clientes o tipo: %', n;
  end if;
  if n ->> 'ultimo_acceso' is null or n ->> 'ultima_cita' is null then
    raise exception 'FALLO: faltan último acceso o última cita: %', n;
  end if;

  if (r ->> 'activos_7d')::int < 1 or (r ->> 'citas_en_linea_30d')::int < 1
     or (r ->> 'negocios')::int < 1 or (r ->> 'en_prueba')::int < 1 then
    raise exception 'FALLO: resumen inesperado: %', r;
  end if;
end $$;

-- Un dueño no puede ver las métricas de la plataforma.
select set_config('request.jwt.claim.sub', 'a4000000-0000-0000-0000-00000000000a', false);
do $$ begin
  perform admin_resumen_uso();
  raise exception 'FALLO: el dueño vio el resumen de la plataforma';
exception when insufficient_privilege then null;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '', false);
