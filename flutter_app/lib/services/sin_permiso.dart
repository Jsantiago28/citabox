/// RLS no lanza error cuando bloquea un UPDATE o DELETE: simplemente deja
/// 0 filas afectadas. Los repositorios piden `.select('id')` y usan
/// [exigirFilas] para no reportar como guardado algo que no se guardó.
library;

const mensajeSinPermiso = 'No tienes permiso o el registro ya no existe.';

/// El UPDATE/DELETE no afectó ninguna fila (RLS o registro borrado).
class SinPermisoException implements Exception {
  const SinPermisoException();

  String get mensaje => mensajeSinPermiso;

  @override
  String toString() => mensajeSinPermiso;
}

/// Lanza [SinPermisoException] si [filas] viene vacío.
void exigirFilas(List<dynamic> filas) {
  if (filas.isEmpty) throw const SinPermisoException();
}

/// Mensaje para mostrar: el de [SinPermisoException] o [porDefecto].
String mensajeDeError(Object error, String porDefecto) =>
    error is SinPermisoException ? error.mensaje : porDefecto;
