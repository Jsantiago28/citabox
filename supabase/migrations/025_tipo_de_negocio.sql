-- =========================================================================
-- Citabox — Tipo de negocio y textos generales
-- Requiere haber aplicado 001–024 sobre la misma base.
-- =========================================================================
--
-- La app ya no es solo para barberías: cada negocio guarda su tipo y la app
-- usa las palabras que le tocan (barbero, estilista, terapeuta…). Los
-- negocios que ya existían quedan como barbería. Los mensajes de la base
-- de datos pasan a palabras que sirven para cualquier negocio.
-- =========================================================================

alter table negocios
  add column if not exists tipo text not null default 'barberia'
    constraint negocios_tipo_valido
      check (tipo in ('barberia', 'salon', 'unas', 'spa', 'consultorio', 'otro'));

-- El plan intermedio se llamaba "Barbería".
update planes set nombre = 'Equipo' where codigo = 'barberia';

-- Negocio ACTIVO por slug, o error (007 con el mensaje general).
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
    raise exception 'No encontramos este negocio. Revisa el enlace.'
      using errcode = 'P0001';
  end if;

  return v_neg;
end;
$$;

-- Persona del equipo activa que realiza el servicio, o error (007).
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
    raise exception 'Esta persona no está disponible.'
      using errcode = 'P0001';
  end if;

  if exists (select 1 from empleado_servicios es where es.empleado_id = p_empleado_id)
     and not exists (
       select 1 from empleado_servicios es
        where es.empleado_id = p_empleado_id
          and es.servicio_id = p_servicio_id
     ) then
    raise exception 'Esta persona no realiza este servicio.'
      using errcode = 'P0001';
  end if;
end;
$$;

-- Límite de personas activas del plan (017 con el mensaje general).
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
    raise exception 'Tu plan permite hasta % persona(s) activa(s) en el equipo. Cambia de plan para agregar más.', v_max
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- Catálogo público: igual que en 017 más el tipo de negocio, para que la
-- página de reservas use las palabras que le tocan.
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
    raise exception 'Este negocio no está recibiendo reservas en línea por ahora.'
      using errcode = 'P0001';
  end if;

  v_hoy := reserva_priv_ahora(v_neg.zona_horaria)::date;

  return jsonb_build_object(
    'negocio', jsonb_build_object(
      'nombre', v_neg.nombre,
      'slug', v_neg.slug,
      'tipo', v_neg.tipo,
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
