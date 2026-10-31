import 'dart:typed_data';

/// Descarga un archivo de texto. Devuelve false si no se puede (no web).
bool descargarArchivo(String nombre, String contenido, String tipo) => false;

/// Descarga un archivo binario (p. ej. .xlsx). false si no se puede (no web).
bool descargarBytes(String nombre, Uint8List bytes, String tipo) => false;

/// Lee un valor guardado en el navegador (null fuera de web).
String? leerLocal(String clave) => null;

/// Guarda un valor en el navegador (no hace nada fuera de web).
void guardarLocal(String clave, String valor) {}

/// Cómo se puede instalar la app en la pantalla de inicio.
enum Instalacion {
  /// Ya se abre como app (o no es web): no hay nada que ofrecer.
  instalada,

  /// El navegador permite instalar con un botón (Chrome, Edge, Brave).
  conBoton,

  /// iPhone o iPad: Compartir → Agregar a pantalla de inicio.
  iphone,

  /// Celular sin botón (otros navegadores): desde el menú del navegador.
  menuDelNavegador,
}

Instalacion estadoInstalacion() => Instalacion.instalada;

/// Muestra el aviso de instalación del navegador. true si la instaló.
Future<bool> instalarApp() async => false;

/// Avisa cuando cambia la posibilidad de instalar (el aviso llega tarde).
void alCambiarInstalacion(void Function() alCambiar) {}
