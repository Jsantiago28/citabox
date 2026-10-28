// Barbería PRO — invitar a un barbero
//
// POST { empleado_id, email } con el JWT del dueño en "Authorization".
// 1. Comprueba, con los permisos del propio usuario (RLS), que es OWNER
//    activo y que el empleado es de SU negocio y aún no tiene cuenta.
// 2. Con la clave service_role invita al correo (Supabase envía el correo
//    para fijar la contraseña), crea el perfil EMPLOYEE y liga la ficha
//    (empleados.perfil_id).
// Respuestas: 200 { ok: true } · 4xx/5xx { error: 'mensaje en español' }.

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// La app usa esta marca para pedir al invitado que fije su contraseña.
const DEBE_FIJAR_PASSWORD = 'debe_fijar_password';

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_RE = /^\S+@\S+\.\S+$/;

class ErrorHttp extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

function responder(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function env(nombre: string, ...alternativas: string[]): string {
  for (const clave of [nombre, ...alternativas]) {
    const valor = Deno.env.get(clave);
    if (valor) return valor;
  }
  throw new ErrorHttp(500, `Falta configurar ${nombre} en la función.`);
}

interface Empleado {
  id: string;
  nombre: string;
  telefono: string | null;
  perfil_id: string | null;
}

async function leerEntrada(req: Request) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    throw new ErrorHttp(400, 'El cuerpo de la solicitud debe ser JSON.');
  }
  const datos = (body ?? {}) as Record<string, unknown>;
  const empleadoId =
    typeof datos.empleado_id === 'string' ? datos.empleado_id.trim() : '';
  const email =
    typeof datos.email === 'string' ? datos.email.trim().toLowerCase() : '';

  if (!UUID_RE.test(empleadoId)) {
    throw new ErrorHttp(400, 'Falta el barbero a invitar.');
  }
  if (!EMAIL_RE.test(email)) {
    throw new ErrorHttp(400, 'Ingresa un correo válido.');
  }
  return { empleadoId, email };
}

/** Dueño activo que hace la solicitud y su negocio. */
async function negocioDelOwner(cliente: SupabaseClient, jwt: string) {
  const { data: auth, error: authError } = await cliente.auth.getUser(jwt);
  if (authError || !auth.user) {
    throw new ErrorHttp(401, 'Tu sesión venció. Vuelve a iniciar sesión.');
  }

  const { data: perfil, error } = await cliente
    .from('perfiles')
    .select('negocio_id, rol, activo')
    .eq('id', auth.user.id)
    .maybeSingle();
  if (error) {
    throw new ErrorHttp(500, 'No se pudo comprobar tu perfil.');
  }
  if (!perfil || perfil.rol !== 'OWNER' || perfil.activo !== true) {
    throw new ErrorHttp(403, 'Solo el dueño del negocio puede invitar barberos.');
  }
  return perfil.negocio_id as string;
}

async function empleadoSinCuenta(
  cliente: SupabaseClient,
  empleadoId: string,
  negocioId: string,
): Promise<Empleado> {
  const { data, error } = await cliente
    .from('empleados')
    .select('id, nombre, telefono, perfil_id')
    .eq('id', empleadoId)
    .eq('negocio_id', negocioId)
    .maybeSingle();
  if (error) {
    throw new ErrorHttp(500, 'No se pudo consultar el barbero.');
  }
  if (!data) {
    throw new ErrorHttp(404, 'Ese barbero no existe en tu negocio.');
  }
  if (data.perfil_id) {
    throw new ErrorHttp(409, 'Este barbero ya tiene una cuenta.');
  }
  return data as Empleado;
}

/** Busca un usuario de Auth por correo (la API admin no filtra por correo). */
async function buscarUsuarioPorEmail(admin: SupabaseClient, email: string) {
  const porPagina = 1000;
  for (let pagina = 1; pagina <= 100; pagina++) {
    const { data, error } = await admin.auth.admin.listUsers({
      page: pagina,
      perPage: porPagina,
    });
    if (error) {
      throw new ErrorHttp(500, 'No se pudo comprobar el correo.');
    }
    const usuario = data.users.find((u) => u.email?.toLowerCase() === email);
    if (usuario) return usuario;
    if (data.users.length < porPagina) break;
  }
  return null;
}

function correoYaRegistrado(error: { status?: number; code?: string; message: string }) {
  const texto = `${error.code ?? ''} ${error.message}`.toLowerCase();
  return (
    error.code === 'email_exists' ||
    texto.includes('already') ||
    texto.includes('registered')
  );
}

