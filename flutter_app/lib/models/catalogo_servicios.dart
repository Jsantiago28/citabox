// Servicios sugeridos para que el dueño los agregue de una vez, sin
// escribirlos uno a uno. Sin precio: lo pone el dueño al seleccionarlos.

class ServicioSugerido {
  const ServicioSugerido(this.nombre, this.duracionMinutos, this.icono);

  final String nombre;
  final int duracionMinutos;
  final String icono;
}

const catalogoBarberia = <ServicioSugerido>[
  ServicioSugerido('Corte de caballero', 30, 'tijera'),
  ServicioSugerido('Corte + barba', 45, 'tijera'),
  ServicioSugerido('Fade / degradado', 40, 'degradado'),
  ServicioSugerido('Corte con diseño', 50, 'diseno'),
  ServicioSugerido('Corte de niño', 25, 'nino'),
  ServicioSugerido('Barba (perfilado)', 20, 'barba'),
  ServicioSugerido('Afeitado con navaja', 30, 'navaja'),
  ServicioSugerido('Cerquillo / line up', 15, 'navaja'),
  ServicioSugerido('Cejas', 10, 'cejas'),
  ServicioSugerido('Lavado de cabello', 15, 'lavado'),
  ServicioSugerido('Tinte de barba', 30, 'tinte'),
  ServicioSugerido('Tinte de cabello', 60, 'tinte'),
  ServicioSugerido('Mascarilla facial', 25, 'facial'),
  ServicioSugerido('Black mask', 20, 'facial'),
  ServicioSugerido('Trenzas / twist', 90, 'trenzas'),
];

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
