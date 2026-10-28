-- =========================================================================
-- Barbería PRO — Reserva pública (visitantes sin cuenta)
-- Requiere haber aplicado 001–006 sobre la misma base.
-- =========================================================================
--
-- QUÉ AGREGA
--
-- 1. citas.token_publico: enlace secreto de "Mi cita" (sin cuenta).
-- 2. Índice para buscar clientes por teléfono (solo dígitos).
-- 3. Funciones internas (reserva_priv_*): NO se conceden a anon ni a
--    authenticated. Contienen las reglas de disponibilidad, una sola vez.
-- 4. Funciones públicas (RPC) para anon y authenticated:
--      reserva_catalogo, reserva_horas_disponibles, reserva_crear,
--      reserva_consultar, reserva_cancelar, reserva_reprogramar,
--      reserva_reportar_pago.
--
-- SEGURIDAD
--
-- - No se abre ninguna política RLS pública: anon sigue sin leer ninguna
--   tabla. Todo pasa por estas funciones SECURITY DEFINER, que validan
--   cada dato en el servidor y devuelven solo lo necesario.
-- - Nunca se devuelven teléfonos de barberos, perfiles ni datos de
--   clientes. "Mi cita" se identifica solo con el token (uuid aleatorio).
-- - "Hoy" y "ahora" se calculan con negocios.zona_horaria.
--
-- ERRORES (para mostrar al cliente tal cual)
--
-- - P0001: regla de negocio (dato inválido, fuera de plazo, etc.).
-- - 23P01: la hora elegida no está disponible (ocupada, ya pasó o fuera
--   de horario). La app debe recargar las horas.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Token público de la cita
-- -------------------------------------------------------------------------

alter table citas
  add column token_publico uuid not null default gen_random_uuid();

alter table citas
  add constraint citas_token_publico_key unique (token_publico);

-- -------------------------------------------------------------------------
-- 2. Búsqueda de clientes por teléfono normalizado (solo dígitos)
-- -------------------------------------------------------------------------

create index idx_clientes_negocio_telefono_digitos
  on clientes (negocio_id, (regexp_replace(telefono, '\D', '', 'g')));

-- =========================================================================
-- FUNCIONES INTERNAS (no expuestas a anon / authenticated)
-- =========================================================================

-- Fecha y hora actuales en la zona horaria del negocio.
create or replace function reserva_priv_ahora(p_zona text)
returns timestamp
language sql
stable
set search_path = public
as $$
  select now() at time zone p_zona;
$$;

-- Negocio ACTIVO por slug, o error.
create or replace function reserva_priv_negocio(p_slug text)
returns negocios
language plpgsql
stable
set search_path = public
as $$
declare
  v_neg negocios;
begin
  select * into v_neg
    from negocios n
   where n.slug = lower(btrim(coalesce(p_slug, '')))
     and n.estado = 'ACTIVO';

  if not found then
    raise exception 'No encontramos esta barbería. Revisa el enlace.'
      using errcode = 'P0001';
  end if;

  return v_neg;
end;
$$;

-- Servicio ACTIVO del negocio, o error.
create or replace function reserva_priv_servicio(p_negocio_id uuid, p_servicio_id uuid)
returns servicios
language plpgsql
stable
set search_path = public
as $$
declare
  v_srv servicios;
begin
  select * into v_srv
    from servicios s
   where s.id = p_servicio_id
     and s.negocio_id = p_negocio_id
     and s.activo;

  if not found then
    raise exception 'Este servicio no está disponible.'
      using errcode = 'P0001';
  end if;

  return v_srv;
end;
$$;

-- Barbero activo del negocio que realiza el servicio, o error.
create or replace function reserva_priv_validar_empleado(
  p_negocio_id uuid,
  p_empleado_id uuid,
  p_servicio_id uuid
)
returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if not exists (
    select 1 from empleados e
     where e.id = p_empleado_id
       and e.negocio_id = p_negocio_id
       and e.activo
  ) then
    raise exception 'Este barbero no está disponible.'
      using errcode = 'P0001';
  end if;

  if exists (select 1 from empleado_servicios es where es.empleado_id = p_empleado_id)
     and not exists (
       select 1 from empleado_servicios es
        where es.empleado_id = p_empleado_id
          and es.servicio_id = p_servicio_id
     ) then
    raise exception 'Este barbero no realiza este servicio.'
      using errcode = 'P0001';
  end if;
