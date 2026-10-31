import 'package:flutter/material.dart';

import '../theme.dart';

/// Ícono de Citabox: calendario dorado con la cita confirmada, sobre un
/// cuadro negro redondeado. Es la misma figura de los íconos de la web
/// (`tool/generar_iconos_test.dart`).
class IconoCitabox extends StatelessWidget {
  const IconoCitabox({super.key, this.tamano = 24});

  final double tamano;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: tamano,
      child: const CustomPaint(painter: PintorIconoCitabox()),
    );
  }
}

/// Dibuja el ícono en un cuadro de 100 × 100 escalado al tamaño disponible.
///
/// [conFondo] pinta el cuadro negro; [redondeado] le da las esquinas del
/// ícono de la app; [escala] encoge el símbolo (íconos "maskable", que el
/// sistema recorta en círculo).
class PintorIconoCitabox extends CustomPainter {
  const PintorIconoCitabox({
    this.conFondo = true,
    this.redondeado = true,
    this.escala = 1,
  });

  final bool conFondo;
  final bool redondeado;
  final double escala;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas.scale(s);

    if (conFondo) {
      final fondo = Paint()..color = Marca.negro;
      const cuadro = Rect.fromLTWH(0, 0, 100, 100);
      if (redondeado) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(cuadro, const Radius.circular(22)),
          fondo,
        );
      } else {
        canvas.drawRect(cuadro, fondo);
      }
    }

    canvas.translate(50, 50);
    canvas.scale(escala);
    canvas.translate(-50, -50);

    final relleno = Paint()..color = Marca.dorado;
    final trazo = Paint()
      ..color = Marca.dorado
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    // Argollas, cuerpo y franja superior del calendario.
    for (final x in [34.0, 59.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 18, 7, 16),
          const Radius.circular(3.5),
        ),
        relleno,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(21, 27, 58, 53),
        const Radius.circular(10),
      ),
      trazo,
    );
    canvas.drawLine(const Offset(21, 42), const Offset(79, 42), trazo);

    // Visto: la cita confirmada.
    canvas.drawPath(
      Path()
        ..moveTo(37, 60)
        ..lineTo(46, 69)
        ..lineTo(63, 52),
      Paint()
        ..color = Marca.doradoClaro
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(PintorIconoCitabox old) =>
      old.conFondo != conFondo ||
      old.redondeado != redondeado ||
      old.escala != escala;
}

/// Ícono + "Citabox" ("box" en dorado).
class LogoCitabox extends StatelessWidget {
  const LogoCitabox({super.key, this.claro = true, this.tamano = 20});

  /// Texto blanco (sobre fondo oscuro) o del color del texto.
  final bool claro;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconoCitabox(tamano: tamano * 1.5),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            text: 'Cita',
            children: [
              TextSpan(
                text: 'box',
                style: TextStyle(
                  color: claro ? Marca.doradoClaro : const Color(0xFFB08A36),
                ),
              ),
            ],
          ),
          style: TextStyle(
            color: claro ? Colors.white : Marca.texto,
            fontSize: tamano,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

/// Logo, subtítulo y lema sobre fondo negro (login y registro).
class EncabezadoMarca extends StatelessWidget {
  const EncabezadoMarca({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        LogoCitabox(tamano: 30),
        SizedBox(height: 10),
        Text(
          'Agenda • Apartados • Clientes • Crece tu negocio',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        SizedBox(height: 6),
        Text(
          'Más que una agenda, es el control de tu negocio',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Marca.doradoClaro,
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// Botón principal dorado del modelo ("Reservar cita", "Pagar", …).
class BotonDorado extends StatelessWidget {
  const BotonDorado({
    super.key,
    required this.etiqueta,
    required this.onPressed,
  });

  final String etiqueta;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final activo = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: activo ? Marca.degradadoDorado : null,
        color: activo ? null : Marca.borde,
        borderRadius: BorderRadius.circular(10),
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Marca.negro,
          shadowColor: Colors.transparent,
          textStyle: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        child: Text(etiqueta),
      ),
    );
  }
}
