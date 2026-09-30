import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { guardarRegistroPendiente, limpiarRegistroPendiente, registrarNegocioYOwner, signUp } from '../services/authService.js';
import { slugValido, slugify } from '../utils/slug.js';
import { useAuth } from '../hooks/useAuth.jsx';

const ESTADO_INICIAL = {
  negocioNombre: '',
  slug: '',
  slugEditadoManualmente: false,
  negocioTelefono: '',
  ownerNombre: '',
  ownerTelefono: '',
  email: '',
  password: '',
};

export default function Registro() {
  const [form, setForm] = useState(ESTADO_INICIAL);
  const [error, setError] = useState(null);
  const [avisoConfirmacion, setAvisoConfirmacion] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const navigate = useNavigate();
  const { refreshPerfil, session, perfil } = useAuth();

  function actualizarCampo(campo, valor) {
    setForm((prev) => {
      const siguiente = { ...prev, [campo]: valor };
      if (campo === 'negocioNombre' && !prev.slugEditadoManualmente) {
        siguiente.slug = slugify(valor);
      }
      if (campo === 'slug') {
        siguiente.slug = slugify(valor);
        siguiente.slugEditadoManualmente = true;
      }
      return siguiente;
    });
  }

  function validar() {
    if (!form.negocioNombre.trim()) return 'El nombre del negocio es obligatorio.';
    if (!slugValido(form.slug)) return 'El slug del negocio no es válido (usa minúsculas, números y guiones).';
    if (!form.ownerNombre.trim()) return 'Tu nombre es obligatorio.';

    // Una cuenta Auth que ya confirmó su correo puede llegar aquí sin
    // necesitar crear otra cuenta ni volver a introducir una contraseña.
    if (session && !perfil) return null;

    if (!/^\S+@\S+\.\S+$/.test(form.email.trim())) return 'Ingresa un correo válido.';
    if (form.password.length < 8) return 'La contraseña debe tener al menos 8 caracteres.';
    return null;
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);

    const mensajeValidacion = validar();
    if (mensajeValidacion) {
      setError(mensajeValidacion);
      return;
    }

    setEnviando(true);

    if (session && !perfil) {
      const { error: bootstrapError } = await registrarNegocioYOwner({
        negocioNombre: form.negocioNombre.trim(),
        negocioSlug: form.slug,
        negocioTelefono: form.negocioTelefono.trim(),
        ownerNombre: form.ownerNombre.trim(),
        ownerTelefono: form.ownerTelefono.trim(),
      });

      setEnviando(false);
      if (bootstrapError) {
        setError(
          bootstrapError.message?.toLowerCase().includes('slug')
            ? 'Ese slug ya está en uso. Elige otro.'
            : 'No se pudo completar el registro. Intenta de nuevo.'
        );
        return;
      }
      limpiarRegistroPendiente();
      await refreshPerfil(session.user.id);
      navigate('/dashboard', { replace: true });
      return;
    }

    guardarRegistroPendiente({
      negocioNombre: form.negocioNombre.trim(),
      slug: form.slug,
      negocioTelefono: form.negocioTelefono.trim(),
      ownerNombre: form.ownerNombre.trim(),
      ownerTelefono: form.ownerTelefono.trim(),
      email: form.email.trim(),
    });

    const { data: signUpData, error: signUpError } = await signUp(
      form.email.trim(),
      form.password
    );

    if (signUpError) {
      limpiarRegistroPendiente();
      setEnviando(false);
      setError(
        signUpError.message?.toLowerCase().includes('registered')
          ? 'Ya existe una cuenta con ese correo.'
          : 'No se pudo crear la cuenta. Intenta de nuevo.'
      );
      return;
    }

    if (!signUpData.session) {
      setEnviando(false);
      setAvisoConfirmacion(true);
      return;
    }

    const { error: bootstrapError } = await registrarNegocioYOwner({
      negocioNombre: form.negocioNombre.trim(),
      negocioSlug: form.slug,
      negocioTelefono: form.negocioTelefono.trim(),
      ownerNombre: form.ownerNombre.trim(),
      ownerTelefono: form.ownerTelefono.trim(),
    });

    setEnviando(false);
    if (bootstrapError) {
      setError(
        bootstrapError.message?.toLowerCase().includes('slug')
          ? 'Ese slug ya está en uso. Elige otro.'
          : 'No se pudo crear el negocio. Intenta de nuevo.'
      );
      return;
    }

    limpiarRegistroPendiente();
    await refreshPerfil(signUpData.user.id);
    navigate('/dashboard', { replace: true });
  }

  if (avisoConfirmacion) {
    return (
      <div className="auth-screen">
        <div className="auth-card">
          <h1 className="auth-card__title">Revisa tu correo</h1>
          <div className="auth-success">
            Te enviamos un enlace de confirmación a {form.email}. Confírmalo e
            inicia sesión para continuar con el registro de tu negocio.
          </div>
          <Link to="/login">Ir a iniciar sesión</Link>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-screen">
      <div className="auth-card">
        <h1 className="auth-card__title">Registra tu negocio</h1>
        <p className="auth-card__subtitle">Crea tu cuenta de propietario (OWNER).</p>

        {error && <div className="auth-error">{error}</div>}

        <form onSubmit={handleSubmit} noValidate>
          <div className="auth-field">
            <label htmlFor="negocioNombre">Nombre del negocio</label>
            <input
              id="negocioNombre"
              value={form.negocioNombre}
              onChange={(e) => actualizarCampo('negocioNombre', e.target.value)}
            />
          </div>

          <div className="auth-field">
            <label htmlFor="slug">Slug (link público)</label>
            <input
              id="slug"
              value={form.slug}
              onChange={(e) => actualizarCampo('slug', e.target.value)}
            />
            <span className="auth-field__hint">
              tuapp.com/reservar/{form.slug || 'tu-negocio'}
            </span>
          </div>

          <div className="auth-field">
            <label htmlFor="negocioTelefono">Teléfono del negocio</label>
            <input
              id="negocioTelefono"
              value={form.negocioTelefono}
              onChange={(e) => actualizarCampo('negocioTelefono', e.target.value)}
            />
          </div>

          <div className="auth-field">
            <label htmlFor="ownerNombre">Tu nombre (propietario)</label>
            <input
              id="ownerNombre"
              value={form.ownerNombre}
              onChange={(e) => actualizarCampo('ownerNombre', e.target.value)}
            />
          </div>

          <div className="auth-field">
            <label htmlFor="ownerTelefono">Tu teléfono</label>
            <input
              id="ownerTelefono"
              value={form.ownerTelefono}
              onChange={(e) => actualizarCampo('ownerTelefono', e.target.value)}
            />
          </div>

          {session && !perfil ? (
            <div className="auth-success">
              Tu cuenta ya está confirmada. Completa los datos del negocio para terminar el registro.
            </div>
          ) : (
            <>
              <div className="auth-field">
                <label htmlFor="email">Correo</label>
                <input
                  id="email"
                  type="email"
                  autoComplete="email"
                  value={form.email}
                  onChange={(e) => actualizarCampo('email', e.target.value)}
                />
              </div>

              <div className="auth-field">
                <label htmlFor="password">Contraseña</label>
                <input
                  id="password"
                  type="password"
                  autoComplete="new-password"
                  value={form.password}
                  onChange={(e) => actualizarCampo('password', e.target.value)}
                />
                <span className="auth-field__hint">Mínimo 8 caracteres.</span>
              </div>
            </>
          )}

          <button type="submit" className="auth-submit" disabled={enviando}>
            {enviando ? 'Creando…' : 'Crear mi negocio'}
          </button>
        </form>

        <div className="auth-links">
          <Link to="/login">Ya tengo cuenta</Link>
        </div>
      </div>
    </div>
  );
}
