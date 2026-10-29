-- =========================================================================
-- Barbería PRO — Suscripciones (cobro manual por transferencia), panel de
-- administrador de la plataforma y soporte.
-- Requiere haber aplicado 001–015 sobre la misma base.
-- =========================================================================
--
-- 1. planes y suscripciones: cada negocio nace en PRUEBA por 30 días.
-- 2. Cumplimiento: sin servicio activo (con 7 días de gracia) no entran
--    citas ni reservas en línea; el plan limita los barberos activos.
-- 3. Administrador de la plataforma: tabla sin acceso por API y RPCs que
--    verifican es_admin_plataforma().
-- 4. Soporte: los miembros del negocio reportan problemas.
-- =========================================================================

-- -------------------------------------------------------------------------
-- Planes
-- -------------------------------------------------------------------------
create table planes (
  codigo text primary key,
  nombre text not null,
  precio_mensual numeric(12, 2) not null default 0 check (precio_mensual >= 0),
  max_barberos integer check (max_barberos is null or max_barberos > 0)
);

-- Precios placeholder en 0: definir antes de cobrar.
insert into planes (codigo, nombre, precio_mensual, max_barberos) values
  ('prueba',   'Prueba',   0, null),
  ('solo',     'Solo',     0, 1),     -- definir precio
  ('barberia', 'Barbería', 0, 5),     -- definir precio
  ('pro',      'Pro',      0, null);  -- definir precio

alter table planes enable row level security;
create policy planes_lectura on planes for select to authenticated using (true);
revoke all on planes from anon;
revoke insert, update, delete on planes from authenticated;

-- -------------------------------------------------------------------------
-- Suscripciones
-- -------------------------------------------------------------------------
create table suscripciones (
  negocio_id uuid primary key references negocios (id) on delete cascade,
  plan text not null default 'prueba' references planes (codigo),
  estado text not null default 'PRUEBA'
    check (estado in ('PRUEBA', 'ACTIVA', 'VENCIDA', 'SUSPENDIDA')),
  prueba_hasta date,
  pagado_hasta date,
  notas text,
  updated_at timestamptz not null default now()
);

create trigger trg_suscripciones_updated_at
  before update on suscripciones
  for each row execute function set_updated_at();

alter table suscripciones enable row level security;
create policy suscripciones_dueno_lee on suscripciones
  for select to authenticated
  using (negocio_id = auth_negocio_id());
-- Nadie la modifica por API: solo las RPC de administrador (security definer).
revoke all on suscripciones from anon;
revoke insert, update, delete on suscripciones from authenticated;

create or replace function trg_negocio_suscripcion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into suscripciones (negocio_id, plan, estado, prueba_hasta)
  values (new.id, 'prueba', 'PRUEBA', current_date + 30)
  on conflict (negocio_id) do nothing;
  return new;
end;
$$;

create trigger trg_negocios_suscripcion
  after insert on negocios
  for each row execute function trg_negocio_suscripcion();

-- Negocios que ya existían: prueba hasta hoy + 30.
insert into suscripciones (negocio_id, plan, estado, prueba_hasta)
select id, 'prueba', 'PRUEBA', current_date + 30 from negocios
on conflict (negocio_id) do nothing;

-- -------------------------------------------------------------------------
-- ¿El negocio tiene el servicio activo? (7 días de gracia)
-- -------------------------------------------------------------------------
create or replace function negocio_servicio_activo(p_negocio uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select case s.estado
             when 'PRUEBA' then coalesce(s.prueba_hasta >= current_date - 7, false)
             when 'ACTIVA' then coalesce(s.pagado_hasta >= current_date - 7, false)
             else false
           end
      from suscripciones s
     where s.negocio_id = p_negocio
  ), false);
$$;

revoke all on function negocio_servicio_activo(uuid) from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- Cumplimiento
-- -------------------------------------------------------------------------
create or replace function trg_citas_servicio_activo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not negocio_servicio_activo(new.negocio_id) then
    raise exception 'El servicio de este negocio está pausado. Contacta a Barbería PRO.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger trg_citas_servicio_activo
  before insert on citas
  for each row execute function trg_citas_servicio_activo();

create or replace function trg_empleados_limite_plan()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max integer;
  v_activos integer;
