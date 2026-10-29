-- =========================================================================
-- Barbería PRO — Ícono de cada servicio
-- Requiere haber aplicado 001–011 sobre la misma base.
-- =========================================================================
--
-- "icono" es una clave corta (p. ej. 'secador', 'tijera') que la app
-- convierte en un ícono. Es opcional: sin clave se usa la tijera.
-- reserva_catalogo la devuelve para mostrarla a los clientes.
-- =========================================================================

alter table servicios
  add column icono text,
  add constraint servicios_icono_formato
    check (icono is null or icono ~ '^[a-z_]{1,30}$');

-- Misma función que en 007, con 'icono' en cada servicio.
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
               'duracion_minutos', s.duracion_minutos,
               'icono', s.icono
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

