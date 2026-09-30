import { supabase } from './supabaseClient.js';

// Capa de acceso a datos para el módulo Servicios.
// negocio_id SIEMPRE se recibe como parámetro explícito (viene del
// contexto autenticado vía useAuth en la pantalla, nunca de un input
// del usuario) y se usa tanto para filtrar selects como para setear
// el valor en inserts. RLS en Postgres es la barrera real; aquí solo
// evitamos mandar negocio_id de otra fuente.

export async function listarServicios(negocioId) {
  return supabase
    .from('servicios')
    .select('id, negocio_id, nombre, descripcion, precio, duracion_minutos, activo, created_at')
    .eq('negocio_id', negocioId)
    .order('created_at', { ascending: false });
}

export async function crearServicio(negocioId, { nombre, descripcion, precio, duracionMinutos }) {
  return supabase
    .from('servicios')
    .insert({
      negocio_id: negocioId,
      nombre,
      descripcion: descripcion || null,
      precio,
      duracion_minutos: duracionMinutos,
    })
    .select()
    .single();
}

export async function actualizarServicio(negocioId, servicioId, { nombre, descripcion, precio, duracionMinutos }) {
  return supabase
    .from('servicios')
    .update({
      nombre,
      descripcion: descripcion || null,
      precio,
      duracion_minutos: duracionMinutos,
    })
    .eq('id', servicioId)
    .eq('negocio_id', negocioId)
    .select()
    .single();
}

export async function cambiarEstadoServicio(negocioId, servicioId, activo) {
  return supabase
    .from('servicios')
    .update({ activo })
    .eq('id', servicioId)
    .eq('negocio_id', negocioId)
    .select()
    .single();
}
