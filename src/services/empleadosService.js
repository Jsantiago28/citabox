import { supabase } from './supabaseClient.js';

// Capa de acceso a datos para el módulo Empleados.
// negocio_id siempre llega como parámetro explícito desde la pantalla
// (proveniente de useAuth), nunca escrito manualmente por el usuario.
//
// Nota: por ahora se gestiona el registro operativo del
// barbero/estilista (nombre, teléfono, foto, activo). La vinculación
// con una cuenta de acceso (perfil_id / invitación de usuario) queda
// para una fase posterior, fuera del alcance de Fase 3.

export async function listarEmpleados(negocioId) {
  return supabase
    .from('empleados')
    .select('id, negocio_id, perfil_id, nombre, telefono, foto, activo, created_at')
    .eq('negocio_id', negocioId)
    .order('created_at', { ascending: false });
}

export async function crearEmpleado(negocioId, { nombre, telefono, foto }) {
  return supabase
    .from('empleados')
    .insert({
      negocio_id: negocioId,
      nombre,
      telefono: telefono || null,
      foto: foto || null,
    })
    .select()
    .single();
}

export async function actualizarEmpleado(negocioId, empleadoId, { nombre, telefono, foto }) {
  return supabase
    .from('empleados')
    .update({
      nombre,
      telefono: telefono || null,
      foto: foto || null,
    })
    .eq('id', empleadoId)
    .eq('negocio_id', negocioId)
    .select()
    .single();
}

export async function cambiarEstadoEmpleado(negocioId, empleadoId, activo) {
  return supabase
    .from('empleados')
    .update({ activo })
    .eq('id', empleadoId)
    .eq('negocio_id', negocioId)
    .select()
    .single();
}
