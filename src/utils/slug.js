// Genera un slug compatible con el constraint de la base de datos:
// ^[a-z0-9]+(-[a-z0-9]+)*$
export function slugify(texto) {
  return (texto ?? '')
    .toString()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '') // quita acentos
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-{2,}/g, '-');
}

export function slugValido(slug) {
  return /^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug ?? '');
}