begin
  if not new.activo then
    return new;
  end if;

  select p.max_barberos into v_max
    from suscripciones s
    join planes p on p.codigo = s.plan
   where s.negocio_id = new.negocio_id;

  if v_max is null then
    return new;
  end if;

  select count(*) into v_activos
    from empleados e
   where e.negocio_id = new.negocio_id
     and e.activo
     and e.id is distinct from new.id;

  if v_activos >= v_max then
    raise exception 'Tu plan permite hasta % barbero(s) activo(s). Cambia de plan para agregar más.', v_max
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger trg_empleados_limite_plan
  before insert or update of activo on empleados
  for each row execute function trg_empleados_limite_plan();

-- reserva_catalogo: copia exacta de 013 más la comprobación del servicio.
create or replace function reserva_catalogo(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_neg negocios;
  v_hoy date;
begin
  v_neg := reserva_priv_negocio(p_slug);

  if not negocio_servicio_activo(v_neg.id) then
    raise exception 'Esta barbería no está recibiendo reservas en línea por ahora.'
      using errcode = 'P0001';
  end if;

  v_hoy := reserva_priv_ahora(v_neg.zona_horaria)::date;

  return jsonb_build_object(
    'negocio', jsonb_build_object(
      'nombre', v_neg.nombre,
      'slug', v_neg.slug,
      'telefono', v_neg.telefono,
      'direccion', v_neg.direccion,
      'logo', v_neg.logo,
      'imagen', v_neg.imagen,
      'color_principal', v_neg.color_principal,
      'moneda', v_neg.moneda,
      'zona_horaria', v_neg.zona_horaria,
      'apartado_requerido', v_neg.apartado_requerido,
      'apartado_monto', v_neg.apartado_monto,
      'apartado_politica', v_neg.apartado_politica,
      'apartado_instrucciones', v_neg.apartado_instrucciones,
      'cancelacion_horas_minimas', v_neg.cancelacion_horas_minimas,
      'intervalo_reserva_minutos', v_neg.intervalo_reserva_minutos
    ),
    'hoy', v_hoy,
    'fecha_maxima', v_hoy + 60,
    'servicios', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id,
               'nombre', s.nombre,
               'descripcion', s.descripcion,
               'precio', s.precio,
               'duracion_minutos', s.duracion_minutos,
               'icono', s.icono,
               'imagen_url', s.imagen_url
             ) order by s.nombre, s.id)
        from servicios s
       where s.negocio_id = v_neg.id
         and s.activo
    ), '[]'::jsonb),
    'empleados', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id,
               'nombre', e.nombre,
               'foto', e.foto,
               'servicio_ids', case
                 when exists (select 1 from empleado_servicios x where x.empleado_id = e.id)
                 then coalesce((
                   select jsonb_agg(es.servicio_id order by es.servicio_id)
                     from empleado_servicios es
                     join servicios s2 on s2.id = es.servicio_id and s2.activo
                    where es.empleado_id = e.id
                 ), '[]'::jsonb)
                 else null
               end
             ) order by e.nombre, e.id)
        from empleados e
       where e.negocio_id = v_neg.id
         and e.activo
    ), '[]'::jsonb),
    'horarios', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dia_semana', h.dia_semana,
               'hora_apertura', left(h.hora_apertura::text, 5),
               'hora_cierre', left(h.hora_cierre::text, 5)
             ) order by h.dia_semana)
        from horarios_negocio h
       where h.negocio_id = v_neg.id
    ), '[]'::jsonb)
  );
end;
$$;

-- -------------------------------------------------------------------------
-- Vencimiento diario
-- -------------------------------------------------------------------------
create or replace function vencer_suscripciones()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
begin
  update suscripciones
     set estado = 'VENCIDA'
   where (estado = 'PRUEBA' and coalesce(prueba_hasta, current_date) < current_date - 7)
      or (estado = 'ACTIVA' and coalesce(pagado_hasta, current_date) < current_date - 7);
  get diagnostics v_total = row_count;
  return v_total;
end;
$$;

revoke all on function vencer_suscripciones() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('barberia-vencer-suscripciones', '10 4 * * *',
                          'select public.vencer_suscripciones()');
  else
    raise notice 'pg_cron no está disponible: vencer_suscripciones() no quedó programada.';
  end if;
exception when others then
  raise notice 'No se pudo programar vencer_suscripciones(): %', sqlerrm;
