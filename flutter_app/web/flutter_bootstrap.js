{{flutter_js}}
{{flutter_build_config}}

// Sin service worker: el de Flutter (obsoleto) guardaba la versión anterior
// y había que recargar dos veces para ver una nueva. Los archivos se piden
// siempre al servidor (no-cache en _headers), así que no hace falta.
// También se quita el que ya tengan registrado los navegadores.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function (registros) {
    registros.forEach(function (registro) {
      registro.unregister();
    });
  });
}

_flutter.loader.load();
