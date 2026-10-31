-- =========================================================================
-- Citabox — Métricas de uso en el panel del administrador
-- Requiere haber aplicado 001–025 sobre la misma base.
-- =========================================================================
--
-- admin_listar_negocios(): igual que en 023 más el uso de cada negocio:
-- último acceso de su gente, citas en línea, clientes y última cita creada.
-- admin_resumen_uso(): totales de la plataforma para el encabezado.
-- =========================================================================

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
             'tipo', n.tipo,
             'creado', n.created_at,
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
             'citas_en_linea_30d', (select count(*) from citas c
                                     where c.negocio_id = n.id
                                       and c.origen = 'PUBLICA'
                                       and c.created_at >= now() - interval '30 days'),
             'clientes', (select count(*) from clientes cl
                           where cl.negocio_id = n.id and cl.activo),
             'ultima_cita', (select max(c.created_at) from citas c
                              where c.negocio_id = n.id),
             'ultimo_acceso', (select max(u.last_sign_in_at) from perfiles p
                                 join auth.users u on u.id = p.id
                                where p.negocio_id = n.id),
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

-- Activo = alguien del negocio creó una cita en los últimos 7 días.
create or replace function admin_resumen_uso()
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

  return jsonb_build_object(
    'negocios', (select count(*) from negocios),
    'activos_7d', (select count(distinct c.negocio_id) from citas c
                    where c.created_at >= now() - interval '7 days'),
    'en_prueba', (select count(*) from suscripciones where estado = 'PRUEBA'),
    'pagando', (select count(*) from suscripciones where estado = 'ACTIVA'),
    'pausados', (select count(*) from suscripciones
                  where estado in ('VENCIDA', 'SUSPENDIDA')),
    'nuevos_30d', (select count(*) from negocios
                    where created_at >= now() - interval '30 days'),
    'citas_30d', (select count(*) from citas
                   where created_at >= now() - interval '30 days'),
    'citas_en_linea_30d', (select count(*) from citas
                            where origen = 'PUBLICA'
                              and created_at >= now() - interval '30 days')
  );
end;
$$;

revoke all on function admin_resumen_uso() from public, anon;
grant execute on function admin_resumen_uso() to authenticated;