end;
$$;

-- Fecha entre hoy y hoy + 60 días (zona horaria del negocio), o error.
create or replace function reserva_priv_validar_fecha(p_zona text, p_fecha date)
returns void
language plpgsql
stable
set search_path = public
as $$
declare
  v_hoy date := reserva_priv_ahora(p_zona)::date;
begin
  if p_fecha is null then
    raise exception 'Elige una fecha.' using errcode = 'P0001';
  end if;

  if p_fecha < v_hoy then
    raise exception 'Esa fecha ya pasó. Elige otra.' using errcode = 'P0001';
  end if;

  if p_fecha > v_hoy + 60 then
    raise exception 'Solo se puede reservar hasta 60 días por adelantado.'
      using errcode = 'P0001';
  end if;
end;
$$;

-- Horas libres de un día. ÚNICA fuente de las reglas de disponibilidad;
-- la usan reserva_horas_disponibles, reserva_crear y reserva_reprogramar.
--
-- Reglas:
--   - Negocio ACTIVO, servicio ACTIVO del negocio.
--   - Horario del negocio ese día de la semana (sin fila = cerrado).
--   - Horario del barbero ese día (si no tiene filas, el del negocio; si
--     tiene filas pero no ese día, no trabaja), recortado al del negocio.
--   - Barbero activo, sin bloqueo que cubra la fecha, que haga el servicio
--     (sin filas en empleado_servicios = todos).
--   - Inicios cada intervalo_reserva_minutos desde que empieza a trabajar;
--     inicio + duración debe caber antes del cierre (y antes de medianoche).
--   - Sin cruce con citas activas (no CANCELADA / NO_VINO), excepto
--     p_excluir_cita_id (la propia cita al reprogramar).
--   - Solo horas futuras según la zona horaria del negocio.
-- "carga" = citas activas del barbero ese día (para repartir el trabajo).
create or replace function reserva_priv_horarios_libres(
  p_negocio_id uuid,
  p_servicio_id uuid,
  p_fecha date,
  p_empleado_id uuid default null,
  p_excluir_cita_id uuid default null
)
returns table (hora_inicio time, empleado_id uuid, carga bigint)
language sql
stable
set search_path = public
as $$
  with neg as (
    select n.id,
           n.intervalo_reserva_minutos as paso,
           reserva_priv_ahora(n.zona_horaria) as ahora
      from negocios n
     where n.id = p_negocio_id
       and n.estado = 'ACTIVO'
  ),
  srv as (
    select s.duracion_minutos as duracion
      from servicios s
     where s.id = p_servicio_id
       and s.negocio_id = p_negocio_id
       and s.activo
  ),
  hn as (
    select h.hora_apertura, h.hora_cierre
      from horarios_negocio h
     where h.negocio_id = p_negocio_id
       and h.dia_semana = extract(dow from p_fecha)::int
  ),
  emp as (
    select e.id,
           greatest(hn.hora_apertura, coalesce(he.hora_inicio, hn.hora_apertura)) as desde,
           least(hn.hora_cierre, coalesce(he.hora_fin, hn.hora_cierre)) as hasta
      from empleados e
     cross join hn
      left join horarios_empleado he
        on he.empleado_id = e.id
       and he.dia_semana = extract(dow from p_fecha)::int
     where e.negocio_id = p_negocio_id
       and e.activo
       and (p_empleado_id is null or e.id = p_empleado_id)
       and (
         he.id is not null
         or not exists (select 1 from horarios_empleado x where x.empleado_id = e.id)
       )
       and not exists (
         select 1 from bloqueos_empleado b
          where b.empleado_id = e.id
            and p_fecha between b.fecha_inicio and b.fecha_fin
       )
       and (
         not exists (select 1 from empleado_servicios es where es.empleado_id = e.id)
         or exists (
           select 1 from empleado_servicios es
            where es.empleado_id = e.id
              and es.servicio_id = p_servicio_id
         )
       )
  ),
  candidatos as (
    select emp.id as emp_id,
           t.inicio,
           t.inicio + make_interval(mins => srv.duracion) as fin
      from emp
     cross join neg
     cross join srv
     cross join lateral generate_series(
       p_fecha + emp.desde,
       p_fecha + emp.hasta - make_interval(mins => srv.duracion),
       make_interval(mins => neg.paso)
     ) as t(inicio)
     where t.inicio > neg.ahora
       and t.inicio + make_interval(mins => srv.duracion) < (p_fecha + 1)::timestamp
  )
  select c.inicio::time,
         c.emp_id,
         (select count(*)
            from citas x
           where x.empleado_id = c.emp_id
             and x.fecha = p_fecha
             and x.estado not in ('CANCELADA', 'NO_VINO'))
    from candidatos c
   where not exists (
     select 1
       from citas ci
      where ci.empleado_id = c.emp_id
        and ci.fecha = p_fecha
        and ci.estado not in ('CANCELADA', 'NO_VINO')
        and (p_excluir_cita_id is null or ci.id <> p_excluir_cita_id)
        and ci.fecha + ci.hora_inicio < c.fin
        and c.inicio < ci.fecha + ci.hora_fin
   );
