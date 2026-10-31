/// Programa de fidelización del negocio ("la décima gratis"): cada
/// [visitas] visitas atendidas, el cliente recibe [premio].
class Fidelidad {
  const Fidelidad({required this.visitas, this.premio = 'Servicio gratis'});

  final int visitas;
  final String premio;

  /// null si el negocio no tiene programa (columna `fidelidad_visitas`).
  static Fidelidad? desde(Object? visitas, Object? premio) {
    final n = int.tryParse('${visitas ?? ''}');
    if (n == null || n < 2) return null;
    final texto = '${premio ?? ''}'.trim();
    return Fidelidad(
      visitas: n,
      premio: texto.isEmpty ? 'Servicio gratis' : texto,
    );
  }

  /// Visitas que lleva en la ronda actual (la del premio cierra la ronda).
  int enRonda(int atendidas) => atendidas % visitas;

  /// La próxima visita es la del premio.
  bool proximaEsPremio(int atendidas) => (atendidas + 1) % visitas == 0;

  /// '7 de 10 · faltan 3 para Corte gratis' o
  /// '¡La próxima visita: Corte gratis!'.
  String progreso(int atendidas) {
    if (proximaEsPremio(atendidas)) return '¡La próxima visita: $premio!';
    final faltan = visitas - 1 - enRonda(atendidas);
    return '${enRonda(atendidas)} de $visitas · '
        'falta${faltan == 1 ? '' : 'n'} $faltan para $premio';
  }

  /// Texto para la página de reservas.
  String get invitacion => 'En tu visita $visitas: $premio.';
}
