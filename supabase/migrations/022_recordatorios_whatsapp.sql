-- =========================================================================
-- Barbería PRO — Recordatorios automáticos por WhatsApp (API de Meta)
-- Requiere haber aplicado 001–021 sobre la misma base.
-- =========================================================================
--
-- 1. El dueño los activa y elige con cuántas horas de anticipación.
-- 2. Cada plan trae un cupo mensual; en la prueba el cupo es un tope, en
--    los planes pagos lo que pase del cupo se cobra (precio por mensaje).
-- 3. La función enviar-recordatorios (service_role) pide las citas que
--    tocan con recordatorios_pendientes() y anota cada envío con
--    registrar_recordatorio(). Un recordatorio por cita y horario: si la
--    cita se reprograma, se envía otro.
-- =========================================================================

alter table negocios
  add column if not exists recordatorio_whatsapp boolean not null default false,
  add column if not exists recordatorio_horas integer not null default 24
    constraint negocios_recordatorio_horas_rango
      check (recordatorio_horas between 1 and 48);

alter table planes
  add column if not exists whatsapp_cupo integer not null default 0
    check (whatsapp_cupo >= 0),
  add column if not exists whatsapp_precio_extra numeric(8, 2) not null default 3
    check (whatsapp_precio_extra >= 0);

-- Cupos de lanzamiento (mensajes al mes) y RD$3 por mensaje extra.
update planes set whatsapp_cupo = 30   where codigo = 'prueba';
update planes set whatsapp_cupo = 150  where codigo = 'solo';
update planes set whatsapp_cupo = 400  where codigo = 'barberia';
update planes set whatsapp_cupo = 1000 where codigo = 'pro';

-- -------------------------------------------------------------------------
-- Registro de envíos
-- -------------------------------------------------------------------------
create table recordatorios_whatsapp (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios (id) on delete cascade,
  cita_id uuid not null references citas (id) on delete cascade,
  -- Horario de la cita cuando se envió (si se reprograma, toca otro).
  fecha date not null,
  hora time not null,
  estado text not null check (estado in ('ENVIADO', 'FALLIDO')),
  intentos integer not null default 1,
  -- Pasó del cupo del plan: se cobra aparte.
  extra boolean not null default false,
  mensaje_id text,
  error text,
  enviado_en timestamptz,
  created_at timestamptz not null default now(),
  constraint uq_recordatorio_cita_horario unique (cita_id, fecha, hora)
);

create index idx_recordatorios_negocio_enviado
  on recordatorios_whatsapp (negocio_id, enviado_en);

alter table recordatorios_whatsapp enable row level security;
create policy recordatorios_dueno_lee on recordatorios_whatsapp
  for select to authenticated
  using (negocio_id = auth_negocio_id() and auth_es_owner());
revoke all on recordatorios_whatsapp from anon;
revoke insert, update, delete on recordatorios_whatsapp from authenticated;

-- Mensajes enviados en el mes en curso (zona horaria del negocio).
create or replace function whatsapp_enviados_mes(p_negocio uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
    from recordatorios_whatsapp r
    join negocios n on n.id = r.negocio_id
   where r.negocio_id = p_negocio
     and r.estado = 'ENVIADO'
     and r.enviado_en >= (date_trunc('month', now() at time zone n.zona_horaria)
                          at time zone n.zona_horaria);
$$;

revoke all on function whatsapp_enviados_mes(uuid) from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- Para la función de envío (solo service_role)
-- -------------------------------------------------------------------------
-- Citas que entran en la ventana del recordatorio. Se omiten las reservadas
-- ya dentro de esa ventana (el cliente acaba de reservar), las que ya
-- recibieron el recordatorio y las que fallaron 3 veces. En la prueba no se
-- pasa del cupo.
create or replace function recordatorios_pendientes(p_limite integer default 200)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with candidatas as (
    select c.id as cita_id, c.fecha, c.hora_inicio,
           n.id as negocio_id, n.nombre as negocio, n.telefono as negocio_telefono,
           cl.nombre as cliente, cl.telefono,
           s.nombre as servicio, e.nombre as barbero,
           su.plan, p.whatsapp_cupo,
           row_number() over (partition by n.id
                              order by c.fecha, c.hora_inicio, c.id) as orden
      from citas c
      join negocios n on n.id = c.negocio_id
      join clientes cl on cl.id = c.cliente_id
      join servicios s on s.id = c.servicio_id
      join empleados e on e.id = c.empleado_id
      join suscripciones su on su.negocio_id = n.id
      join planes p on p.codigo = su.plan
     where n.recordatorio_whatsapp
       and n.estado = 'ACTIVO'
       and negocio_servicio_activo(n.id)
       and c.estado in ('PENDIENTE', 'CONFIRMADA')
       and c.fecha between current_date - 1 and current_date + 3
       and length(regexp_replace(coalesce(cl.telefono, ''), '\D', '', 'g')) >= 10
       and (c.fecha + c.hora_inicio) at time zone n.zona_horaria
             > now() + interval '15 minutes'
       and (c.fecha + c.hora_inicio) at time zone n.zona_horaria
             <= now() + make_interval(hours => n.recordatorio_horas)
       and c.created_at < (c.fecha + c.hora_inicio) at time zone n.zona_horaria
                          - make_interval(hours => n.recordatorio_horas)
       and not exists (
         select 1 from recordatorios_whatsapp r
          where r.cita_id = c.id
            and r.fecha = c.fecha
            and r.hora = c.hora_inicio
            and (r.estado = 'ENVIADO' or r.intentos >= 3))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'cita_id', cita_id,
           'fecha', fecha,
           'hora', left(hora_inicio::text, 5),
           'negocio', negocio,
           'negocio_telefono', negocio_telefono,
           'cliente', cliente,
           'telefono', telefono,
           'servicio', servicio,
           'barbero', barbero
         ) order by fecha, hora_inicio), '[]'::jsonb)
    from (
      select * from candidatas
       where plan <> 'prueba'
          or whatsapp_enviados_mes(negocio_id) + orden <= whatsapp_cupo
       order by fecha, hora_inicio
       limit greatest(least(p_limite, 500), 1)
    ) x;
