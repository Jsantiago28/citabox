import 'package:flutter/material.dart';

import '../theme.dart';

/// Tijeras doradas + "Barbería PRO", como en el modelo visual.
class LogoBarberia extends StatelessWidget {
  const LogoBarberia({super.key, this.claro = true, this.tamano = 20});

  final bool claro;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.content_cut, color: Marca.dorado, size: tamano + 4),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            text: 'Barbería ',
            children: const [
              TextSpan(
                text: 'PRO',
                style: TextStyle(color: Marca.dorado),
              ),
            ],
          ),
          style: TextStyle(
            color: claro ? Colors.white : Marca.texto,
            fontSize: tamano,
            fontWeight: FontWeight.w700,
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
        LogoBarberia(tamano: 30),
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
