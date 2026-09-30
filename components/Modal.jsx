import { useEffect } from 'react';

// Modal genérico reutilizable. Cierra con la X, con click en el
// overlay o con la tecla Escape. No maneja foco avanzado (fuera de
// alcance de esta fase) pero es funcional y accesible a nivel básico.
export default function Modal({ title, onClose, children }) {
  useEffect(() => {
    function handleKeyDown(event) {
      if (event.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose]);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(event) => event.stopPropagation()}
      >
        <div className="modal-card__header">
          <h2 className="modal-card__title">{title}</h2>
          <button
            type="button"
            className="modal-card__close"
            onClick={onClose}
            aria-label="Cerrar"
          >
            ×
          </button>
        </div>
        <div className="modal-card__body">{children}</div>
      </div>
    </div>
  );
}
