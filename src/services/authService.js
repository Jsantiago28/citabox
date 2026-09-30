import { supabase } from './supabaseClient.js';

// Capa fina sobre supabase.auth. No crea una segunda instancia del
// cliente; reutiliza el ya existente en services/supabaseClient.js.

export async function signIn(email, password) {
  return supabase.auth.signInWithPassword({ email, password });
}

export async function signUp(email, password) {
  return supabase.auth.signUp({ email, password });
}

export async function signOut() {
  return supabase.auth.signOut();
}

export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session ?? null;
}

export function onAuthStateChange(callback) {
  const { data } = supabase.auth.onAuthStateChange((event, session) => {
    callback(event, session);
  });
  return data.subscription;
}

export async function enviarCorreoRecuperacion(email) {
  return supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}/restablecer-password`,
  });
}

export async function actualizarPassword(nuevaPassword) {
  return supabase.auth.updateUser({ password: nuevaPassword });
}

// Bootstrap seguro de negocio + perfil OWNER. Llama a la función
// SECURITY DEFINER creada en 003_auth_bootstrap.sql. Requiere que el
// usuario ya tenga una sesión activa (ver limitación documentada en esa
// migración si el proyecto exige confirmación de correo).
export async function registrarNegocioYOwner({
  negocioNombre,
  negocioSlug,
  negocioTelefono,
  ownerNombre,
  ownerTelefono,
}) {
  return supabase.rpc('bootstrap_negocio_owner', {
    p_negocio_nombre: negocioNombre,
    p_negocio_slug: negocioSlug,
    p_negocio_telefono: negocioTelefono || null,
    p_owner_nombre: ownerNombre,
    p_owner_telefono: ownerTelefono || null,
  });
}

export async function slugDisponible(slug) {
  const { data, error } = await supabase.rpc('negocio_slug_disponible', { p_slug: slug });
  if (error) return { disponible: null, error };
  return { disponible: data, error: null };
}

const PENDING_REGISTRATION_KEY = 'barberia-pro:registro-pendiente:v1';
const PENDING_REGISTRATION_MAX_AGE_MS = 24 * 60 * 60 * 1000;

export function guardarRegistroPendiente(datos) {
  window.localStorage.setItem(PENDING_REGISTRATION_KEY, JSON.stringify({
    ...datos,
    email: datos.email?.trim().toLowerCase() || '',
    savedAt: Date.now(),
  }));
}

export function obtenerRegistroPendiente() {
  try {
    const raw = window.localStorage.getItem(PENDING_REGISTRATION_KEY);
    if (!raw) return null;
    const payload = JSON.parse(raw);
    if (!payload?.savedAt || Date.now() - payload.savedAt > PENDING_REGISTRATION_MAX_AGE_MS) {
      window.localStorage.removeItem(PENDING_REGISTRATION_KEY);
      return null;
    }
    return payload;
  } catch {
    window.localStorage.removeItem(PENDING_REGISTRATION_KEY);
    return null;
  }
}

export function limpiarRegistroPendiente() {
  window.localStorage.removeItem(PENDING_REGISTRATION_KEY);
}

export async function completarRegistroPendiente(user) {
  if (!user?.id || !user.email) return { completado: false, existente: false, error: null };

  const { data: perfilExistente, error: perfilError } = await obtenerPerfilConNegocio(user.id);
  if (!perfilError && perfilExistente) {
    limpiarRegistroPendiente();
    return { completado: false, existente: true, error: null };
  }

  const pendiente = obtenerRegistroPendiente();
  if (!pendiente || pendiente.email !== user.email.trim().toLowerCase()) {
    return { completado: false, existente: false, error: null };
  }

  const { error } = await registrarNegocioYOwner({
    negocioNombre: pendiente.negocioNombre,
    negocioSlug: pendiente.slug,
    negocioTelefono: pendiente.negocioTelefono,
    ownerNombre: pendiente.ownerNombre,
    ownerTelefono: pendiente.ownerTelefono,
  });

  if (error) return { completado: false, existente: false, error };

  limpiarRegistroPendiente();
  return { completado: true, existente: false, error: null };
}

// Trae perfil + negocio del usuario autenticado en una sola consulta.
export async function obtenerPerfilConNegocio(userId) {
  return supabase
    .from('perfiles')
    .select('id, negocio_id, nombre, telefono, rol, activo, negocios ( id, nombre, slug )')
    .eq('id', userId)
    .single();
}
