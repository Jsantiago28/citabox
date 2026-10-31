// Citabox — enviar recordatorios de citas por WhatsApp (API de Meta)
//
// POST sin cuerpo, con el encabezado "x-cron-secret" igual al secreto
// RECORDATORIOS_SECRETO. La llama cada 15 minutos el flujo
// .github/workflows/recordatorios.yml (no la usa la app).
// 1. Pide a la base las citas que tocan (recordatorios_pendientes).
// 2. Envía a cada cliente la plantilla aprobada en Meta.
// 3. Anota cada resultado (registrar_recordatorio): lo enviado no se
//    repite y lo fallido se reintenta hasta 3 veces.
// Si faltan WHATSAPP_TOKEN o WHATSAPP_PHONE_ID responde 200 con
// { omitido } y no envía nada. Ver supabase/functions/README.md.

import { createClient } from 'npm:@supabase/supabase-js@2';

const GRAPH_URL = 'https://graph.facebook.com/v21.0';

interface Pendiente {
  cita_id: string;
  fecha: string; // '2026-10-31'
  hora: string; // '15:00'
  negocio: string;
  negocio_telefono: string | null;
  cliente: string;
  telefono: string;
  servicio: string;
  barbero: string;
}

function responder(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

// Comparación en tiempo constante para el secreto.
function iguales(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diferencia = 0;
  for (let i = 0; i < x.length; i++) diferencia |= x[i] ^ y[i];
  return diferencia === 0;
}

// Igual que telefonoWhatsApp() de la app: 10 dígitos (RD, EE. UU.) → 1 delante.
export function telefonoWhatsApp(telefono: string): string {
  const digitos = telefono.replace(/\D/g, '');
  return digitos.length === 10 ? `1${digitos}` : digitos;
}

// '2026-10-31' → 'sábado 31 de octubre'.
export function fechaLarga(fecha: string): string {
  return new Date(`${fecha}T12:00:00Z`)
    .toLocaleDateString('es-DO', {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      timeZone: 'UTC',
    })
    .replace(',', '');
}

// '15:00' → '3:00 PM' (como formatoHora() de la app).
export function horaCorta(hora: string): string {
  const [h, m] = hora.split(':').map(Number);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

// Parámetros de la plantilla, en orden:
// {{1}} cliente, {{2}} negocio, {{3}} fecha, {{4}} hora, {{5}} servicio,
// {{6}} barbero.
export function parametros(p: Pendiente): string[] {
  return [
    p.cliente.trim().split(/\s+/)[0] || p.cliente.trim(),
    p.negocio.trim(),
    fechaLarga(p.fecha),
    horaCorta(p.hora),
    p.servicio.trim(),
    p.barbero.trim(),
  ];
}

async function enviar(
  p: Pendiente,
  token: string,
  phoneId: string,
  plantilla: string,
  idioma: string,
): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  const respuesta = await fetch(`${GRAPH_URL}/${phoneId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: telefonoWhatsApp(p.telefono),
      type: 'template',
      template: {
        name: plantilla,
        language: { code: idioma },
        components: [
          {
            type: 'body',
            parameters: parametros(p).map((text) => ({ type: 'text', text })),
          },
        ],
      },
    }),
  });
  const cuerpo = await respuesta.json().catch(() => ({}));
  const id = cuerpo?.messages?.[0]?.id;
  if (respuesta.ok && typeof id === 'string') return { ok: true, id };
  const error = cuerpo?.error?.message ?? `HTTP ${respuesta.status}`;
  return { ok: false, error: String(error) };
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return responder(405, { error: 'Método no permitido.' });
  }

  const secreto = Deno.env.get('RECORDATORIOS_SECRETO') ?? '';
  if (!secreto || !iguales(req.headers.get('x-cron-secret') ?? '', secreto)) {
    return responder(401, { error: 'No autorizado.' });
  }

  const token = Deno.env.get('WHATSAPP_TOKEN');
  const phoneId = Deno.env.get('WHATSAPP_PHONE_ID');
  if (!token || !phoneId) {
    return responder(200, {
      ok: true,
      omitido: 'Faltan WHATSAPP_TOKEN y/o WHATSAPP_PHONE_ID.',
    });
  }
  const plantilla = Deno.env.get('WHATSAPP_PLANTILLA') || 'recordatorio_cita';
  const idioma = Deno.env.get('WHATSAPP_IDIOMA') || 'es';

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  const { data, error } = await admin.rpc('recordatorios_pendientes', {
    p_limite: 200,
  });
  if (error) {
    console.error('recordatorios_pendientes', error.message);
    return responder(500, { error: 'No se pudieron leer las citas.' });
  }

  let enviados = 0;
  let fallidos = 0;
  for (const p of (data ?? []) as Pendiente[]) {
    let resultado: Awaited<ReturnType<typeof enviar>>;
    try {
      resultado = await enviar(p, token, phoneId, plantilla, idioma);
    } catch (e) {
      resultado = { ok: false, error: e instanceof Error ? e.message : String(e) };
    }
    if (resultado.ok) enviados++;
    else fallidos++;

    const { error: errorRegistro } = await admin.rpc('registrar_recordatorio', {
      p_cita: p.cita_id,
      p_fecha: p.fecha,
      p_hora: p.hora,
      p_ok: resultado.ok,
      p_mensaje_id: resultado.ok ? resultado.id : null,
      p_error: resultado.ok ? null : resultado.error,
    });
    if (errorRegistro) {
      // Sin registro se reenviaría en la próxima vuelta: mejor parar.
      console.error('registrar_recordatorio', errorRegistro.message);
      return responder(500, { error: 'No se pudo anotar un envío.', enviados, fallidos });
    }
  }

  return responder(200, { ok: true, enviados, fallidos });
});
