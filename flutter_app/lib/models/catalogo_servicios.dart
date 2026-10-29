// Servicios sugeridos para que el dueño los agregue de una vez, sin
// escribirlos uno a uno. Sin precio: lo pone el dueño al seleccionarlos.

class ServicioSugerido {
  const ServicioSugerido(this.nombre, this.duracionMinutos, this.icono);

  final String nombre;
  final int duracionMinutos;
  final String icono;
}

const catalogoSalon = <ServicioSugerido>[
  ServicioSugerido('Lavado y blower (pelo corto)', 45, 'secador'),
  ServicioSugerido('Lavado y blower (pelo largo)', 60, 'secador'),
  ServicioSugerido('Lavado con rolos', 60, 'rolos'),
  ServicioSugerido('Planchado', 45, 'plancha'),
  ServicioSugerido('Corte de dama', 45, 'tijera'),
  ServicioSugerido('Corte de puntas', 20, 'tijera'),
  ServicioSugerido('Peinado / recogido para evento', 60, 'peinado'),
  ServicioSugerido('Tinte completo', 120, 'tinte'),
  ServicioSugerido('Retoque de raíz', 90, 'raiz'),
  ServicioSugerido('Mechas / reflejos', 150, 'mechas'),
  ServicioSugerido('Balayage', 180, 'balayage'),
  ServicioSugerido('Tratamiento / mascarilla hidratante', 45, 'tratamiento'),
  ServicioSugerido('Keratina / alisado', 180, 'keratina'),
  ServicioSugerido('Desrizado (relaxer)', 120, 'desrizado'),
  ServicioSugerido('Trenzas', 120, 'trenzas'),
  ServicioSugerido('Maquillaje', 60, 'maquillaje'),
  ServicioSugerido('Manicure', 45, 'manicure'),
  ServicioSugerido('Pedicure', 60, 'pedicure'),
  ServicioSugerido('Uñas acrílicas / gel', 90, 'unas'),
  ServicioSugerido('Diseño de cejas', 20, 'cejas'),
];
