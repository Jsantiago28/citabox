import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pantalla de formulario (entrar, registrarse…): ocupa todo el espacio,
/// centra el contenido si cabe y, si no, se desplaza con la barra visible.
/// Así en la PC la rueda del ratón funciona aunque el puntero esté sobre el
/// fondo y no sobre la tarjeta.
class PantallaDesplazable extends StatefulWidget {
  const PantallaDesplazable({
    super.key,
    this.padding = const EdgeInsets.all(20),
    required this.child,
  });

  final EdgeInsets padding;
  final Widget child;

  @override
  State<PantallaDesplazable> createState() => _PantallaDesplazableState();
}

class _PantallaDesplazableState extends State<PantallaDesplazable> {
  final _controlador = ScrollController();

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, limites) => Scrollbar(
          controller: _controlador,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controlador,
            padding: widget.padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: math.max(
                  0,
                  limites.maxWidth - widget.padding.horizontal,
                ),
                minHeight: math.max(
                  0,
                  limites.maxHeight - widget.padding.vertical,
                ),
              ),
              child: Center(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
