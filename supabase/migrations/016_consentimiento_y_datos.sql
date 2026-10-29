-- =========================================================================
-- 016: consentimiento y derechos sobre los datos (Ley 172-13, RD)
--   * clientes.consentimiento_at: cuándo aceptó la política de privacidad.
--   * reserva_crear exige p_acepta_privacidad = true (misma lógica que 015).
--   * anonimizar_cliente: derecho de cancelación; solo el dueño.
-- =========================================================================

alter table clientes add column if not exists consentimiento_at timestamptz;

-- Cambia la firma: se elimina la anterior (9 parámetros).
drop function if exists reserva_crear(text, uuid, uuid, date, time, text, text, text, text);

create or replace function reserva_crear(
  p_slug text,
  p_servicio_id uuid,
  p_empleado_id uuid,
  p_fecha date,
  p_hora_inicio time,
  p_cliente_nombre text,
  p_cliente_telefono text,
  p_cliente_email text default null,
  p_notas text default null,
  p_acepta_privacidad boolean default false
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
  if p_acepta_privacidad is not true then
    raise exception 'Debes aceptar la política de privacidad para reservar.' using errcode = 'P0001';
  end if;

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
    raise exception 'No es posible reservar en línea. Comunícate con el negocio.'
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
    insert into clientes (negocio_id, nombre, telefono, email, consentimiento_at)
    values (v_neg.id, v_nombre, v_telefono, v_email, now())
    returning id into v_cliente_id;
  else
    update clientes set consentimiento_at = now() where id = v_cliente_id;
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

revoke all on function reserva_crear(text, uuid, uuid, date, time, text, text, text, text, boolean) from public;
grant execute on function reserva_crear(text, uuid, uuid, date, time, text, text, text, text, boolean) to anon, authenticated;

-- -------------------------------------------------------------------------
-- Derecho de cancelación: anonimizar un cliente (las citas se conservan).
-- -------------------------------------------------------------------------

create or replace function anonimizar_cliente(p_cliente_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not auth_es_owner() then
    raise exception 'Solo el dueño puede anonimizar clientes.' using errcode = '42501';
  end if;

  update clientes
     set nombre = 'Cliente anonimizado',
         telefono = null,
         email = null,
         notas = null,
         activo = false,
         consentimiento_at = null
   where id = p_cliente_id
     and negocio_id = auth_negocio_id();

  if not found then
    raise exception 'Cliente no encontrado.' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function anonimizar_cliente(uuid) from public, anon;
grant execute on function anonimizar_cliente(uuid) to authenticated;
