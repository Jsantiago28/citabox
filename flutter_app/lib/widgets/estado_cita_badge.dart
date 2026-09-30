import 'package:flutter/material.dart';

import '../models/cita.dart';
import '../theme.dart';

Color colorEstadoCita(EstadoCita estado) => switch (estado) {
  EstadoCita.llego || EstadoCita.completada => Marca.verde,
  EstadoCita.noVino => Marca.rojo,
  EstadoCita.confirmada => Marca.azul,
  EstadoCita.pendiente => Marca.naranja,
  EstadoCita.cancelada => Marca.textoSuave,
};

class EstadoCitaBadge extends StatelessWidget {
  const EstadoCitaBadge({super.key, required this.estado});

  final EstadoCita estado;

  @override
  Widget build(BuildContext context) {
    final color = colorEstadoCita(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado.etiqueta,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AvatarIniciales extends StatelessWidget {
  const AvatarIniciales({super.key, required this.texto, this.radio = 18});

  final String texto;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radio,
      backgroundColor: Marca.negro,
      child: Text(
        texto,
        style: TextStyle(
          color: Marca.doradoClaro,
          fontWeight: FontWeight.w700,
          fontSize: radio * 0.7,
        ),
      ),
    );
  }
}
