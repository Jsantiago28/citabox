-- =========================================================================
-- Barbería PRO — Correcciones de seguridad (revisión del 28-oct-2026)
-- Requiere haber aplicado 001–008 sobre la misma base.
-- =========================================================================
--
-- 1. Reservas públicas: tope por negocio, clientes desactivados no reservan,
--    el visitante ya no puede cambiar el correo de una ficha existente y las
--    reservas con apartado sin reportar vencen solas.
-- 2. Perfiles: el dueño ya no puede crear perfiles a mano ni cambiar el id
--    de un perfil (permitía apropiarse de cuentas ajenas).
-- 3. Barberos (EMPLOYEE): solo operan sus propias citas, no cambian precios
--    salvo al cobrar, y no registran ni validan apartados.
-- 4. Cancelar una cita cancela su apartado pendiente.
-- 5. La zona horaria del negocio debe ser válida.
-- =========================================================================

-- -------------------------------------------------------------------------
-- Origen de la cita
-- -------------------------------------------------------------------------

alter table citas
  add column origen text not null default 'INTERNA',
  add constraint citas_origen_valido check (origen in ('INTERNA', 'PUBLICA'));

create index idx_citas_negocio_origen_creada on citas (negocio_id, origen, created_at);

-- -------------------------------------------------------------------------
-- 1. reserva_crear con los límites nuevos (misma firma y permisos que 007)
-- -------------------------------------------------------------------------

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

  -- Tope por negocio: frena scripts que llenan la agenda con teléfonos inventados.
  perform pg_advisory_xact_lock(hashtextextended('reserva-neg:' || v_neg.id::text, 0));
  if (select count(*) from citas c
       where c.negocio_id = v_neg.id
         and c.origen = 'PUBLICA'
         and c.estado = 'PENDIENTE'
         and c.created_at > now() - interval '1 hour') >= 30 then
    raise exception 'Hay demasiadas reservas en este momento. Intenta más tarde o comunícate con el negocio.'
      using errcode = 'P0001';
  end if;

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
    raise exception 'Ya hay varias citas próximas con este teléfono. Comunícate con el negocio.'
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

  -- Un cliente desactivado por el negocio no puede reservar en línea.
  if v_cliente_id is not null
     and not (select cl.activo from clientes cl where cl.id = v_cliente_id) then
    raise exception 'No es posible reservar en línea. Comunícate con el negocio.'
      using errcode = 'P0001';
  end if;

  if v_cliente_id is null then
    insert into clientes (negocio_id, nombre, telefono, email)
    values (v_neg.id, v_nombre, v_telefono, v_email)
    returning id into v_cliente_id;
  end if;

  v_hora_fin := p_hora_inicio + make_interval(mins => v_srv.duracion_minutos);

  begin
    insert into citas (negocio_id, cliente_id, empleado_id, servicio_id,
                       fecha, hora_inicio, hora_fin, precio, estado, notas, origen)
    values (v_neg.id, v_cliente_id, v_empleado_id, v_srv.id,
            p_fecha, p_hora_inicio, v_hora_fin, v_srv.precio, 'PENDIENTE', v_notas, 'PUBLICA')
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

-- Vence las reservas públicas cuyo apartado no se reportó en 3 horas.
create or replace function vencer_reservas_sin_pago()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
begin
  with vencidas as (
    update citas c
       set estado = 'CANCELADA',
           notas = concat_ws(E'\n', nullif(c.notas, ''),
                             'Cancelada automáticamente: no se reportó el pago del apartado a tiempo.')
      from apartados a
     where a.cita_id = c.id
       and a.negocio_id = c.negocio_id
       and a.estado = 'PENDIENTE'
       and a.referencia is null
       and c.origen = 'PUBLICA'
       and c.estado = 'PENDIENTE'
       and c.created_at < now() - interval '3 hours'
    returning c.id
  )
  select count(*) into v_total from vencidas;

  return v_total;
end;
$$;

revoke all on function vencer_reservas_sin_pago() from public, anon, authenticated;

-- Se programa cada 15 minutos si pg_cron está disponible (en Supabase lo está).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('barberia-vencer-reservas', '*/15 * * * *',
                          'select public.vencer_reservas_sin_pago()');
  else
    raise notice 'pg_cron no está disponible: vencer_reservas_sin_pago() no quedó programada.';
  end if;
exception when others then
  raise notice 'No se pudo programar vencer_reservas_sin_pago(): %', sqlerrm;
