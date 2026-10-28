/// PostgREST corta cada respuesta (1000 filas por defecto). Para listas
/// completas se pide página a página con `.range(desde, hasta)`.
library;

const tamanoPagina = 1000;

/// Llama a [pagina] con rangos consecutivos (`desde`, `hasta` inclusivo)
/// hasta que una respuesta trae menos de [tamano] filas.
///
/// La consulta debe tener un orden total (p. ej. terminar en `.order('id')`)
/// para que las páginas no se solapen.
Future<List<Map<String, dynamic>>> leerTodasLasPaginas(
  Future<List<Map<String, dynamic>>> Function(int desde, int hasta) pagina, {
  int tamano = tamanoPagina,
}) async {
  final filas = <Map<String, dynamic>>[];
  for (var desde = 0; ; desde += tamano) {
    final rows = await pagina(desde, desde + tamano - 1);
    filas.addAll(rows);
    if (rows.length < tamano) break;
  }
  return filas;
}
