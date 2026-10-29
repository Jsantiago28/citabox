import 'package:flutter/material.dart';

/// Casilla obligatoria de aceptación con enlaces a las páginas legales.
/// [enlaces] son pares etiqueta → ruta (`/privacidad`, `/terminos`).
class ConsentimientoCheck extends FormField<bool> {
  ConsentimientoCheck({
    super.key,
    required String texto,
    required Map<String, String> enlaces,
    required bool valor,
    required ValueChanged<bool> onChanged,
    String mensajeError = 'Debes aceptar para continuar.',
  }) : super(
         initialValue: valor,
         validator: (v) => v == true ? null : mensajeError,
         builder: (estado) {
           final contexto = estado.context;
           return Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Row(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Checkbox(
                     value: valor,
                     onChanged: (v) {
                       estado.didChange(v ?? false);
                       onChanged(v ?? false);
                     },
                   ),
                   Expanded(
                     child: Padding(
                       padding: const EdgeInsets.only(top: 12),
                       child: Text(texto),
                     ),
                   ),
                 ],
               ),
               Wrap(
                 children: [
                   const SizedBox(width: 12),
                   for (final e in enlaces.entries)
                     TextButton(
                       onPressed: () =>
                           Navigator.of(contexto).pushNamed(e.value),
                       child: Text(e.key),
                     ),
                 ],
               ),
               if (estado.hasError)
                 Padding(
                   padding: const EdgeInsets.only(left: 12, bottom: 4),
                   child: Text(
                     estado.errorText!,
                     style: TextStyle(
                       color: Theme.of(contexto).colorScheme.error,
                       fontSize: 12,
                     ),
                   ),
                 ),
             ],
           );
         },
       );
}
