import 'package:flutter/material.dart';

// Íconos de los servicios. En la base se guarda solo la clave
// (servicios.icono, migración 012); sin clave se usa la tijera.

const iconoServicioPorDefecto = 'tijera';

const iconosServicio = <String, IconData>{
  'tijera': Icons.content_cut,
  'secador': Icons.air,
  'rolos': Icons.waves,
  'plancha': Icons.iron_outlined,
  'peinado': Icons.face_retouching_natural,
  'tinte': Icons.palette_outlined,
  'raiz': Icons.format_color_fill,
  'mechas': Icons.auto_awesome,
  'balayage': Icons.gradient,
  'tratamiento': Icons.spa_outlined,
  'keratina': Icons.water_drop_outlined,
  'desrizado': Icons.straighten,
  'trenzas': Icons.gesture,
  'maquillaje': Icons.brush_outlined,
  'manicure': Icons.back_hand_outlined,
  'pedicure': Icons.airline_seat_legroom_extra,
  'unas': Icons.diamond_outlined,
  'cejas': Icons.remove_red_eye_outlined,
  'barba': Icons.face,
  'navaja': Icons.horizontal_rule,
  'nino': Icons.child_care,
  'diseno': Icons.draw_outlined,
  'degradado': Icons.blur_linear,
  'lavado': Icons.shower_outlined,
  'facial': Icons.sentiment_satisfied_alt_outlined,
};

IconData iconoServicio(String? clave) =>
    iconosServicio[clave] ?? iconosServicio[iconoServicioPorDefecto]!;
