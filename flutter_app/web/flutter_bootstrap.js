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

// Quita la pantalla de carga de index.html cuando la app ya dibujó.
function quitarPantallaDeCarga() {
  var cargando = document.getElementById('cargando');
  if (!cargando) return;
  cargando.classList.add('listo');
  setTimeout(function () {
    cargando.remove();
  }, 350);
}

// Si en 30 s la app no dibujó (conexión muy lenta o un error), se avisa en
// vez de dejar la pantalla de carga sola.
setTimeout(function () {
  var cargando = document.getElementById('cargando');
  if (!cargando || cargando.classList.contains('listo')) return;
  var aviso = document.createElement('p');
  aviso.style.cssText = 'color:#fff;max-width:260px;text-align:center;margin:0';
  aviso.textContent =
    'Está tardando más de lo normal. Revisa tu conexión y recarga la página.';
  cargando.appendChild(aviso);
}, 30000);

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    var appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    requestAnimationFrame(function () {
      requestAnimationFrame(quitarPantallaDeCarga);
    });
  },
});
