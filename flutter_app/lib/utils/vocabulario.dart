import 'package:flutter/widgets.dart';

/// Tipo de negocio (columna `negocios.tipo`) y las palabras que usa la app
/// para él: un spa no tiene "barberos" sino "terapeutas".
enum TipoNegocio {
  barberia('barberia', 'Barbería', 'Barbero', 'Barberos', 'barbería'),
  salon('salon', 'Salón de belleza', 'Estilista', 'Estilistas', 'salón'),
  unas('unas', 'Salón de uñas', 'Manicurista', 'Manicuristas', 'salón'),
  spa('spa', 'Spa', 'Terapeuta', 'Terapeutas', 'spa'),
  consultorio(
    'consultorio',
    'Consultorio',
    'Profesional',
    'Profesionales',
    'consultorio',
  ),
  otro('otro', 'Otro negocio', 'Profesional', 'Profesionales', 'negocio');

  const TipoNegocio(
    this.codigo,
    this.nombre,
    this.profesional,
    this.profesionales,
    this.negocio,
  );

  /// Valor guardado en la base de datos.
  final String codigo;

  /// Para elegirlo: "Salón de belleza".
  final String nombre;

  /// "Barbero", "Estilista"… (con mayúscula, como etiqueta).
  final String profesional;
  final String profesionales;

  /// Cómo se nombra el negocio en una frase: "tu barbería", "tu salón".
  final String negocio;

  /// Los que no se reconocen (o vacíos) son barbería, el tipo original.
  static TipoNegocio desdeCodigo(Object? codigo) => TipoNegocio.values
      .firstWhere((t) => t.codigo == codigo, orElse: () => barberia);

  /// "barbero", "estilista"… para el medio de una frase.
  String get profesionalMin => profesional.toLowerCase();
  String get profesionalesMin => profesionales.toLowerCase();

  /// El catálogo sugerido de servicios que le corresponde.
  bool get catalogoSalon => this == salon || this == unas || this == spa;
}

/// Da el tipo de negocio a las pantallas de debajo. Sin él, se usa
/// barbería (por ejemplo, en pruebas).
class Vocabulario extends InheritedWidget {
  const Vocabulario({super.key, required this.tipo, required super.child});

  final TipoNegocio tipo;

  static TipoNegocio of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Vocabulario>()?.tipo ??
      TipoNegocio.barberia;

  @override
  bool updateShouldNotify(Vocabulario oldWidget) => oldWidget.tipo != tipo;
}

/// Guarda el tipo de negocio activo encima del Navigator (ver `app.dart`),
/// para que diálogos y pantallas apiladas usen las mismas palabras. El
/// panel del negocio y la página de reservas lo fijan al cargar.
class TipoNegocioHost extends StatefulWidget {
  const TipoNegocioHost({super.key, required this.child});

  final Widget child;

  /// Cambia el tipo activo; no hace nada si no hay host (pruebas).
  static void fijar(BuildContext context, TipoNegocio tipo) =>
      context.findAncestorStateOfType<_TipoNegocioHostState>()?._fijar(tipo);

  @override
  State<TipoNegocioHost> createState() => _TipoNegocioHostState();
}

class _TipoNegocioHostState extends State<TipoNegocioHost> {
  TipoNegocio _tipo = TipoNegocio.barberia;

  void _fijar(TipoNegocio tipo) {
    if (tipo != _tipo && mounted) setState(() => _tipo = tipo);
  }

  @override
  Widget build(BuildContext context) =>
      Vocabulario(tipo: _tipo, child: widget.child);
}
