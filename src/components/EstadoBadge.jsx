// Badge reutilizable para mostrar el estado activo/inactivo de un
// registro (servicio, cliente, empleado, etc.).
export default function EstadoBadge({ activo }) {
  return (
    <span className={activo ? 'estado-badge estado-badge--activo' : 'estado-badge estado-badge--inactivo'}>
      {activo ? 'Activo' : 'Inactivo'}
    </span>
  );
}
