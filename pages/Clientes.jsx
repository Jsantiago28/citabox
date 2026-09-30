import { useEffect, useState } from 'react';
import { useAuth } from '../hooks/useAuth.jsx';
import Modal from '../components/Modal.jsx';
import EstadoBadge from '../components/EstadoBadge.jsx';
import {
  actualizarCliente,
  cambiarEstadoCliente,
  crearCliente,
  listarClientes,
} from '../services/clientesService.js';

const FORM_VACIO = { nombre: '', telefono: '', email: '', notas: '' };

export default function Clientes() {
  const { negocio, rol } = useAuth();
  const negocioId = negocio?.id ?? null;
  const esOwner = rol === 'OWNER';

  const [clientes, setClientes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [modalAbierto, setModalAbierto] = useState(false);
  const [clienteEditando, setClienteEditando] = useState(null);
  const [form, setForm] = useState(FORM_VACIO);
  const [guardando, setGuardando] = useState(false);
  const [formError, setFormError] = useState('');
  const [cambiandoEstadoId, setCambiandoEstadoId] = useState(null);

  useEffect(() => {
    if (!negocioId) return;
    cargarClientes();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [negocioId]);

  async function cargarClientes() {
    setLoading(true);
    setError('');
    const { data, error: err } = await listarClientes(negocioId);
    if (err) {
      setError('No se pudieron cargar los clientes. Intenta de nuevo.');
      setClientes([]);
    } else {
      setClientes(data || []);
    }
    setLoading(false);
  }

  function abrirCrear() {
    setClienteEditando(null);
    setForm(FORM_VACIO);
    setFormError('');
    setModalAbierto(true);
  }

  function abrirEditar(cliente) {
    setClienteEditando(cliente);
    setForm({
      nombre: cliente.nombre,
      telefono: cliente.telefono || '',
      email: cliente.email || '',
      notas: cliente.notas || '',
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
    if (!nombre) {
      setFormError('El nombre es obligatorio.');
      return;
    }

    setGuardando(true);
    setFormError('');

    const payload = {
      nombre,
      telefono: form.telefono.trim(),
      email: form.email.trim(),
      notas: form.notas.trim(),
    };

    const { error: err } = clienteEditando
      ? await actualizarCliente(negocioId, clienteEditando.id, payload)
      : await crearCliente(negocioId, payload);

    setGuardando(false);

    if (err) {
      setFormError('No se pudo guardar el cliente. Intenta de nuevo.');
      return;
    }

    setModalAbierto(false);
    await cargarClientes();
  }

  async function handleToggleActivo(cliente) {
    setCambiandoEstadoId(cliente.id);
    const { error: err } = await cambiarEstadoCliente(negocioId, cliente.id, !cliente.activo);
    setCambiandoEstadoId(null);
    if (err) {
      setError('No se pudo actualizar el estado del cliente.');
      return;
    }
    await cargarClientes();
  }

  return (
    <section className="module-page">
      <header className="module-page__header">
        <div>
          <h1 className="module-page__title">Clientes</h1>
          <p className="module-page__subtitle">Listado y ficha de clientes del negocio.</p>
        </div>
        <button type="button" className="btn btn--primary" onClick={abrirCrear}>
          Nuevo cliente
        </button>
      </header>

      {error && <div className="auth-error">{error}</div>}

      {loading ? (
        <div className="module-page__loading">Cargando clientes…</div>
      ) : clientes.length === 0 ? (
        <div className="module-page__empty">
          Todavía no hay clientes registrados. Crea el primero con el botón "Nuevo cliente".
        </div>
      ) : (
        <div className="table-wrapper">
          <table className="data-table">
            <thead>
              <tr>
                <th>Nombre</th>
                <th>Teléfono</th>
                <th>Email</th>
                <th>Estado</th>
                <th aria-label="Acciones" />
              </tr>
            </thead>
            <tbody>
              {clientes.map((cliente) => (
                <tr key={cliente.id}>
                  <td data-label="Nombre">{cliente.nombre}</td>
                  <td data-label="Teléfono">{cliente.telefono || '—'}</td>
                  <td data-label="Email">{cliente.email || '—'}</td>
                  <td data-label="Estado">
                    <EstadoBadge activo={cliente.activo} />
                  </td>
                  <td data-label="Acciones" className="data-table__actions">
                    <button type="button" className="btn btn--ghost" onClick={() => abrirEditar(cliente)}>
                      Editar
                    </button>
                    {esOwner && (
                      <button
                        type="button"
                        className="btn btn--ghost"
                        disabled={cambiandoEstadoId === cliente.id}
                        onClick={() => handleToggleActivo(cliente)}
                      >
                        {cliente.activo ? 'Desactivar' : 'Activar'}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {modalAbierto && (
        <Modal title={clienteEditando ? 'Editar cliente' : 'Nuevo cliente'} onClose={cerrarModal}>
          <form className="form-grid" onSubmit={handleSubmit}>
            {formError && <div className="auth-error">{formError}</div>}

            <div className="auth-field">
              <label htmlFor="cliente-nombre">Nombre</label>
              <input
                id="cliente-nombre"
                type="text"
                value={form.nombre}
                onChange={(e) => setForm((f) => ({ ...f, nombre: e.target.value }))}
                required
              />
            </div>

            <div className="form-grid__row">
              <div className="auth-field">
                <label htmlFor="cliente-telefono">Teléfono</label>
                <input
                  id="cliente-telefono"
                  type="tel"
                  value={form.telefono}
                  onChange={(e) => setForm((f) => ({ ...f, telefono: e.target.value }))}
                />
              </div>

              <div className="auth-field">
                <label htmlFor="cliente-email">Email</label>
                <input
                  id="cliente-email"
                  type="email"
                  value={form.email}
                  onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))}
                />
              </div>
            </div>

            <div className="auth-field">
              <label htmlFor="cliente-notas">Notas</label>
              <input
                id="cliente-notas"
                type="text"
                value={form.notas}
                onChange={(e) => setForm((f) => ({ ...f, notas: e.target.value }))}
              />
            </div>

            <button type="submit" className="auth-submit" disabled={guardando}>
              {guardando ? 'Guardando…' : clienteEditando ? 'Guardar cambios' : 'Crear cliente'}
            </button>
          </form>
        </Modal>
      )}
    </section>
  );
}
