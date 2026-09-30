export function validarNombre(nombre, etiqueta = 'El nombre') {
  if (!nombre?.trim()) return `${etiqueta} es obligatorio.`;
  if (nombre.trim().length < 2) return `${etiqueta} debe tener al menos 2 caracteres.`;
  return null;
}

export function validarPrecio(precio) {
  if (precio === '' || precio === null || precio === undefined) return 'El precio es obligatorio.';
  const valor = Number(precio);
  if (!Number.isFinite(valor) || valor < 0) return 'El precio debe ser un número mayor o igual a 0.';
  return null;
}

export function validarDuracion(duracion) {
  const valor = Number(duracion);
  if (!Number.isInteger(valor) || valor <= 0) return 'La duración debe ser un número entero mayor que 0.';
  return null;
}

export function validarTelefono(telefono) {
  if (!telefono?.trim()) return null;
  if (telefono.trim().length < 7) return 'El teléfono parece demasiado corto.';
  return null;
}

export function validarEmail(email) {
  if (!email?.trim()) return null;
  return /^\S+@\S+\.\S+$/.test(email.trim()) ? null : 'Ingresa un correo válido.';
}