$$;

-- Anota el resultado de un envío (éxito o fallo) para el horario actual.
create or replace function registrar_recordatorio(
  p_cita uuid,
  p_fecha date,
  p_hora time,
  p_ok boolean,
  p_mensaje_id text default null,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_negocio uuid;
  v_extra boolean := false;
begin
  select c.negocio_id into v_negocio from citas c where c.id = p_cita;
  if v_negocio is null then
    raise exception 'Cita no encontrada.' using errcode = 'P0001';
  end if;

  if p_ok then
    select whatsapp_enviados_mes(v_negocio) >= p.whatsapp_cupo into v_extra
      from suscripciones s
      join planes p on p.codigo = s.plan
     where s.negocio_id = v_negocio;
  end if;

  insert into recordatorios_whatsapp
    (negocio_id, cita_id, fecha, hora, estado, extra, mensaje_id, error, enviado_en)
  values
    (v_negocio, p_cita, p_fecha, p_hora,
     case when p_ok then 'ENVIADO' else 'FALLIDO' end,
     coalesce(v_extra, false), p_mensaje_id, left(p_error, 500),
     case when p_ok then now() end)
  on conflict (cita_id, fecha, hora) do update
    set estado = excluded.estado,
        intentos = recordatorios_whatsapp.intentos + 1,
        extra = excluded.extra,
        mensaje_id = excluded.mensaje_id,
        error = excluded.error,
        enviado_en = excluded.enviado_en
    where recordatorios_whatsapp.estado <> 'ENVIADO';
end;
$$;

revoke all on function recordatorios_pendientes(integer) from public, anon, authenticated;
revoke all on function registrar_recordatorio(uuid, date, time, boolean, text, text)
  from public, anon, authenticated;
grant execute on function recordatorios_pendientes(integer) to service_role;
grant execute on function registrar_recordatorio(uuid, date, time, boolean, text, text)
  to service_role;

-- -------------------------------------------------------------------------
-- Uso del mes para el dueño
-- -------------------------------------------------------------------------
create or replace function uso_whatsapp_mes(p_negocio uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_enviados integer;
  v_extra integer;
  v_cupo integer;
  v_precio numeric;
  v_plan text;
begin
  if p_negocio is distinct from auth_negocio_id() or not auth_es_owner() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select s.plan, p.whatsapp_cupo, p.whatsapp_precio_extra
    into v_plan, v_cupo, v_precio
    from suscripciones s
    join planes p on p.codigo = s.plan
   where s.negocio_id = p_negocio;

  v_enviados := whatsapp_enviados_mes(p_negocio);
  v_extra := greatest(v_enviados - coalesce(v_cupo, 0), 0);

  return jsonb_build_object(
    'enviados', v_enviados,
    'cupo', coalesce(v_cupo, 0),
    'extra', v_extra,
    'precio_extra', coalesce(v_precio, 0),
    'monto_extra', v_extra * coalesce(v_precio, 0),
    'prueba', coalesce(v_plan, 'prueba') = 'prueba'
  );
end;
$$;

revoke all on function uso_whatsapp_mes(uuid) from public, anon;
grant execute on function uso_whatsapp_mes(uuid) to authenticated;

-- -------------------------------------------------------------------------
-- Panel del administrador: igual que en 017 más el uso de WhatsApp del mes.
-- -------------------------------------------------------------------------
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
                              and c.created_at >= now() - interval '30 days'),
             'whatsapp_mes', whatsapp_enviados_mes(n.id),
             'whatsapp_extra', greatest(whatsapp_enviados_mes(n.id)
                                        - coalesce(pl.whatsapp_cupo, 0), 0)
           ) order by n.created_at desc)
      from negocios n
      left join suscripciones s on s.negocio_id = n.id
      left join planes pl on pl.codigo = s.plan
  ), '[]'::jsonb);
end;
$$;
