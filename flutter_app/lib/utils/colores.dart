import 'package:flutter/material.dart';

/// '#C9A24B' o 'C9A24B' → Color. Devuelve null si el formato no es válido.
Color? colorDesdeHex(String texto) {
  final limpio = texto.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(limpio)) return null;
  return Color(int.parse('FF$limpio', radix: 16));
}
