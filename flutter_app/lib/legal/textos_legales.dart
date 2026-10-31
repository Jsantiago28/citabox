// Textos legales editables. BORRADOR: requieren revisión de un abogado
// antes de publicarse (Ley 172-13 de protección de datos, RD).

const avisoBorradorLegal = 'Borrador — pendiente de revisión legal';

/// Una sección de texto legal: título y párrafos.
class SeccionLegal {
  const SeccionLegal(this.titulo, this.parrafos);

  final String titulo;
  final List<String> parrafos;
}

const tituloPrivacidad = 'Política de privacidad';
const tituloTerminos = 'Términos de uso';

const seccionesPrivacidad = <SeccionLegal>[
  SeccionLegal('Quién es responsable de tus datos', [
    'El negocio donde reservas tu cita es el responsable '
        'del tratamiento de tus datos personales. Citabox es la '
        'plataforma que los almacena y procesa por cuenta del negocio '
        '(encargado del tratamiento).',
  ]),
  SeccionLegal('Qué datos guardamos', [
    'Tu nombre, tu teléfono, tu correo electrónico (si lo escribes), las '
        'notas que dejes y el historial de tus citas (servicio, quién te atiende, '
        'fecha, hora, estado y apartado).',
  ]),
  SeccionLegal('Para qué los usamos', [
    'Solo para gestionar tus citas: confirmarlas, recordártelas, '
        'contactarte si hay cambios y llevar el historial de atención del '
        'negocio. No vendemos tus datos ni los usamos para publicidad de '
        'terceros.',
  ]),
  SeccionLegal('Tus derechos', [
    'Conforme a la Ley 172-13 puedes pedir acceso a tus datos, su '
        'rectificación, su cancelación (eliminación o anonimización) y '
        'oponerte a su uso.',
    'Para ejercerlos, escríbele o llama al negocio donde reservaste. El '
        'negocio puede exportar tus datos o anonimizarlos desde su panel. '
        'Las citas pasadas pueden conservarse sin datos que te identifiquen '
        'para fines contables y de reportes.',
  ]),
  SeccionLegal('Dónde se almacenan', [
    'Los datos se guardan en servidores de Supabase, con acceso restringido '
        'al personal autorizado del negocio y conexiones cifradas.',
    'Para detectar y corregir fallos usamos Sentry, que recibe información '
        'técnica del error (pantalla, navegador y versión de la app). No le '
        'enviamos tu nombre, teléfono, correo ni dirección IP.',
  ]),
  SeccionLegal('Cookies y almacenamiento local', [
    'Usamos únicamente almacenamiento técnico en tu navegador (por ejemplo, '
        'recordar tu última cita en ese dispositivo y mantener tu sesión si '
        'eres parte del negocio). No usamos cookies de publicidad ni de '
        'seguimiento.',
  ]),
  SeccionLegal('Conservación y cambios', [
    'Conservamos tus datos mientras el negocio los necesite para atenderte '
        'o hasta que pidas su cancelación. Podemos actualizar esta política; '
        'la versión vigente siempre estará en esta página.',
  ]),
];

const seccionesTerminos = <SeccionLegal>[
  SeccionLegal('El servicio', [
    'Citabox es una herramienta para que negocios que trabajan con citas '
        '(barberías, salones, spas, consultorios y otros) gestionen '
        'su agenda, clientes, servicios y reservas en línea. Al registrar '
        'un negocio aceptas estos términos y la política de privacidad.',
  ]),
  SeccionLegal('Uso por parte de los negocios', [
    'El negocio es responsable de la veracidad de la información que '
        'publica (servicios, precios, horarios), de atender las citas que '
        'acepta y de tratar los datos de sus clientes conforme a la ley y a '
        'la política de privacidad. No debe usar la plataforma para fines '
        'ilícitos ni para enviar mensajes no solicitados.',
  ]),
  SeccionLegal('Reservas y apartados entre cliente y negocio', [
    'Las reservas y los apartados (adelantos) son un acuerdo entre el '
        'cliente y el negocio. Las condiciones de cancelación, reprogramación '
        'y reembolso del apartado las define el negocio. Citabox no '
        'cobra ni retiene el apartado: solo registra la información.',
  ]),
  SeccionLegal('Limitación de responsabilidad', [
    'Citabox se ofrece "tal cual". No somos parte de la relación entre '
        'cliente y negocio ni responsables por la calidad del servicio, por '
        'pagos acordados entre ellos, ni por interrupciones puntuales del '
        'servicio. Haremos esfuerzos razonables por mantener la plataforma '
        'disponible y los datos seguros.',
  ]),
  SeccionLegal('Cambios', [
    'Podemos modificar estos términos. Los cambios importantes se '
        'comunicarán en la plataforma.',
  ]),
];