/**
 * Invita al correo. Si ya existe una cuenta con ese correo, la reutiliza
 * (sin correo nuevo: esa persona ya tiene contraseña).
 * Devuelve el id del usuario y si se creó en esta llamada.
 */
async function invitarOReutilizar(
  admin: SupabaseClient,
  email: string,
  empleado: Empleado,
) {
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { nombre: empleado.nombre, [DEBE_FIJAR_PASSWORD]: true },
  });
  if (!error && data.user) {
    return { userId: data.user.id, creado: true };
  }

  if (error && correoYaRegistrado(error)) {
    const existente = await buscarUsuarioPorEmail(admin, email);
    if (!existente) {
      throw new ErrorHttp(409, 'Ese correo ya está registrado, pero no se encontró la cuenta.');
    }
    return { userId: existente.id, creado: false };
  }

  if (error?.status === 429) {
    throw new ErrorHttp(429, 'Se enviaron demasiados correos. Espera unos minutos.');
  }
  throw new ErrorHttp(502, 'No se pudo enviar la invitación. Intenta de nuevo.');
}

async function invitar(req: Request): Promise<Response> {
  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!jwt || jwt === authHeader) {
    throw new ErrorHttp(401, 'Inicia sesión para invitar barberos.');
  }

  const { empleadoId, email } = await leerEntrada(req);

  const url = env('SUPABASE_URL');
  const anonKey = env('SUPABASE_ANON_KEY', 'SUPABASE_PUBLISHABLE_KEY');
  const serviceKey = env('SUPABASE_SERVICE_ROLE_KEY');
  const sinSesion = { persistSession: false, autoRefreshToken: false };

  // Cliente con los permisos del usuario: RLS decide qué puede ver.
  const usuario = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: sinSesion,
  });
  const negocioId = await negocioDelOwner(usuario, jwt);
  const empleado = await empleadoSinCuenta(usuario, empleadoId, negocioId);

  const admin = createClient(url, serviceKey, { auth: sinSesion });
  const { userId, creado } = await invitarOReutilizar(admin, email, empleado);

  // Deshace la cuenta recién invitada si no se pudo terminar de ligar, para
  // que el dueño pueda reintentar con el mismo correo.
  const deshacer = async (borrarPerfil: boolean) => {
    if (borrarPerfil) await admin.from('perfiles').delete().eq('id', userId);
    if (creado) await admin.auth.admin.deleteUser(userId);
  };

  if (!creado) {
    const { data: perfil, error } = await admin
      .from('perfiles')
      .select('negocio_id')
      .eq('id', userId)
      .maybeSingle();
    if (error) {
      throw new ErrorHttp(500, 'No se pudo comprobar el correo.');
    }
    if (perfil) {
      throw new ErrorHttp(
        409,
        perfil.negocio_id === negocioId
          ? 'Ese correo ya pertenece a otra cuenta de tu negocio.'
          : 'Ese correo ya pertenece a una cuenta de otro negocio.',
      );
    }
  }

  const { error: perfilError } = await admin.from('perfiles').insert({
    id: userId,
    negocio_id: negocioId,
    nombre: empleado.nombre,
    telefono: empleado.telefono,
    rol: 'EMPLOYEE',
  });
  if (perfilError) {
    await deshacer(false);
    if (perfilError.code === '23505') {
      throw new ErrorHttp(409, 'Ese correo ya tiene una cuenta en el sistema.');
    }
    throw new ErrorHttp(500, 'No se pudo crear el perfil del barbero.');
  }

  // Solo liga si la ficha sigue libre (evita carreras entre dos invitaciones).
  const { data: ligados, error: ligarError } = await admin
    .from('empleados')
    .update({ perfil_id: userId })
    .eq('id', empleado.id)
    .eq('negocio_id', negocioId)
    .is('perfil_id', null)
    .select('id');
  if (ligarError || !ligados || ligados.length === 0) {
    await deshacer(true);
    throw new ErrorHttp(
      ligarError ? 500 : 409,
      ligarError
        ? 'No se pudo ligar la cuenta con el barbero.'
        : 'Este barbero ya tiene una cuenta.',
    );
  }

  // correo_enviado = false: el correo ya tenía cuenta (sin negocio); esa
  // persona entra con su contraseña de siempre y no recibe correo nuevo.
  return responder(200, { ok: true, correo_enviado: creado });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return responder(405, { error: 'Método no permitido.' });
  }

  try {
    return await invitar(req);
  } catch (error) {
    if (error instanceof ErrorHttp) {
      return responder(error.status, { error: error.message });
    }
    console.error('invitar-barbero', error);
    return responder(500, { error: 'Ocurrió un error inesperado. Intenta de nuevo.' });
  }
});
