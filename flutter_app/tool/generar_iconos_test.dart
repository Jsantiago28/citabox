// Genera los íconos de la web (favicon, PWA y "maskable") a partir de
// PintorIconoCitabox, para que coincidan con el logo de la app.
//
//   flutter test tool/generar_iconos_test.dart
//
// No corre en el CI (está fuera de test/): se usa solo al cambiar el logo.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:barberiapro/widgets/logo_marca.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _guardar(String ruta, int lado, PintorIconoCitabox pintor) async {
  final grabadora = ui.PictureRecorder();
  pintor.paint(Canvas(grabadora), Size.square(lado.toDouble()));
  final imagen = await grabadora.endRecording().toImage(lado, lado);
  final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
  File(ruta).writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  testWidgets('genera los íconos de web/', (tester) async {
    await tester.runAsync(() async {
      const normal = PintorIconoCitabox();
      // Los "maskable" los recorta el sistema (círculo, gota…): fondo
      // completo y símbolo dentro de la zona segura del 80 %.
      const maskable = PintorIconoCitabox(redondeado: false, escala: 0.72);

      await _guardar('web/favicon.png', 32, normal);
      await _guardar('web/icons/Icon-192.png', 192, normal);
      await _guardar('web/icons/Icon-512.png', 512, normal);
      await _guardar('web/icons/Icon-maskable-192.png', 192, maskable);
      await _guardar('web/icons/Icon-maskable-512.png', 512, maskable);
      // iPhone pone sus propias esquinas: cuadro completo, sin transparencias.
      await _guardar(
        'web/icons/apple-touch-icon.png',
        180,
        const PintorIconoCitabox(redondeado: false),
      );
    });
  });
}