$$;

-- ¿Se puede cancelar / reprogramar? Estado PENDIENTE o CONFIRMADA y
-- faltan al menos p_horas horas para el inicio.
create or replace function reserva_priv_puede_cambiar(
  p_estado estado_cita,
  p_fecha date,
  p_hora time,
  p_zona text,
  p_horas integer
)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_estado in ('PENDIENTE', 'CONFIRMADA')
     and p_fecha + p_hora >= reserva_priv_ahora(p_zona) + make_interval(hours => p_horas);
$$;

-- Datos de "Mi cita" (sin datos del cliente).
create or replace function reserva_priv_cita_json(p_cita_id uuid)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_cita citas;
  v_neg negocios;
  v_srv servicios;
  v_emp empleados;
  v_apa apartados;
  v_puede boolean;
begin
  select * into v_cita from citas c where c.id = p_cita_id;
  if not found then
    raise exception 'No encontramos esta cita. Revisa el enlace.'
      using errcode = 'P0001';
  end if;

  select * into v_neg from negocios n where n.id = v_cita.negocio_id;
  select * into v_srv from servicios s where s.id = v_cita.servicio_id;
  select * into v_emp from empleados e where e.id = v_cita.empleado_id;
  select * into v_apa
    from apartados a
   where a.cita_id = v_cita.id
   order by (a.estado <> 'CANCELADO') desc, a.created_at desc
   limit 1;

  v_puede := reserva_priv_puede_cambiar(
    v_cita.estado, v_cita.fecha, v_cita.hora_inicio,
    v_neg.zona_horaria, v_neg.cancelacion_horas_minimas
  );

  return jsonb_build_object(
    'cita_id', v_cita.id,
    'token_publico', v_cita.token_publico,
    'estado', v_cita.estado,
    'fecha', v_cita.fecha,
    'hora_inicio', left(v_cita.hora_inicio::text, 5),
    'hora_fin', left(v_cita.hora_fin::text, 5),
    'precio', v_cita.precio,
    'servicio', jsonb_build_object(
      'id', v_srv.id,
      'nombre', v_srv.nombre,
      'duracion_minutos', v_srv.duracion_minutos
    ),
    'barbero', jsonb_build_object(
      'id', v_emp.id,
      'nombre', v_emp.nombre,
      'foto', v_emp.foto
    ),
    'negocio', jsonb_build_object(
      'nombre', v_neg.nombre,
      'slug', v_neg.slug,
      'telefono', v_neg.telefono,
      'direccion', v_neg.direccion,
      'logo', v_neg.logo,
      'color_principal', v_neg.color_principal,
      'moneda', v_neg.moneda,
      'zona_horaria', v_neg.zona_horaria,
      'cancelacion_horas_minimas', v_neg.cancelacion_horas_minimas
    ),
    'apartado', case
      when v_apa.id is null then null
      else jsonb_build_object(
        'estado', v_apa.estado,
        'monto', v_apa.monto,
        'metodo_pago', v_apa.metodo_pago,
        'referencia', v_apa.referencia,
        'instrucciones', v_neg.apartado_instrucciones,
        'politica', v_neg.apartado_politica
      )
    end,
    'limite_cambios', (v_cita.fecha + v_cita.hora_inicio)
                      - make_interval(hours => v_neg.cancelacion_horas_minimas),
    'puede_cancelar', v_puede,
    'puede_reprogramar', v_puede and v_neg.estado = 'ACTIVO'
  );
