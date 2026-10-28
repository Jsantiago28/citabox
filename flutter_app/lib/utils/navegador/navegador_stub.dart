/// Descarga un archivo de texto. Devuelve false si no se puede (no web).
bool descargarArchivo(String nombre, String contenido, String tipo) => false;

/// Lee un valor guardado en el navegador (null fuera de web).
String? leerLocal(String clave) => null;

/// Guarda un valor en el navegador (no hace nada fuera de web).
void guardarLocal(String clave, String valor) {}
