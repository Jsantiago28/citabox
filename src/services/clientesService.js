import { supabase } from './supabaseClient.js';

// Capa de acceso a datos para el módulo Clientes.
// negocio_id siempre llega como parámetro explícito desde la pantalla
// (proveniente de useAuth), nunca escrito manualmente por el usuario.

export async function listarClientes(negocioId) {
  return supabase
    .from('clientes')
    .select('id, negocio_id, nombre, telefono, email, notas, activo, created_at')
    .eq('negocio_id', negocioId)
    .order('created_at', { ascending: false });
}

export async function crearCliente(negocioId, { nombre, telefono, email, notas }) {
  return supabase
    .from('clientes')
    .insert({
      negocio_id: negocioId,
      nombre,
      telefono: telefono || null,
      email: email || null,
      notas: notas || null,
    })
    .select()
    .single();
}

export async function actualizarCliente(negocioId, clienteId, { nombre, telefono, email, notas }) {
  return supabase
    .from('clientes')
    .update({
      nombre,
      telefono: telefono || null,
      email: email || null,
      notas: notas || null,
    })
    .eq('id', clienteId)
    .eq('negocio_id', negocioId)
    .select()
    .single();
}

export async function cambiarEstadoCliente(negocioId, clienteId, activo) {
  return supabase
    .from('clientes')
    .update({ activo })
    .eq('id', clienteId)
    .eq('negocio_id', negocioId)
    .select()
    .single();
}
