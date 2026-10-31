import 'dart:js_interop';
import 'dart:typed_data';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> partes, _OpcionesBlob opciones);
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

bool descargarArchivo(String nombre, String contenido, String tipo) =>
    _descargar(nombre, contenido.toJS, tipo);

bool descargarBytes(String nombre, Uint8List bytes, String tipo) =>
    _descargar(nombre, bytes.toJS, tipo);

bool _descargar(String nombre, JSAny contenido, String tipo) {
  try {
    final blob = _Blob([contenido].toJS, _OpcionesBlob(type: tipo));
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

/// Cómo se puede instalar la app en la pantalla de inicio.
enum Instalacion { instalada, conBoton, iphone, menuDelNavegador }

extension type _Citabox._(JSObject _) implements JSObject {
  external JSObject? get aviso;
  external bool? get instalada;
}

@JS('citabox')
external _Citabox? get _citabox;

@JS('citaboxInstalar')
external JSPromise<JSString> _instalar();

@JS('matchMedia')
external _ConsultaMedia _matchMedia(String consulta);

extension type _ConsultaMedia._(JSObject _) implements JSObject {
  external bool get matches;
}

@JS('navigator.userAgent')
external String get _agente;

@JS('navigator.maxTouchPoints')
external int? get _puntosTactiles;

@JS('navigator.standalone')
external bool? get _standaloneIos;

@JS('window.addEventListener')
external void _escuchar(String evento, JSFunction funcion);

Instalacion estadoInstalacion() {
  try {
    if (_matchMedia('(display-mode: standalone)').matches ||
        _standaloneIos == true ||
        _citabox?.instalada == true) {
      return Instalacion.instalada;
    }
    if (_citabox?.aviso != null) return Instalacion.conBoton;
    final agente = _agente;
    // iPadOS se presenta como Mac; se distingue por la pantalla táctil.
    final esIos =
        RegExp('iPhone|iPad|iPod').hasMatch(agente) ||
        (agente.contains('Macintosh') && (_puntosTactiles ?? 0) > 1);
    if (esIos) return Instalacion.iphone;
    if (agente.contains('Android')) return Instalacion.menuDelNavegador;
    return Instalacion.instalada; // computadora sin botón: no se insiste
  } catch (_) {
    return Instalacion.instalada;
  }
}

Future<bool> instalarApp() async {
  try {
    return (await _instalar().toDart).toDart == 'accepted';
  } catch (_) {
    return false;
  }
}

void alCambiarInstalacion(void Function() alCambiar) {
  try {
    _escuchar('citabox-instalacion', alCambiar.toJS);
  } catch (_) {}
}
