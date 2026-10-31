-- =========================================================================
-- Citabox — Fidelización: "la décima gratis"
-- Requiere haber aplicado 001–027 sobre la misma base.
-- =========================================================================
--
-- El dueño elige cada cuántas visitas atendidas hay premio y cuál es
-- (por ejemplo, cada 10: "Corte gratis"). Sin número, no hay programa.
-- La página de reservas lo muestra para animar al cliente a volver.
-- =========================================================================

alter table negocios
  add column if not exists fidelidad_visitas smallint
    constraint negocios_fidelidad_visitas_rango
      check (fidelidad_visitas is null or fidelidad_visitas between 2 and 50),
  add column if not exists fidelidad_premio text not null default 'Servicio gratis'
    constraint negocios_fidelidad_premio_largo
      check (length(btrim(fidelidad_premio)) between 1 and 80);

-- Catálogo público: igual que en 025 más el programa de fidelidad.
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
      'fidelidad_visitas', v_neg.fidelidad_visitas,
      'fidelidad_premio', v_neg.fidelidad_premio,
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
