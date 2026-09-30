import { useEffect, useState } from 'react';
import { useAuth } from '../hooks/useAuth.jsx';
import Modal from '../components/Modal.jsx';
import EstadoBadge from '../components/EstadoBadge.jsx';
import {
  actualizarEmpleado,
  cambiarEstadoEmpleado,
  crearEmpleado,
  listarEmpleados,
} from '../services/empleadosService.js';

const FORM_VACIO = { nombre: '', telefono: '', foto: '' };

export default function Empleados() {
  const { negocio, rol } = useAuth();
  const negocioId = negocio?.id ?? null;
  const esOwner = rol === 'OWNER';

  const [empleados, setEmpleados] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [modalAbierto, setModalAbierto] = useState(false);
  const [empleadoEditando, setEmpleadoEditando] = useState(null);
  const [form, setForm] = useState(FORM_VACIO);
  const [guardando, setGuardando] = useState(false);
  const [formError, setFormError] = useState('');
  const [cambiandoEstadoId, setCambiandoEstadoId] = useState(null);

  useEffect(() => {
    if (!negocioId) return;
    cargarEmpleados();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [negocioId]);

  async function cargarEmpleados() {
    setLoading(true);
    setError('');
    const { data, error: err } = await listarEmpleados(negocioId);
    if (err) {
      setError('No se pudieron cargar los empleados. Intenta de nuevo.');
      setEmpleados([]);
    } else {
      setEmpleados(data || []);
    }
    setLoading(false);
  }

  function abrirCrear() {
    setEmpleadoEditando(null);
    setForm(FORM_VACIO);
    setFormError('');
    setModalAbierto(true);
  }

  function abrirEditar(empleado) {
    setEmpleadoEditando(empleado);
    setForm({
      nombre: empleado.nombre,
      telefono: empleado.telefono || '',
      foto: empleado.foto || '',
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
    if (!negocioId || !esOwner) return;

    const nombre = form.nombre.trim();
    if (!nombre) {
      setFormError('El nombre es obligatorio.');
      return;
    }

    setGuardando(true);
    setFormError('');

    const payload = {
      nombre,
      telefono: form.telefono.trim(),
      foto: form.foto.trim(),
    };

    const { error: err } = empleadoEditando
      ? await actualizarEmpleado(negocioId, empleadoEditando.id, payload)
      : await crearEmpleado(negocioId, payload);

    setGuardando(false);

    if (err) {
      setFormError('No se pudo guardar el empleado. Intenta de nuevo.');
      return;
    }

    setModalAbierto(false);
    await cargarEmpleados();
  }

  async function handleToggleActivo(empleado) {
    setCambiandoEstadoId(empleado.id);
    const { error: err } = await cambiarEstadoEmpleado(negocioId, empleado.id, !empleado.activo);
    setCambiandoEstadoId(null);
    if (err) {
      setError('No se pudo actualizar el estado del empleado.');
      return;
    }
    await cargarEmpleados();
  }

  return (
    <section className="module-page">
      <header className="module-page__header">
        <div>
          <h1 className="module-page__title">Empleados</h1>
          <p className="module-page__subtitle">Barberos/estilistas del negocio y su disponibilidad.</p>
        </div>
        {esOwner && (
          <button type="button" className="btn btn--primary" onClick={abrirCrear}>
            Nuevo empleado
          </button>
        )}
      </header>

      {error && <div className="auth-error">{error}</div>}

      {loading ? (
        <div className="module-page__loading">Cargando empleados…</div>
      ) : empleados.length === 0 ? (
        <div className="module-page__empty">
          {esOwner
            ? 'Todavía no has registrado empleados. Crea el primero con el botón "Nuevo empleado".'
            : 'Este negocio todavía no tiene empleados registrados.'}
        </div>
      ) : (
        <div className="table-wrapper">
          <table className="data-table">
            <thead>
              <tr>
                <th>Nombre</th>
                <th>Teléfono</th>
                <th>Estado</th>
                {esOwner && <th aria-label="Acciones" />}
              </tr>
            </thead>
            <tbody>
              {empleados.map((empleado) => (
                <tr key={empleado.id}>
                  <td data-label="Nombre">{empleado.nombre}</td>
                  <td data-label="Teléfono">{empleado.telefono || '—'}</td>
                  <td data-label="Estado">
                    <EstadoBadge activo={empleado.activo} />
                  </td>
                  {esOwner && (
                    <td data-label="Acciones" className="data-table__actions">
                      <button type="button" className="btn btn--ghost" onClick={() => abrirEditar(empleado)}>
                        Editar
                      </button>
                      <button
                        type="button"
                        className="btn btn--ghost"
                        disabled={cambiandoEstadoId === empleado.id}
                        onClick={() => handleToggleActivo(empleado)}
                      >
                        {empleado.activo ? 'Desactivar' : 'Activar'}
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {modalAbierto && esOwner && (
        <Modal title={empleadoEditando ? 'Editar empleado' : 'Nuevo empleado'} onClose={cerrarModal}>
          <form className="form-grid" onSubmit={handleSubmit}>
            {formError && <div className="auth-error">{formError}</div>}

            <div className="auth-field">
              <label htmlFor="empleado-nombre">Nombre</label>
              <input
                id="empleado-nombre"
                type="text"
                value={form.nombre}
                onChange={(e) => setForm((f) => ({ ...f, nombre: e.target.value }))}
                required
              />
            </div>

            <div className="auth-field">
              <label htmlFor="empleado-telefono">Teléfono</label>
              <input
                id="empleado-telefono"
                type="tel"
                value={form.telefono}
                onChange={(e) => setForm((f) => ({ ...f, telefono: e.target.value }))}
              />
            </div>

            <button type="submit" className="auth-submit" disabled={guardando}>
              {guardando ? 'Guardando…' : empleadoEditando ? 'Guardar cambios' : 'Crear empleado'}
            </button>
          </form>
        </Modal>
      )}
    </section>
  );
}