end;
$$;

-- -------------------------------------------------------------------------
-- Administrador de la plataforma
-- -------------------------------------------------------------------------
create table plataforma_admins (
  user_id uuid primary key
);
alter table plataforma_admins enable row level security;
-- Sin políticas: nadie la lee por API. Se llena a mano con el SQL editor.
revoke all on plataforma_admins from anon, authenticated;

create or replace function es_admin_plataforma()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from plataforma_admins where user_id = auth.uid());
$$;

create or replace function admin_listar_negocios()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not es_admin_plataforma() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'negocio_id', n.id,
             'nombre', n.nombre,
             'slug', n.slug,
             'dueno_correo', (
               select u.email from perfiles p
                 join auth.users u on u.id = p.id
                where p.negocio_id = n.id and p.rol = 'OWNER'
                order by p.created_at limit 1),
             'plan', s.plan,
             'estado', s.estado,
             'prueba_hasta', s.prueba_hasta,
             'pagado_hasta', s.pagado_hasta,
             'notas', s.notas,
             'barberos', (select count(*) from empleados e
                           where e.negocio_id = n.id and e.activo),
             'citas_30d', (select count(*) from citas c
                            where c.negocio_id = n.id
                              and c.created_at >= now() - interval '30 days')
           ) order by n.created_at desc)
      from negocios n
      left join suscripciones s on s.negocio_id = n.id
  ), '[]'::jsonb);
end;
$$;

create or replace function admin_activar(p_negocio uuid, p_plan text, p_hasta date)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not es_admin_plataforma() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_hasta is null then
    raise exception 'Indica hasta qué fecha queda pagado.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from planes where codigo = p_plan) then
    raise exception 'Plan desconocido.' using errcode = 'P0001';
  end if;

  insert into suscripciones (negocio_id, plan, estado, pagado_hasta)
  values (p_negocio, p_plan, 'ACTIVA', p_hasta)
  on conflict (negocio_id) do update
    set plan = excluded.plan,
        estado = 'ACTIVA',
        pagado_hasta = excluded.pagado_hasta;
end;
$$;

create or replace function admin_suspender(p_negocio uuid, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not es_admin_plataforma() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  update suscripciones
     set estado = 'SUSPENDIDA',
         notas = nullif(btrim(coalesce(p_motivo, '')), '')
   where negocio_id = p_negocio;
  if not found then
    raise exception 'Negocio sin suscripción.' using errcode = 'P0001';
  end if;
end;
$$;

-- -------------------------------------------------------------------------
-- Soporte
-- -------------------------------------------------------------------------
create table soporte (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  usuario_id uuid default auth.uid(),
  mensaje text not null check (char_length(mensaje) between 5 and 2000),
  contexto jsonb,
  created_at timestamptz not null default now()
);
create index idx_soporte_creado on soporte (created_at desc);

alter table soporte enable row level security;
create policy soporte_insert_miembros on soporte
  for insert to authenticated
  with check (negocio_id = auth_negocio_id() and usuario_id = auth.uid());
revoke all on soporte from anon;
revoke select, update, delete on soporte from authenticated;

create or replace function admin_listar_soporte()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not es_admin_plataforma() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', t.id,
             'negocio_id', t.negocio_id,
             'negocio', n.nombre,
             'usuario_id', t.usuario_id,
             'mensaje', t.mensaje,
             'contexto', t.contexto,
             'created_at', t.created_at
           ) order by t.created_at desc)
      from soporte t
      join negocios n on n.id = t.negocio_id
  ), '[]'::jsonb);
end;
$$;

-- Solo usuarios con sesión pueden llamarlas; cada una verifica que sea admin.
revoke all on function es_admin_plataforma() from public, anon;
revoke all on function admin_listar_negocios() from public, anon;
revoke all on function admin_activar(uuid, text, date) from public, anon;
revoke all on function admin_suspender(uuid, text) from public, anon;
revoke all on function admin_listar_soporte() from public, anon;
grant execute on function es_admin_plataforma() to authenticated;
grant execute on function admin_listar_negocios() to authenticated;
grant execute on function admin_activar(uuid, text, date) to authenticated;
grant execute on function admin_suspender(uuid, text) to authenticated;
grant execute on function admin_listar_soporte() to authenticated;
