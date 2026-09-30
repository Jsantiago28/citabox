import 'package:flutter/material.dart';

// Paleta del modelo visual de Barbería PRO: negro, dorado y blanco.
abstract final class Marca {
  static const negro = Color(0xFF141414);
  static const lateral = Color(0xFF1A1B1D);
  static const lateralActivo = Color(0xFF2A2B2E);
  static const dorado = Color(0xFFC9A24B);
  static const doradoClaro = Color(0xFFE3C77E);
  static const fondo = Color(0xFFF4F4F2);
  static const borde = Color(0xFFE6E4DF);
  static const texto = Color(0xFF1B1B1B);
  static const textoSuave = Color(0xFF6E6E6A);
  static const verde = Color(0xFF2E9E5B);
  static const rojo = Color(0xFFD64545);
  static const naranja = Color(0xFFE0922B);
  static const azul = Color(0xFF3B6FD8);

  static const degradadoDorado = LinearGradient(
    colors: [doradoClaro, dorado],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

ThemeData temaBarberia() {
  final base = ColorScheme.fromSeed(
    seedColor: Marca.dorado,
    brightness: Brightness.light,
  );

  // Los estilos de botón parten de labelLarge para conservar la fuente
  // de la plataforma; un TextStyle suelto la reemplazaría por completo.
  final etiqueta = ThemeData(useMaterial3: true).textTheme.labelLarge
      ?.copyWith(fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    colorScheme: base.copyWith(
      primary: Marca.negro,
      onPrimary: Colors.white,
      secondary: Marca.dorado,
      surface: Colors.white,
      error: Marca.rojo,
    ),
    scaffoldBackgroundColor: Marca.fondo,
    appBarTheme: const AppBarTheme(
      backgroundColor: Marca.fondo,
      foregroundColor: Marca.texto,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Marca.borde),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Marca.borde, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Marca.borde),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Marca.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Marca.dorado, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Marca.negro,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: etiqueta,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Marca.texto,
        side: const BorderSide(color: Marca.borde),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Marca.texto),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
