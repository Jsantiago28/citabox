-- =========================================================================
-- Citabox — Vista previa del enlace de reservas
-- Requiere haber aplicado 001–028 sobre la misma base.
-- =========================================================================
--
-- Al compartir /r/<slug> por WhatsApp, la función de Cloudflare arma la
-- vista previa: "<Dueño> te invita a reservar en <Negocio>". Esta función
-- pública da solo lo necesario: nombre y tipo del negocio, imagen y el
-- primer nombre del dueño (nada de correo, teléfono ni apellidos).
-- Sin negocio activo o con el servicio suspendido devuelve null.
-- =========================================================================

create or replace function reserva_vista_previa(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
           'nombre', n.nombre,
           'tipo', n.tipo,
           'imagen', n.imagen,
           'logo', n.logo,
           'dueno', (
             select nullif(split_part(btrim(p.nombre), ' ', 1), '')
               from perfiles p
              where p.negocio_id = n.id
                and p.rol = 'OWNER'
                and p.activo
              order by p.created_at, p.id
              limit 1
           )
         )
    from negocios n
   where n.slug = lower(btrim(coalesce(p_slug, '')))
     and n.estado = 'ACTIVO'
     and negocio_servicio_activo(n.id);
$$;

revoke all on function reserva_vista_previa(text) from public;
grant execute on function reserva_vista_previa(text) to anon, authenticated;