end;
$$;

-- -------------------------------------------------------------------------
-- 2. Perfiles: sin altas manuales y sin cambio de id
-- -------------------------------------------------------------------------
-- Los perfiles solo se crean con bootstrap_negocio_owner (dueño) o con la
-- Edge Function invitar-barbero (service_role).

drop policy perfiles_insert_owner on perfiles;

create or replace function perfiles_proteger_columnas()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  if new.id is distinct from old.id then
    raise exception 'No se puede cambiar el id de un perfil.'
      using errcode = '42501';
  end if;

  if new.negocio_id is distinct from old.negocio_id then
    raise exception 'No se puede cambiar el negocio de un perfil.'
      using errcode = '42501';
  end if;

  if new.rol is distinct from old.rol or new.activo is distinct from old.activo then
    if not auth_es_owner() then
      raise exception 'Solo el dueño del negocio puede cambiar el rol o el estado de un perfil.'
        using errcode = '42501';
    end if;

    if old.id = auth.uid() then
      raise exception 'No puedes cambiar tu propio rol ni desactivar tu propia cuenta.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

-- -------------------------------------------------------------------------
-- 3. Límites del barbero (EMPLOYEE)
-- -------------------------------------------------------------------------
-- Solo se aplica a miembros del negocio que no son dueños. Las funciones de
-- reserva pública (visitantes) y el servidor no se ven afectados.

create or replace function citas_limitar_empleado()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_empleado_id uuid;
begin
  if auth.uid() is null
     or auth_negocio_id() is distinct from new.negocio_id
     or auth_es_owner() then
    return new;
  end if;

  select e.id into v_empleado_id
    from empleados e
   where e.perfil_id = auth.uid()
     and e.negocio_id = new.negocio_id;

  if tg_op = 'INSERT' then
    if new.empleado_id is distinct from v_empleado_id then
      raise exception 'Solo puedes crear citas en tu propia agenda.' using errcode = '42501';
    end if;
    return new;
  end if;

  if old.empleado_id is distinct from v_empleado_id
     or new.empleado_id is distinct from old.empleado_id then
    raise exception 'Solo puedes modificar tus propias citas.' using errcode = '42501';
  end if;

  if new.precio is distinct from old.precio
     and not (new.estado = 'COMPLETADA' and old.estado <> 'COMPLETADA') then
    raise exception 'Solo el dueño puede cambiar el precio de una cita.' using errcode = '42501';
  end if;

  if new.token_publico is distinct from old.token_publico
     or new.origen is distinct from old.origen then
    raise exception 'No se puede cambiar este dato de la cita.' using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger trg_citas_limitar_empleado
  before insert or update on citas
  for each row execute function citas_limitar_empleado();

-- Solo el dueño registra y valida apartados (el barbero los ve).
alter policy apartados_insert_mismo_negocio on apartados
  with check (negocio_id = auth_negocio_id() and auth_es_owner());

alter policy apartados_update_mismo_negocio on apartados
  using (negocio_id = auth_negocio_id() and auth_es_owner())
  with check (negocio_id = auth_negocio_id() and auth_es_owner());

-- -------------------------------------------------------------------------
-- 4. Cancelar una cita cancela su apartado pendiente
-- -------------------------------------------------------------------------
-- Un apartado PAGADO queda igual: la devolución la decide el dueño.

create or replace function citas_cancelar_apartado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estado = 'CANCELADA' and old.estado is distinct from 'CANCELADA' then
    update apartados
       set estado = 'CANCELADO'
     where cita_id = new.id
       and negocio_id = new.negocio_id
       and estado = 'PENDIENTE';
  end if;
  return new;
end;
$$;

revoke all on function citas_cancelar_apartado() from public, anon, authenticated;

create trigger trg_citas_cancelar_apartado
  after update of estado on citas
  for each row execute function citas_cancelar_apartado();

-- -------------------------------------------------------------------------
-- 5. Zona horaria válida
-- -------------------------------------------------------------------------

create or replace function negocios_validar_zona_horaria()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (tg_op = 'INSERT' or new.zona_horaria is distinct from old.zona_horaria)
     and not exists (select 1 from pg_timezone_names where name = new.zona_horaria) then
    raise exception 'La zona horaria "%" no es válida.', new.zona_horaria
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger trg_negocios_validar_zona_horaria
  before insert or update of zona_horaria on negocios
  for each row execute function negocios_validar_zona_horaria();
