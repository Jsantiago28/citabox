import 'package:flutter/material.dart';

import '../theme.dart';

class ProximamentePage extends StatelessWidget {
  const ProximamentePage({
    super.key,
    required this.titulo,
    required this.icono,
    required this.descripcion,
  });

  final String titulo;
  final IconData icono;
  final String descripcion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Marca.negro,
                child: Icon(icono, color: Marca.doradoClaro, size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                titulo,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                descripcion,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Marca.textoSuave),
              ),
              const SizedBox(height: 12),
              const Chip(label: Text('Próximamente')),
            ],
          ),
        ),
      ),
    );
  }
}
