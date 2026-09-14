# ADR-001: Data Ownership de payments-api

- **Estado:** Propuesto
- **Fecha:** 2026-09-13
- **Equipo:** Karina

## Contexto

BankPulse separa sus capacidades de negocio en servicios independientes. El servicio `payments-api` pertenece al contexto de Core Financiero y es responsable de registrar pagos.

Debido a que información de un pago también debe ser utilizada por otros contextos, como Auditoría, es necesario definir explícitamente qué servicio posee los datos financieros y cómo pueden ser consumidos por otros servicios sin compartir la base de datos.

## Decision

`payments-api` será el propietario de los datos de pagos.

La entidad canónica de negocio perteneciente al servicio es:

- `Payment`

Sus atributos principales son:

- `id`
- `idempotencyKey`
- `account`
- `amount`
- `currency`
- `status`
- `createdAt`

`OutboxEvent` es un registro técnico utilizado para integración confiable y no representa una entidad canónica del dominio de pagos.

Otros servicios no deben modificar directamente los registros de pagos.

## Source of Truth

La fuente de verdad de los pagos es la base relacional MariaDB utilizada por `payments-api`.

Tablas observadas:

- `payments`
- `outbox_events`

`payments-api` es el único servicio que debe realizar escrituras sobre sus datos de pagos.

Otros servicios deben consumir la información mediante contratos de integración y no mediante acceso directo a las tablas.

## Datos externos requeridos

`payments-api` se integra actualmente con `audit-api` para registrar eventos de auditoría relacionados con pagos.

`audit-api` no es propietario de los datos del pago. Recibe una representación del evento necesario para auditoría.

## Integracion

La creación de pagos se expone mediante:

- `POST /api/payments`

La operación requiere el header:

- `X-Idempotency-Key`

La integración con Auditoría utiliza HTTP/REST:

- `POST /internal/events` de `audit-api`

Para asegurar la entrega se utiliza el patrón Transactional Outbox.

Al crear un pago, `Payment` y `OutboxEvent` se persisten dentro de la misma transacción de base de datos.

Un proceso programado revisa eventos pendientes aproximadamente cada 2000 ms y los envía a `audit-api`.

Si Auditoría no está disponible:

- el pago no se elimina;
- el evento permanece pendiente;
- se incrementa el número de intentos;
- se registra el último error;
- el evento puede volver a intentarse posteriormente.

### Idempotencia

La creación de pagos es idempotente mediante `X-Idempotency-Key`.

Antes de crear un nuevo pago se busca un registro con la misma clave. Además, la columna `idempotency_key` posee una restricción de unicidad en MariaDB.

Esto evita crear múltiples pagos ante reintentos de una misma solicitud.

### Timeout

En el código revisado no se observa una configuración explícita de timeout para la llamada HTTP hacia `audit-api`.

Este punto queda identificado como una mejora pendiente antes de considerar completamente cerrada la política de resiliencia de la integración.

## Consistencia

### Pago y Outbox

Existe consistencia fuerte entre `Payment` y `OutboxEvent`, ya que ambos se escriben dentro de una misma transacción local de MariaDB.

### Payments y Auditoría

Existe consistencia eventual entre `payments-api` y `audit-api`.

Un pago puede quedar confirmado en `payments-api` mientras su evento permanece temporalmente pendiente de publicación hacia Auditoría.

El patrón Outbox permite reintentar posteriormente sin perder el evento.

## Seguridad y privacidad

`payments-api` conserva el ownership de la información financiera asociada al pago.

Los demás servicios no deben acceder directamente a su base de datos.

El evento enviado a Auditoría contiene únicamente la información necesaria observada en la implementación actual:

- identificador del evento;
- identificador del pago;
- cuenta;
- monto;
- moneda;
- fecha del evento.

Debe evitarse replicar información financiera o personal adicional que no sea necesaria para el caso de auditoría.

## Observabilidad

`payments-api` expone mediante Spring Boot Actuator:

- health;
- info;
- metrics;
- prometheus.

El health check utilizado actualmente es:

`/actuator/health`

El estado del patrón Outbox puede observarse mediante:

`GET /api/outbox`

Este endpoint permite visualizar:

- número de eventos pendientes;
- eventos todavía no publicados;
- número de intentos;
- último error.

Los logs del `OutboxPublisher` permiten observar publicaciones exitosas y fallos de comunicación con Auditoría.

## Alternativas consideradas

### Base de datos compartida

Permitir que `audit-api` u otros servicios escriban directamente en las tablas de pagos.

Se descarta porque incrementa el acoplamiento entre servicios y elimina el ownership claro de los datos.

### Acceso directo a la base externa

Permitir que otros servicios consulten directamente MariaDB de `payments-api`.

Se descarta porque expone el modelo interno de persistencia y genera dependencia entre los esquemas de distintos bounded contexts.

### Otra tecnología de persistencia

Utilizar una base documental para los pagos.

Se mantiene MariaDB debido a que el flujo de pagos requiere operaciones transaccionales entre el registro de `Payment` y su `OutboxEvent`, y la implementación actual ya utiliza persistencia relacional mediante JPA.

## Consecuencias

### Positivas

- Ownership claro de los datos de pagos.
- Reduce el acoplamiento entre bounded contexts.
- Previene pagos duplicados mediante idempotencia.
- Evita perder eventos mediante Transactional Outbox.
- Permite que Auditoría falle temporalmente sin perder el pago.
- Facilita observabilidad sobre eventos pendientes.

### Negativas / trade-offs

- Auditoría puede quedar temporalmente desactualizada respecto de Payments.
- Se requiere gestionar reintentos y eventos pendientes.
- La tabla de Outbox agrega almacenamiento y complejidad operativa.
- Es necesario monitorear acumulación de eventos no publicados.
- La llamada HTTP a Auditoría todavía no muestra un timeout explícitamente configurado.