end;
$$;

revoke all on function reserva_priv_ahora(text) from public, anon, authenticated;
revoke all on function reserva_priv_negocio(text) from public, anon, authenticated;
revoke all on function reserva_priv_servicio(uuid, uuid) from public, anon, authenticated;
revoke all on function reserva_priv_validar_empleado(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function reserva_priv_validar_fecha(text, date) from public, anon, authenticated;
revoke all on function reserva_priv_horarios_libres(uuid, uuid, date, uuid, uuid) from public, anon, authenticated;
revoke all on function reserva_priv_puede_cambiar(estado_cita, date, time, text, integer) from public, anon, authenticated;
revoke all on function reserva_priv_cita_json(uuid) from public, anon, authenticated;

-- =========================================================================
-- FUNCIONES PÚBLICAS (anon y authenticated)
-- =========================================================================

-- -------------------------------------------------------------------------
-- Catálogo del negocio
-- -------------------------------------------------------------------------
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
               'duracion_minutos', s.duracion_minutos
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
-- Horas disponibles de un día
-- -------------------------------------------------------------------------
create or replace function reserva_horas_disponibles(
  p_slug text,
  p_servicio_id uuid,
  p_fecha date,
  p_empleado_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_neg negocios;
  v_srv servicios;
  v_res jsonb;
begin
  v_neg := reserva_priv_negocio(p_slug);
  v_srv := reserva_priv_servicio(v_neg.id, p_servicio_id);
  perform reserva_priv_validar_fecha(v_neg.zona_horaria, p_fecha);

  if p_empleado_id is not null then
    perform reserva_priv_validar_empleado(v_neg.id, p_empleado_id, v_srv.id);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'hora_inicio', left(x.hora_inicio::text, 5),
           'empleado_id', x.empleado_id
         ) order by x.hora_inicio), '[]'::jsonb)
    into v_res
    from (
      select distinct on (l.hora_inicio) l.hora_inicio, l.empleado_id
        from reserva_priv_horarios_libres(v_neg.id, v_srv.id, p_fecha, p_empleado_id, null) l
       order by l.hora_inicio, l.carga, l.empleado_id
    ) x;

  return v_res;
end;
$$;

