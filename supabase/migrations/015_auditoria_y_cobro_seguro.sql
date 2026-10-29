-- =========================================================================
-- Barbería PRO — Auditoría de seguridad del 29-oct-2026
-- Requiere haber aplicado 001–014 sobre la misma base.
-- =========================================================================
--
-- 1. Integridad del cobro: un barbero no puede deshacer una cita cobrada ni
--    cambiar precio, propina o método después de cobrar; tampoco crear citas
--    ya cobradas, con otro precio que el del servicio o como "públicas".
-- 2. Registro de auditoría: quién creó, cambió o borró citas, apartados,
--    clientes, servicios, empleados y perfiles. Solo el dueño lo lee y nadie
--    lo puede modificar.
-- 3. Reservas públicas: las que reportaron un pago pero el dueño no validó
--    en 24 horas también vencen; mensaje único para no revelar si un
--    teléfono tiene citas o está bloqueado.
-- 4. El barbero no puede activar/desactivar clientes; el dueño no puede
--    borrar su propio perfil.
-- 5. Logo y portada del negocio solo con https.
-- 6. Sin privilegios TRUNCATE/REFERENCES/TRIGGER para los roles de la API.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Integridad del cobro (reemplaza la función de 010)
-- -------------------------------------------------------------------------

create or replace function citas_limitar_empleado()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_empleado_id uuid;
  v_precio numeric;
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
    if new.estado = 'COMPLETADA' or new.origen <> 'INTERNA' then
      raise exception 'No se puede crear la cita así.' using errcode = '42501';
    end if;
    -- El precio inicial es siempre el del servicio; se ajusta al cobrar.
    select s.precio into v_precio
      from servicios s
     where s.id = new.servicio_id
       and s.negocio_id = new.negocio_id;
    new.precio := coalesce(v_precio, new.precio);
    new.propina := 0;
    new.metodo_pago := null;
    return new;
  end if;

  if old.empleado_id is distinct from v_empleado_id
     or new.empleado_id is distinct from old.empleado_id then
    raise exception 'Solo puedes modificar tus propias citas.' using errcode = '42501';
  end if;

  -- Una cita cobrada queda cerrada para el barbero.
  if old.estado = 'COMPLETADA'
     and (new.estado is distinct from old.estado
          or new.precio is distinct from old.precio
          or new.propina is distinct from old.propina
          or new.metodo_pago is distinct from old.metodo_pago) then
    raise exception 'Una cita cobrada solo la puede corregir el dueño.' using errcode = '42501';
  end if;

  -- Precio, propina y método solo cambian en el momento de cobrar.
  if (new.precio is distinct from old.precio
      or new.propina is distinct from old.propina
      or new.metodo_pago is distinct from old.metodo_pago)
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

-- -------------------------------------------------------------------------
-- 2. Registro de auditoría
-- -------------------------------------------------------------------------

create table auditoria (
  id bigint generated always as identity primary key,
  -- Sin FK: el registro debe sobrevivir aunque se borre la fila o el negocio.
  negocio_id uuid not null,
  tabla text not null,
  fila_id text not null,
  accion text not null check (accion in ('INSERT', 'UPDATE', 'DELETE')),
  antes jsonb,
  despues jsonb,
  usuario_id uuid,
  fecha timestamptz not null default now()
);

create index idx_auditoria_negocio_fecha on auditoria (negocio_id, fecha desc);

alter table auditoria enable row level security;

-- Solo el dueño la lee. No hay políticas de INSERT/UPDATE/DELETE: solo el
-- trigger (security definer) escribe, y nadie puede alterarla desde la API.
create policy auditoria_select_owner on auditoria
  for select using (negocio_id = auth_negocio_id() and auth_es_owner());

revoke insert, update, delete, truncate on auditoria from anon, authenticated;

create or replace function registrar_auditoria()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fila jsonb := to_jsonb(coalesce(new, old));
begin
  insert into auditoria (negocio_id, tabla, fila_id, accion, antes, despues, usuario_id)
  values (
    (v_fila->>'negocio_id')::uuid,
    tg_table_name,
    v_fila->>'id',
    tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end,
    auth.uid()
  );
  return null;
end;
$$;

revoke all on function registrar_auditoria() from public, anon, authenticated;

create trigger trg_auditoria_citas
  after insert or update or delete on citas
  for each row execute function registrar_auditoria();
create trigger trg_auditoria_apartados
  after insert or update or delete on apartados
  for each row execute function registrar_auditoria();
create trigger trg_auditoria_clientes
  after insert or update or delete on clientes
  for each row execute function registrar_auditoria();
create trigger trg_auditoria_servicios
  after insert or update or delete on servicios
  for each row execute function registrar_auditoria();
create trigger trg_auditoria_empleados
  after insert or update or delete on empleados
  for each row execute function registrar_auditoria();
create trigger trg_auditoria_perfiles
  after insert or update or delete on perfiles
  for each row execute function registrar_auditoria();

-- -------------------------------------------------------------------------
-- 3. Reservas públicas (reserva_crear: misma lógica que 010, mensaje único)
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

-- Vencen: sin pago reportado en 3 h (como en 010) y, además, con pago
-- reportado que el dueño no validó en 24 h (referencias inventadas).
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
                             'Cancelada automáticamente: el apartado no se pagó o no se validó a tiempo.')
      from apartados a
     where a.cita_id = c.id
       and a.negocio_id = c.negocio_id
       and a.estado = 'PENDIENTE'
       and c.origen = 'PUBLICA'
       and c.estado = 'PENDIENTE'
       and (
         (a.referencia is null and c.created_at < now() - interval '3 hours')
         or c.created_at < now() - interval '24 hours'
       )
    returning c.id
  )
  select count(*) into v_total from vencidas;

  return v_total;
end;
$$;

revoke all on function vencer_reservas_sin_pago() from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- 4. Clientes y perfiles
-- -------------------------------------------------------------------------

create or replace function clientes_proteger_activo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null
     and new.activo is distinct from old.activo
     and not auth_es_owner() then
    raise exception 'Solo el dueño puede activar o desactivar clientes.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger trg_clientes_proteger_activo
  before update of activo on clientes
  for each row execute function clientes_proteger_activo();

create or replace function perfiles_proteger_borrado()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null and (old.id = auth.uid() or old.rol = 'OWNER') then
    raise exception 'No se puede borrar este perfil.' using errcode = '42501';
  end if;
  return old;
end;
$$;

create trigger trg_perfiles_proteger_borrado
  before delete on perfiles
  for each row execute function perfiles_proteger_borrado();

-- -------------------------------------------------------------------------
-- 5. Imágenes del negocio solo con https
-- -------------------------------------------------------------------------

alter table negocios
  add constraint negocios_logo_https
    check (logo is null or (logo ~ '^https://' and char_length(logo) <= 500)),
  add constraint negocios_imagen_https
    check (imagen is null or (imagen ~ '^https://' and char_length(imagen) <= 500));

-- -------------------------------------------------------------------------
-- 6. Privilegios mínimos para los roles de la API
-- -------------------------------------------------------------------------

revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
alter default privileges in schema public
  revoke truncate, references, trigger on tables from anon, authenticated;
