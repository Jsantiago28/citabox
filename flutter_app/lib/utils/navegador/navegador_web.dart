import 'dart:js_interop';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSString> partes, _OpcionesBlob opciones);
}

extension type _OpcionesBlob._(JSObject _) implements JSObject {
  external factory _OpcionesBlob({String type});
}

extension type _Enlace._(JSObject _) implements JSObject {
  external set href(String valor);
  external set download(String valor);
  external void click();
}

@JS('URL.createObjectURL')
external String _crearUrl(_Blob blob);

@JS('URL.revokeObjectURL')
external void _liberarUrl(String url);

@JS('document.createElement')
external _Enlace _crearElemento(String etiqueta);

@JS('localStorage.getItem')
external String? _leer(String clave);

@JS('localStorage.setItem')
external void _guardar(String clave, String valor);

bool descargarArchivo(String nombre, String contenido, String tipo) {
  try {
    final blob = _Blob([contenido.toJS].toJS, _OpcionesBlob(type: tipo));
    final url = _crearUrl(blob);
    final enlace = _crearElemento('a')
      ..href = url
      ..download = nombre;
    enlace.click();
    _liberarUrl(url);
    return true;
  } catch (_) {
    return false;
  }
}

String? leerLocal(String clave) {
  try {
    return _leer(clave);
  } catch (_) {
    return null; // modo privado o almacenamiento bloqueado
  }
}

void guardarLocal(String clave, String valor) {
  try {
    _guardar(clave, valor);
  } catch (_) {
    // Sin almacenamiento: el enlace "Mi cita" sigue en pantalla.
  }
}
