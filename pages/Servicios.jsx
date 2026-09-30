import { useEffect, useState } from 'react';
import { useAuth } from '../hooks/useAuth.jsx';
import Modal from '../components/Modal.jsx';
import EstadoBadge from '../components/EstadoBadge.jsx';
import {
  actualizarServicio,
  cambiarEstadoServicio,
  crearServicio,
  listarServicios,
} from '../services/serviciosService.js';

const FORM_VACIO = { nombre: '', descripcion: '', precio: '', duracionMinutos: '' };

function formatearPrecio(precio) {
  return new Intl.NumberFormat('es-DO', { style: 'currency', currency: 'DOP' }).format(precio);
}

export default function Servicios() {
  const { negocio, rol } = useAuth();
  const negocioId = negocio?.id ?? null;
  const esOwner = rol === 'OWNER';

  const [servicios, setServicios] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [modalAbierto, setModalAbierto] = useState(false);
  const [servicioEditando, setServicioEditando] = useState(null);
  const [form, setForm] = useState(FORM_VACIO);
  const [guardando, setGuardando] = useState(false);
  const [formError, setFormError] = useState('');
  const [cambiandoEstadoId, setCambiandoEstadoId] = useState(null);

  useEffect(() => {
    if (!negocioId) return;
    cargarServicios();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [negocioId]);

  async function cargarServicios() {
    setLoading(true);
    setError('');
    const { data, error: err } = await listarServicios(negocioId);
    if (err) {
      setError('No se pudieron cargar los servicios. Intenta de nuevo.');
      setServicios([]);
    } else {
      setServicios(data || []);
    }
    setLoading(false);
  }

  function abrirCrear() {
    setServicioEditando(null);
    setForm(FORM_VACIO);
    setFormError('');
    setModalAbierto(true);
  }

  function abrirEditar(servicio) {
    setServicioEditando(servicio);
    setForm({
      nombre: servicio.nombre,
      descripcion: servicio.descripcion || '',
      precio: String(servicio.precio),
      duracionMinutos: String(servicio.duracion_minutos),
    });
    setFormError('');
    setModalAbierto(true);
  }

  function cerrarModal() {
    if (guardando) return;
    setModalAbierto(false);
  }

  async function handleSubmit(event) {
    event.preventDefault();
    if (!negocioId) return;

    const nombre = form.nombre.trim();
    const precio = Number(form.precio);
    const duracionMinutos = Number(form.duracionMinutos);

    if (!nombre) {
      setFormError('El nombre es obligatorio.');
      return;
    }
    if (!Number.isFinite(precio) || precio < 0) {
      setFormError('El precio debe ser un número válido mayor o igual a 0.');
      return;
    }
    if (!Number.isInteger(duracionMinutos) || duracionMinutos <= 0) {
      setFormError('La duración debe ser un número entero de minutos mayor a 0.');
      return;
    }

    setGuardando(true);
    setFormError('');

    const payload = { nombre, descripcion: form.descripcion.trim(), precio, duracionMinutos };

    const { error: err } = servicioEditando
      ? await actualizarServicio(negocioId, servicioEditando.id, payload)
      : await crearServicio(negocioId, payload);

    setGuardando(false);

    if (err) {
      setFormError('No se pudo guardar el servicio. Intenta de nuevo.');
      return;
    }

    setModalAbierto(false);
    await cargarServicios();
  }

  async function handleToggleActivo(servicio) {
    setCambiandoEstadoId(servicio.id);
    const { error: err } = await cambiarEstadoServicio(negocioId, servicio.id, !servicio.activo);
    setCambiandoEstadoId(null);
    if (err) {
      setError('No se pudo actualizar el estado del servicio.');
      return;
    }
    await cargarServicios();
  }

  const serviciosVisibles = esOwner ? servicios : servicios.filter((s) => s.activo);

  return (
    <section className="module-page">
      <header className="module-page__header">
        <div>
          <h1 className="module-page__title">Servicios</h1>
          <p className="module-page__subtitle">Catálogo de servicios ofrecidos por el negocio.</p>
        </div>
        {esOwner && (
          <button type="button" className="btn btn--primary" onClick={abrirCrear}>
            Nuevo servicio
          </button>
        )}
      </header>

      {error && <div className="auth-error">{error}</div>}

      {loading ? (
        <div className="module-page__loading">Cargando servicios…</div>
      ) : serviciosVisibles.length === 0 ? (
        <div className="module-page__empty">
          {esOwner
            ? 'Todavía no has creado ningún servicio. Crea el primero con el botón "Nuevo servicio".'
            : 'Este negocio todavía no tiene servicios activos.'}
        </div>
      ) : (
        <div className="table-wrapper">
          <table className="data-table">
            <thead>
              <tr>
                <th>Nombre</th>
                <th>Descripción</th>
                <th>Precio</th>
                <th>Duración</th>
                <th>Estado</th>
                {esOwner && <th aria-label="Acciones" />}
              </tr>
            </thead>
            <tbody>
              {serviciosVisibles.map((servicio) => (
                <tr key={servicio.id}>
                  <td data-label="Nombre">{servicio.nombre}</td>
                  <td data-label="Descripción">{servicio.descripcion || '—'}</td>
                  <td data-label="Precio">{formatearPrecio(servicio.precio)}</td>
                  <td data-label="Duración">{servicio.duracion_minutos} min</td>
                  <td data-label="Estado">
                    <EstadoBadge activo={servicio.activo} />
                  </td>
                  {esOwner && (
                    <td data-label="Acciones" className="data-table__actions">
                      <button type="button" className="btn btn--ghost" onClick={() => abrirEditar(servicio)}>
                        Editar
                      </button>
                      <button
                        type="button"
                        className="btn btn--ghost"
                        disabled={cambiandoEstadoId === servicio.id}
                        onClick={() => handleToggleActivo(servicio)}
                      >
                        {servicio.activo ? 'Desactivar' : 'Activar'}
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {modalAbierto && (
        <Modal title={servicioEditando ? 'Editar servicio' : 'Nuevo servicio'} onClose={cerrarModal}>
          <form className="form-grid" onSubmit={handleSubmit}>
            {formError && <div className="auth-error">{formError}</div>}

            <div className="auth-field">
              <label htmlFor="servicio-nombre">Nombre</label>
              <input
                id="servicio-nombre"
                type="text"
                value={form.nombre}
                onChange={(e) => setForm((f) => ({ ...f, nombre: e.target.value }))}
                required
              />
            </div>

            <div className="auth-field">
              <label htmlFor="servicio-descripcion">Descripción</label>
              <input
                id="servicio-descripcion"
                type="text"
                value={form.descripcion}
                onChange={(e) => setForm((f) => ({ ...f, descripcion: e.target.value }))}
              />
            </div>

            <div className="form-grid__row">
              <div className="auth-field">
                <label htmlFor="servicio-precio">Precio</label>
                <input
                  id="servicio-precio"
                  type="number"
                  min="0"
                  step="0.01"
                  value={form.precio}
                  onChange={(e) => setForm((f) => ({ ...f, precio: e.target.value }))}
                  required
                />
              </div>

              <div className="auth-field">
                <label htmlFor="servicio-duracion">Duración (min)</label>
                <input
                  id="servicio-duracion"
                  type="number"
                  min="1"
                  step="1"
                  value={form.duracionMinutos}
                  onChange={(e) => setForm((f) => ({ ...f, duracionMinutos: e.target.value }))}
                  required
                />
              </div>
            </div>

            <button type="submit" className="auth-submit" disabled={guardando}>
              {guardando ? 'Guardando…' : servicioEditando ? 'Guardar cambios' : 'Crear servicio'}
            </button>
          </form>
        </Modal>
      )}
    </section>
  );
}
