// Placeholder profesional reutilizable para módulos aún no implementados.
// Se elimina/reemplaza módulo por módulo cuando el arquitecto entregue
// la especificación funcional correspondiente.
export default function PagePlaceholder({ title, description }) {
  return (
    <section className="page-placeholder">
      <h1 className="page-placeholder__title">{title}</h1>
      {description && <p className="page-placeholder__description">{description}</p>}
      <div className="page-placeholder__badge">Módulo pendiente de implementación</div>
    </section>
  );
}
