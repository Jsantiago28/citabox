// Cloudflare Pages Function: /r/<slug>
//
// Es el enlace que se comparte por WhatsApp/redes. Devuelve HTML mínimo con
// las etiquetas Open Graph del negocio para la vista previa ("María te
// invita a reservar en Salón Brillo") y redirige de inmediato a la app:
// /#/reservar/<slug>.
//
// Variables de entorno (secretos del proyecto Pages): SUPABASE_URL y
// SUPABASE_PUBLISHABLE_KEY (la clave pública, la misma que usa la app).

const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// Qué se reserva según el tipo de negocio (como en utils/vocabulario.dart).
const QUE_SE_RESERVA = {
  barberia: 'tu corte',
  salon: 'tu cita de belleza',
  unas: 'tu cita de uñas',
  spa: 'tu momento de relax',
  consultorio: 'tu consulta',
};

function esc(valor) {
  return String(valor ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function inicio(origen) {
  return Response.redirect(`${origen}/`, 302);
}

async function negocioDe(slug, env) {
  const base = String(env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
  const clave = String(env.SUPABASE_PUBLISHABLE_KEY || '').trim();
  if (!base || !clave) return null;
  try {
    const res = await fetch(`${base}/rest/v1/rpc/reserva_vista_previa`, {
      method: 'POST',
      headers: {
        apikey: clave,
        Authorization: `Bearer ${clave}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_slug: slug }),
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

function imagenHttps(...candidatas) {
  for (const c of candidatas) {
    if (typeof c !== 'string') continue;
    try {
      const u = new URL(c.trim());
      if (u.protocol === 'https:') return u.href;
    } catch {
      // se ignora y se prueba la siguiente
    }
  }
  return null;
}

// Textos de la vista previa.
function textos(negocio) {
  const nombre = String(negocio.nombre).trim();
  const dueno = typeof negocio.dueno === 'string' ? negocio.dueno.trim() : '';
  const que = QUE_SE_RESERVA[negocio.tipo] || 'tu cita';
  return {
    titulo: dueno
      ? `${dueno} te invita a reservar en ${nombre}`
      : `Reserva en ${nombre}`,
    descripcion:
      `Aparta ${que} en menos de un minuto: escoge el servicio, ` +
      'con quién y la hora que te convenga. Sin llamadas ni esperas.',
  };
}

export async function onRequestGet({ params, request, env }) {
  const url = new URL(request.url);
  const slug = String(Array.isArray(params.slug) ? params.slug[0] : params.slug || '')
    .trim()
    .toLowerCase();
  if (!SLUG_RE.test(slug) || slug.length > 80) return inicio(url.origin);

  const negocio = await negocioDe(slug, env);
  if (!negocio || !negocio.nombre) return inicio(url.origin);

  const destino = `/#/reservar/${slug}`;
  const { titulo: tituloTexto, descripcion: descripcionTexto } = textos(negocio);
  const titulo = esc(tituloTexto);
  const descripcion = esc(descripcionTexto);
  // Sin foto del negocio, el logo de Citabox (WhatsApp necesita dirección completa).
  const propia = imagenHttps(negocio.imagen, negocio.logo);
  const imagen = propia || `${url.origin}/icons/Icon-512.png`;
  const enlace = esc(`${url.origin}/r/${slug}`);

  const html = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>${titulo}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="${descripcion}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Citabox">
<meta property="og:locale" content="es_DO">
<meta property="og:title" content="${titulo}">
<meta property="og:description" content="${descripcion}">
<meta property="og:url" content="${enlace}">
<meta property="og:image" content="${esc(imagen)}">
<meta name="twitter:card" content="${propia ? 'summary_large_image' : 'summary'}">
<meta name="twitter:title" content="${titulo}">
<meta name="twitter:description" content="${descripcion}">
<meta name="twitter:image" content="${esc(imagen)}">
<meta http-equiv="refresh" content="0;url=${esc(destino)}">
</head>
<body>
<p><a href="${esc(destino)}">${titulo}</a></p>
<script>location.replace(${JSON.stringify(destino).replace(/</g, '\u003c')});</script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
    },
  });
}
