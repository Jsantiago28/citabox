// Cloudflare Pages Function: /r/<slug>
//
// Es el enlace que se comparte por WhatsApp/redes. Devuelve HTML mínimo con
// las etiquetas Open Graph del negocio (nombre, imagen) para la vista previa
// y redirige de inmediato a la app: /#/reservar/<slug>.
//
// Variables de entorno (secretos del proyecto Pages): SUPABASE_URL y
// SUPABASE_PUBLISHABLE_KEY (la clave pública, la misma que usa la app).

const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

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
    const res = await fetch(`${base}/rest/v1/rpc/reserva_catalogo`, {
      method: 'POST',
      headers: {
        apikey: clave,
        Authorization: `Bearer ${clave}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_slug: slug }),
    });
    if (!res.ok) return null;
    const datos = await res.json();
    return datos && datos.negocio ? datos.negocio : null;
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

export async function onRequestGet({ params, request, env }) {
  const url = new URL(request.url);
  const slug = String(Array.isArray(params.slug) ? params.slug[0] : params.slug || '')
    .trim()
    .toLowerCase();
  if (!SLUG_RE.test(slug) || slug.length > 80) return inicio(url.origin);

  const negocio = await negocioDe(slug, env);
  if (!negocio || !negocio.nombre) return inicio(url.origin);

  const destino = `/#/reservar/${slug}`;
  const titulo = esc(negocio.nombre);
  const descripcion = 'Reserva tu cita en línea';
  const imagen = imagenHttps(negocio.imagen, negocio.logo);
  const enlace = esc(`${url.origin}/r/${slug}`);

  const html = `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>${titulo}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="${descripcion}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Barbería PRO">
<meta property="og:title" content="${titulo}">
<meta property="og:description" content="${descripcion}">
<meta property="og:url" content="${enlace}">
${imagen ? `<meta property="og:image" content="${esc(imagen)}">\n` : ''}<meta name="twitter:card" content="${imagen ? 'summary_large_image' : 'summary'}">
<meta name="twitter:title" content="${titulo}">
<meta name="twitter:description" content="${descripcion}">
${imagen ? `<meta name="twitter:image" content="${esc(imagen)}">\n` : ''}<meta http-equiv="refresh" content="0;url=${esc(destino)}">
</head>
<body>
<p><a href="${esc(destino)}">${titulo}: reserva tu cita</a></p>
<script>location.replace(${JSON.stringify(destino).replace(/</g, '\\u003c')});</script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
    },
  });
}
