# Datos de demostración

Sirven para enseñar la app (o probarla) con una agenda que se vea real,
sin tener que escribir todo a mano. **No son migraciones**: se ejecutan a
mano, solo en el negocio que tú elijas.

| Archivo | Para qué |
|---|---|
| `demo.sql` | Llena un negocio que ya existe con datos de ejemplo. |
| `borrar_demo.sql` | Quita esos datos de ejemplo. |

## Qué crea `demo.sql`

- **6 servicios** (precios en RD$): Corte de cabello (400, 30 min),
  Corte + barba (600, 45 min), Barba (250, 20 min), Cerquillo (150, 15 min),
  Tinte (800, 60 min) y Corte de niño (300, 25 min).
- **3 barberos** sin cuenta de acceso: Carlos Peña, Luis Martínez y
  José "Junior" Rodríguez.
- **Horario**: lunes a sábado de 9:00 a 19:00; domingo cerrado. Si un día
  ya tenía horario, se deja como estaba.
- **15 clientes** con nombres dominicanos y teléfonos ficticios
  (809/829/849-555-01xx).
- **Unas 40 citas** desde hace 2 semanas hasta dentro de 7 días:
  - pasadas: completadas, algunas "no vino" y algunas canceladas;
  - hoy: completadas, "llegó" o confirmadas según la hora;
  - próximas: pendientes, confirmadas y alguna cancelada.
  - Las confirmadas tienen su apartado pagado y las pendientes un apartado
    por validar.
- Ninguna cita se cruza con otra del mismo barbero.

## Cómo usarlo

1. Primero crea tu negocio desde la app (registro). Anota su **slug**: es la
   parte final del enlace de reservas (por ejemplo `mi-barberia`). También lo
   ves en Supabase → **Table Editor** → `negocios` → columna `slug`.
2. Entra a Supabase → **SQL Editor** → **New query**.
3. Copia y pega todo el contenido de `demo.sql`.
4. En la línea marcada con `<<<` cambia `'mi-barberia'` por tu slug
   (deja las comillas simples).
5. Pulsa **Run**. Abajo, en los mensajes, verás un resumen como:
   `Datos de demostración en "mi-barberia": 6 servicios, 3 barberos, ... 41 citas ...`
6. Abre la app y recarga la página.

Puedes ejecutarlo varias veces sin miedo: no duplica servicios, barberos ni
clientes (los reconoce por nombre o teléfono), y si ya hay citas de
demostración avisa y no crea más.

Si sale el error *No existe ningún negocio con el slug...*, revisa que el
slug esté bien escrito.

## Cómo borrarlo

1. Supabase → **SQL Editor** → **New query**.
2. Pega `borrar_demo.sql`, cambia `'mi-barberia'` por tu slug y pulsa **Run**.

Borra las citas con `[demo]` en las notas (y sus apartados), los clientes
de demostración y los barberos y servicios de la demo que ya no tengan
citas. El horario no se toca.

> Ojo: si antes de la demo ya tenías un servicio o barbero con exactamente
> el mismo nombre (por ejemplo "Barba") y no tiene citas, también se borra.
> Las citas reales nunca se borran.

## Pruebas

El CI (`.github/workflows/ci.yml`) aplica las migraciones, ejecuta
`demo.sql` dos veces, luego `borrar_demo.sql` y otra vez `demo.sql`, para
comprobar que no falla y que respeta las reglas de la base.

## Simulación completa (`simulacion.mjs`)

Entra con la cuenta del dueño (sus mismos permisos; no toca otros negocios)
y llena **su** negocio con unos 2 meses de movimiento usando sus servicios y
su horario:

- **30 clientes**: 4 que dejaron de venir ("No vuelven"), 4 nuevos por
  reserva en línea, cumpleaños en el mes y uno fijo con 9 visitas (su
  próxima es la gratis: activa "la décima gratis", cada 10, "Corte gratis").
- **2 profesionales** con comisión (Rafael Núñez 40 %, Kelvin Abreu 35 %) y
  unas vacaciones de Kelvin dentro de la semana que viene.
- **Citas** desde hace ~70 días hasta dentro de 7: cobradas (efectivo,
  transferencia, tarjeta y propinas), "no vino", canceladas, reservas en
  línea con apartado pagado y 2 apartados por validar (vencen en 24 h).

```
CB_EMAIL=correo CB_PASS=clave node supabase/seed/simulacion.mjs
CB_EMAIL=correo CB_PASS=clave node supabase/seed/simulacion.mjs --borrar
```

La clave va solo en la línea de comandos. `simulacion-ids.json` anota lo
creado (profesionales, vacaciones y la fidelidad anterior) para que
`--borrar` lo deshaga; clientes y citas se reconocen por "[demo]".