-- -------------------------------------------------------------------------
-- Crear la reserva
-- -------------------------------------------------------------------------
create or replace function reserva_crear(
  p_slug text,
  p_servicio_id uuid,
  p_empleado_id uuid,
  p_fecha date,
  p_hora_inicio time,
  p_cliente_nombre text,
  p_cliente_telefono text,
  p_cliente_email text default null,
  p_notas text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_neg negocios;
  v_srv servicios;
  v_nombre text := btrim(coalesce(p_cliente_nombre, ''));
  v_telefono text := btrim(coalesce(p_cliente_telefono, ''));
  v_tel text := regexp_replace(coalesce(p_cliente_telefono, ''), '\D', '', 'g');
  v_email text := lower(nullif(btrim(coalesce(p_cliente_email, '')), ''));
  v_notas text := nullif(btrim(coalesce(p_notas, '')), '');
  v_activas integer;
  v_empleado_id uuid;
  v_cliente_id uuid;
  v_hora_fin time;
  v_cita_id uuid;
  v_token uuid;
  v_con_apartado boolean;
begin
  v_neg := reserva_priv_negocio(p_slug);
  v_srv := reserva_priv_servicio(v_neg.id, p_servicio_id);
  perform reserva_priv_validar_fecha(v_neg.zona_horaria, p_fecha);

  if p_hora_inicio is null then
    raise exception 'Elige una hora.' using errcode = 'P0001';
  end if;

  if p_empleado_id is not null then
    perform reserva_priv_validar_empleado(v_neg.id, p_empleado_id, v_srv.id);
  end if;

  -- Datos del cliente
  if char_length(v_nombre) < 2 or char_length(v_nombre) > 80 then
    raise exception 'Escribe tu nombre (entre 2 y 80 caracteres).' using errcode = 'P0001';
  end if;

  if char_length(v_tel) < 7 or char_length(v_tel) > 15 then
    raise exception 'Escribe un teléfono válido (al menos 7 dígitos).' using errcode = 'P0001';
  end if;

  if v_email is not null
     and (char_length(v_email) > 254
          or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then
    raise exception 'El correo electrónico no es válido.' using errcode = 'P0001';
  end if;

  if v_notas is not null and char_length(v_notas) > 500 then
    raise exception 'La nota es muy larga (máximo 500 caracteres).' using errcode = 'P0001';
  end if;

  -- Serializa las reservas del mismo teléfono en el mismo negocio (límite
  -- de citas y alta del cliente sin duplicados).
  perform pg_advisory_xact_lock(hashtextextended('reserva:' || v_neg.id::text || ':' || v_tel, 0));

  -- Límite de abuso: máximo 3 citas futuras activas por teléfono.
  select count(*) into v_activas
    from citas c
    join clientes cl on cl.id = c.cliente_id
   where c.negocio_id = v_neg.id
     and cl.negocio_id = v_neg.id
     and regexp_replace(cl.telefono, '\D', '', 'g') = v_tel
     and c.estado in ('PENDIENTE', 'CONFIRMADA')
     and c.fecha + c.hora_inicio > reserva_priv_ahora(v_neg.zona_horaria);

  if v_activas >= 3 then
    raise exception 'Ya tienes 3 citas próximas con este teléfono. Cancela una o comunícate con el negocio.'
      using errcode = 'P0001';
  end if;

  -- Disponibilidad (mismas reglas que reserva_horas_disponibles).
  select l.empleado_id into v_empleado_id
    from reserva_priv_horarios_libres(v_neg.id, v_srv.id, p_fecha, p_empleado_id, null) l
   where l.hora_inicio = p_hora_inicio
   order by l.carga, l.empleado_id
   limit 1;

  if v_empleado_id is null then
    raise exception 'Esa hora ya no está disponible. Elige otra.' using errcode = '23P01';
  end if;

  -- Cliente: se reutiliza el del mismo teléfono en este negocio.
  select cl.id into v_cliente_id
    from clientes cl
   where cl.negocio_id = v_neg.id
     and regexp_replace(cl.telefono, '\D', '', 'g') = v_tel
   order by cl.activo desc, cl.created_at
   limit 1;

  if v_cliente_id is null then
    insert into clientes (negocio_id, nombre, telefono, email)
    values (v_neg.id, v_nombre, v_telefono, v_email)
    returning id into v_cliente_id;
  elsif v_email is not null then
    update clientes cl
       set email = v_email
     where cl.id = v_cliente_id
       and cl.email is null;
  end if;

  v_hora_fin := p_hora_inicio + make_interval(mins => v_srv.duracion_minutos);

  begin
    insert into citas (negocio_id, cliente_id, empleado_id, servicio_id,
                       fecha, hora_inicio, hora_fin, precio, estado, notas)
    values (v_neg.id, v_cliente_id, v_empleado_id, v_srv.id,
            p_fecha, p_hora_inicio, v_hora_fin, v_srv.precio, 'PENDIENTE', v_notas)
    returning id, token_publico into v_cita_id, v_token;
  exception when exclusion_violation then
    raise exception 'Esa hora acaba de ser reservada por otra persona. Elige otra.'
      using errcode = '23P01';
  end;

  v_con_apartado := v_neg.apartado_requerido and v_neg.apartado_monto > 0;

  if v_con_apartado then
    insert into apartados (negocio_id, cita_id, monto, estado)
    values (v_neg.id, v_cita_id, v_neg.apartado_monto, 'PENDIENTE');
  end if;

  return jsonb_build_object(
    'cita_id', v_cita_id,
    'token_publico', v_token,
    'estado', 'PENDIENTE',
    'empleado_id', v_empleado_id,
    'fecha', p_fecha,
    'hora_inicio', left(p_hora_inicio::text, 5),
    'hora_fin', left(v_hora_fin::text, 5),
    'precio', v_srv.precio,
    'apartado', case
      when v_con_apartado then jsonb_build_object(
        'monto', v_neg.apartado_monto,
        'instrucciones', v_neg.apartado_instrucciones,
        'politica', v_neg.apartado_politica
      )
      else null
    end
  );
end;
$$;

-- -------------------------------------------------------------------------
-- Consultar "Mi cita"
-- -------------------------------------------------------------------------
create or replace function reserva_consultar(p_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cita_id uuid;
begin
  select c.id into v_cita_id from citas c where c.token_publico = p_token;

  if v_cita_id is null then
    raise exception 'No encontramos esta cita. Revisa el enlace.' using errcode = 'P0001';
  end if;

  return reserva_priv_cita_json(v_cita_id);
end;
$$;

-- -------------------------------------------------------------------------
-- Cancelar
-- -------------------------------------------------------------------------
create or replace function reserva_cancelar(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cita citas;
  v_neg negocios;
begin
  select * into v_cita from citas c where c.token_publico = p_token for update;

  if not found then
    raise exception 'No encontramos esta cita. Revisa el enlace.' using errcode = 'P0001';
  end if;

  select * into v_neg from negocios n where n.id = v_cita.negocio_id;

  if v_cita.estado not in ('PENDIENTE', 'CONFIRMADA') then
    raise exception 'Esta cita ya no se puede cancelar.' using errcode = 'P0001';
  end if;

  if not reserva_priv_puede_cambiar(v_cita.estado, v_cita.fecha, v_cita.hora_inicio,
                                    v_neg.zona_horaria, v_neg.cancelacion_horas_minimas) then
    raise exception 'Solo puedes cancelar con al menos % horas de anticipación. Comunícate con el negocio.',
      v_neg.cancelacion_horas_minimas
      using errcode = 'P0001';
  end if;

  update citas c set estado = 'CANCELADA' where c.id = v_cita.id;

  -- Un apartado PAGADO se queda como está: la devolución la decide el dueño.
  update apartados a
     set estado = 'CANCELADO'
   where a.cita_id = v_cita.id
     and a.estado = 'PENDIENTE';

  return reserva_priv_cita_json(v_cita.id);
end;
$$;

-- -------------------------------------------------------------------------
-- Reprogramar (mismo servicio y barbero)
-- -------------------------------------------------------------------------
create or replace function reserva_reprogramar(p_token uuid, p_fecha date, p_hora_inicio time)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cita citas;
  v_neg negocios;
  v_srv servicios;
begin
  select * into v_cita from citas c where c.token_publico = p_token for update;

  if not found then
    raise exception 'No encontramos esta cita. Revisa el enlace.' using errcode = 'P0001';
  end if;

  select * into v_neg from negocios n where n.id = v_cita.negocio_id;

  if v_cita.estado not in ('PENDIENTE', 'CONFIRMADA') then
    raise exception 'Esta cita ya no se puede reprogramar.' using errcode = 'P0001';
  end if;

  if not reserva_priv_puede_cambiar(v_cita.estado, v_cita.fecha, v_cita.hora_inicio,
                                    v_neg.zona_horaria, v_neg.cancelacion_horas_minimas) then
    raise exception 'Solo puedes reprogramar con al menos % horas de anticipación. Comunícate con el negocio.',
      v_neg.cancelacion_horas_minimas
      using errcode = 'P0001';
  end if;

  if v_neg.estado <> 'ACTIVO' then
    raise exception 'Este negocio no está recibiendo reservas. Comunícate con el negocio.'
      using errcode = 'P0001';
  end if;

  select * into v_srv
    from servicios s
   where s.id = v_cita.servicio_id
     and s.activo;

  if not found then
    raise exception 'El servicio de esta cita ya no está disponible. Comunícate con el negocio.'
      using errcode = 'P0001';
  end if;

  perform reserva_priv_validar_fecha(v_neg.zona_horaria, p_fecha);

  if p_hora_inicio is null then
    raise exception 'Elige una hora.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
      from reserva_priv_horarios_libres(v_neg.id, v_srv.id, p_fecha, v_cita.empleado_id, v_cita.id) l
     where l.hora_inicio = p_hora_inicio
  ) then
    raise exception 'Esa hora no está disponible. Elige otra.' using errcode = '23P01';
  end if;

  begin
    update citas c
       set fecha = p_fecha,
           hora_inicio = p_hora_inicio,
           hora_fin = p_hora_inicio + make_interval(mins => v_srv.duracion_minutos)
     where c.id = v_cita.id;
  exception when exclusion_violation then
    raise exception 'Esa hora acaba de ser reservada por otra persona. Elige otra.'
      using errcode = '23P01';
  end;

  return reserva_priv_cita_json(v_cita.id);
end;
$$;

-- -------------------------------------------------------------------------
-- Informar el pago del apartado (transferencia)
-- -------------------------------------------------------------------------
-- Solo guarda la referencia; el dueño verifica y marca PAGADO.
create or replace function reserva_reportar_pago(p_token uuid, p_referencia text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cita_id uuid;
  v_ref text := btrim(coalesce(p_referencia, ''));
begin
  if char_length(v_ref) < 3 or char_length(v_ref) > 100 then
    raise exception 'Escribe la referencia de tu transferencia (entre 3 y 100 caracteres).'
      using errcode = 'P0001';
  end if;

  select c.id into v_cita_id from citas c where c.token_publico = p_token for update;

  if v_cita_id is null then
    raise exception 'No encontramos esta cita. Revisa el enlace.' using errcode = 'P0001';
  end if;

  update apartados a
     set referencia = v_ref,
         metodo_pago = 'TRANSFERENCIA'
   where a.cita_id = v_cita_id
     and a.estado = 'PENDIENTE';

  if not found then
    raise exception 'Esta cita no tiene un apartado pendiente de pago.' using errcode = 'P0001';
  end if;

  return reserva_priv_cita_json(v_cita_id);
end;
$$;

-- -------------------------------------------------------------------------
-- Permisos de las funciones públicas
-- -------------------------------------------------------------------------
revoke all on function reserva_catalogo(text) from public;
revoke all on function reserva_horas_disponibles(text, uuid, date, uuid) from public;
revoke all on function reserva_crear(text, uuid, uuid, date, time, text, text, text, text) from public;
revoke all on function reserva_consultar(uuid) from public;
revoke all on function reserva_cancelar(uuid) from public;
revoke all on function reserva_reprogramar(uuid, date, time) from public;
revoke all on function reserva_reportar_pago(uuid, text) from public;

grant execute on function reserva_catalogo(text) to anon, authenticated;
grant execute on function reserva_horas_disponibles(text, uuid, date, uuid) to anon, authenticated;
grant execute on function reserva_crear(text, uuid, uuid, date, time, text, text, text, text) to anon, authenticated;
grant execute on function reserva_consultar(uuid) to anon, authenticated;
grant execute on function reserva_cancelar(uuid) to anon, authenticated;
grant execute on function reserva_reprogramar(uuid, date, time) to anon, authenticated;
grant execute on function reserva_reportar_pago(uuid, text) to anon, authenticated;
