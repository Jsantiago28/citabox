-- =========================================================================
-- Barbería PRO — Recordatorios automáticos como servicio adicional
-- Requiere haber aplicado 001–022 sobre la misma base.
-- =========================================================================
--
-- Por defecto los recordatorios los envía el dueño o el barbero desde la
-- Agenda (botón de WhatsApp). El envío automático ya no lo enciende el
-- dueño ni viene incluido en los planes: lo activa el administrador para
-- cada negocio que lo contrate, con su cupo y sus precios.
-- El dueño solo elige con cuántas horas de anticipación se envía.
-- =========================================================================

alter table suscripciones
  add column if not exists recordatorios_auto boolean not null default false,
  add column if not exists whatsapp_cupo integer not null default 0
    check (whatsapp_cupo >= 0),
  add column if not exists whatsapp_precio_mensual numeric(10, 2) not null default 0
    check (whatsapp_precio_mensual >= 0),
  add column if not exists whatsapp_precio_extra numeric(8, 2) not null default 0
    check (whatsapp_precio_extra >= 0);

-- -------------------------------------------------------------------------
-- Para la función de envío (solo service_role)
-- -------------------------------------------------------------------------
create or replace function recordatorios_pendientes(p_limite integer default 200)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
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
      select c.id as cita_id, c.fecha, c.hora_inicio,
             n.nombre as negocio, n.telefono as negocio_telefono,
             cl.nombre as cliente, cl.telefono,
             s.nombre as servicio, e.nombre as barbero
        from citas c
        join negocios n on n.id = c.negocio_id
        join suscripciones su on su.negocio_id = n.id
        join clientes cl on cl.id = c.cliente_id
        join servicios s on s.id = c.servicio_id
        join empleados e on e.id = c.empleado_id
       where su.recordatorios_auto
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
       order by c.fecha, c.hora_inicio
       limit greatest(least(p_limite, 500), 1)
    ) x;
$$;

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
    select whatsapp_enviados_mes(v_negocio) >= s.whatsapp_cupo into v_extra
      from suscripciones s
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
  v_su suscripciones;
  v_enviados integer;
  v_extra integer;
begin
  if p_negocio is distinct from auth_negocio_id() or not auth_es_owner() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select * into v_su from suscripciones where negocio_id = p_negocio;
  v_enviados := whatsapp_enviados_mes(p_negocio);
  v_extra := greatest(v_enviados - coalesce(v_su.whatsapp_cupo, 0), 0);

  return jsonb_build_object(
    'activo', coalesce(v_su.recordatorios_auto, false),
    'enviados', v_enviados,
    'cupo', coalesce(v_su.whatsapp_cupo, 0),
    'extra', v_extra,
    'precio_mensual', coalesce(v_su.whatsapp_precio_mensual, 0),
    'precio_extra', coalesce(v_su.whatsapp_precio_extra, 0),
    'monto_extra', v_extra * coalesce(v_su.whatsapp_precio_extra, 0)
  );
end;
$$;

-- -------------------------------------------------------------------------
-- Administrador: activar o quitar el servicio a un negocio
-- -------------------------------------------------------------------------
create or replace function admin_recordatorios(
  p_negocio uuid,
  p_activo boolean,
  p_cupo integer default 0,
  p_precio_mensual numeric default 0,
  p_precio_extra numeric default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not es_admin_plataforma() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if coalesce(p_cupo, -1) < 0 or coalesce(p_precio_mensual, -1) < 0
     or coalesce(p_precio_extra, -1) < 0 then
    raise exception 'El cupo y los precios deben ser 0 o más.' using errcode = 'P0001';
  end if;

  update suscripciones
     set recordatorios_auto = p_activo,
         whatsapp_cupo = p_cupo,
         whatsapp_precio_mensual = p_precio_mensual,
         whatsapp_precio_extra = p_precio_extra
   where negocio_id = p_negocio;
  if not found then
    raise exception 'Negocio sin suscripción.' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function admin_recordatorios(uuid, boolean, integer, numeric, numeric)
  from public, anon;
grant execute on function admin_recordatorios(uuid, boolean, integer, numeric, numeric)
  to authenticated;

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
             'recordatorios_auto', coalesce(s.recordatorios_auto, false),
             'whatsapp_cupo', coalesce(s.whatsapp_cupo, 0),
             'whatsapp_precio_mensual', coalesce(s.whatsapp_precio_mensual, 0),
             'whatsapp_precio_extra', coalesce(s.whatsapp_precio_extra, 0),
             'whatsapp_mes', whatsapp_enviados_mes(n.id),
             'whatsapp_extra', greatest(whatsapp_enviados_mes(n.id)
                                        - coalesce(s.whatsapp_cupo, 0), 0)
           ) order by n.created_at desc)
      from negocios n
      left join suscripciones s on s.negocio_id = n.id
  ), '[]'::jsonb);
end;
$$;

-- El dueño ya no lo enciende y los planes no lo incluyen.
alter table negocios drop column if exists recordatorio_whatsapp;
alter table planes
  drop column if exists whatsapp_cupo,
  drop column if exists whatsapp_precio_extra;
