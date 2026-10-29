import 'package:flutter/material.dart';

import '../legal/textos_legales.dart';
import '../theme.dart';

/// Página pública con un texto legal (`#/terminos`, `#/privacidad`).
class LegalPage extends StatelessWidget {
  const LegalPage.privacidad({super.key})
    : titulo = tituloPrivacidad,
      secciones = seccionesPrivacidad;

  const LegalPage.terminos({super.key})
    : titulo = tituloTerminos,
      secciones = seccionesTerminos;

  final String titulo;
  final List<SeccionLegal> secciones;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Marca.dorado.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    avisoBorradorLegal,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 16),
                Text(titulo, style: tema.headlineSmall),
                for (final s in secciones) ...[
                  const SizedBox(height: 20),
                  Text(
                    s.titulo,
                    style: tema.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final p in s.parrafos) ...[
                    const SizedBox(height: 6),
                    Text(p, style: tema.bodyMedium),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
