import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/navegador.dart';
import 'logo_marca.dart';

/// Tarjeta para poner Citabox en la pantalla de inicio del celular.
///
/// Con Chrome, Edge o Brave basta un botón; en iPhone se muestran los dos
/// pasos (Compartir → Agregar a pantalla de inicio). No aparece si ya está
/// instalada o si el usuario la cerró ("No ahora").
class TarjetaInstalar extends StatefulWidget {
  const TarjetaInstalar({
    super.key,
    this.estado = estadoInstalacion,
    this.instalar = instalarApp,
    this.alCambiar = alCambiarInstalacion,
    this.leer = leerLocal,
    this.guardar = guardarLocal,
  });

  /// Inyectables en pruebas; por defecto el navegador real.
  final Instalacion Function() estado;
  final Future<bool> Function() instalar;
  final void Function(void Function()) alCambiar;
  final String? Function(String clave) leer;
  final void Function(String clave, String valor) guardar;

  static const claveOculta = 'citabox.instalar.oculta';

  @override
  State<TarjetaInstalar> createState() => _TarjetaInstalarState();
}

class _TarjetaInstalarState extends State<TarjetaInstalar> {
  late Instalacion _estado = widget.estado();
  late bool _oculta = widget.leer(TarjetaInstalar.claveOculta) == '1';

  @override
  void initState() {
    super.initState();
    // Chrome puede avisar que se puede instalar después de que cargó la app.
    widget.alCambiar(() {
      if (mounted) setState(() => _estado = widget.estado());
    });
  }

  void _ocultar() {
    widget.guardar(TarjetaInstalar.claveOculta, '1');
    setState(() => _oculta = true);
  }

  Future<void> _instalar() async {
    final instalada = await widget.instalar();
    if (!mounted) return;
    setState(() => _estado = widget.estado());
    if (instalada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listo: Citabox quedó en tu pantalla de inicio.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_oculta || _estado == Instalacion.instalada) {
      return const SizedBox.shrink();
    }

    final (titulo, detalle) = switch (_estado) {
      Instalacion.conBoton => (
        'Instala Citabox en tu celular',
        'Ábrela con un toque desde tu pantalla de inicio, a pantalla '
            'completa y sin buscar el enlace.',
      ),
      Instalacion.iphone => (
        'Agrega Citabox a tu pantalla de inicio',
        'Así la abres como una app, a pantalla completa.',
      ),
      _ => (
        'Agrega Citabox a tu pantalla de inicio',
        'Así la abres como una app, a pantalla completa.',
      ),
    };

    final tarjeta = Card(
      key: const Key('tarjeta-instalar'),
      color: Marca.negro,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconoCitabox(tamano: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detalle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('instalar-cerrar'),
                  tooltip: 'No ahora',
                  onPressed: _ocultar,
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 12),
            switch (_estado) {
              Instalacion.conBoton => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: BotonDorado(
                    key: const Key('instalar-boton'),
                    etiqueta: 'Instalar Citabox',
                    onPressed: _instalar,
                  ),
                ),
              ),
              Instalacion.iphone => const _Pasos(
                pasos: [
                  (Icons.ios_share, 'Toca Compartir, abajo en la pantalla.'),
                  (
                    Icons.add_box_outlined,
                    'Elige "Agregar a pantalla de inicio" y luego "Agregar".',
                  ),
                ],
              ),
              _ => const _Pasos(
                pasos: [
                  (Icons.more_vert, 'Toca el menú ⋮ del navegador.'),
                  (
                    Icons.add_to_home_screen,
                    'Elige "Instalar app" o "Agregar a la pantalla de inicio".',
                  ),
                ],
              ),
            },
          ],
        ),
      ),
    );
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: tarjeta);
  }
}

class _Pasos extends StatelessWidget {
  const _Pasos({required this.pasos});

  final List<(IconData, String)> pasos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < pasos.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, right: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: Marca.dorado,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Marca.negro,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(pasos[i].$1, color: Marca.doradoClaro, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pasos[i].$2,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
