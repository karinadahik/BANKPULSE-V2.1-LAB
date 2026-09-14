# 2. Payments data ownership

Date: 2026-09-14

## Status

Accepted

## Context

BankPulse separa sus capacidades de negocio en servicios independientes.

`payments-api` pertenece al contexto de Core Financiero y es responsable de registrar pagos. Debido a que información de un pago también debe ser utilizada por otros contextos, como Auditoría, es necesario definir explícitamente qué servicio posee los datos financieros y cómo pueden ser consumidos por otros servicios sin compartir la base de datos.

## Decision

`payments-api` será el propietario de los datos de pagos.

La entidad canónica de negocio es `Payment`, con los atributos:

- `id`
- `idempotencyKey`
- `account`
- `amount`
- `currency`
- `status`
- `createdAt`

La fuente de verdad de los pagos es MariaDB, utilizada por `payments-api`.

Las tablas observadas son:

- `payments`
- `outbox_events`

Otros servicios no deben modificar directamente los registros de pagos ni acceder directamente a las tablas del servicio.

La creación de pagos se expone mediante:

- `POST /api/payments`

y requiere:

- `X-Idempotency-Key`

La idempotencia evita crear múltiples pagos ante reintentos de una misma solicitud.

La integración con `audit-api` utiliza HTTP mediante:

- `POST /internal/events`

Para asegurar la entrega se utiliza Transactional Outbox. `Payment` y `OutboxEvent` se persisten dentro de la misma transacción local de MariaDB.

Un proceso programado intenta publicar los eventos pendientes aproximadamente cada 2000 ms. Si Auditoría falla, el pago permanece registrado y el evento queda pendiente para ser reintentado.

Existe consistencia fuerte entre `Payment` y `OutboxEvent`, y consistencia eventual entre `payments-api` y `audit-api`.

`payments-api` expone health, metrics y Prometheus mediante Spring Boot Actuator. El estado del Outbox también puede observarse mediante:

- `GET /api/outbox`

En el código revisado no se observa una configuración explícita de timeout para la llamada HTTP a `audit-api`; queda registrado como una mejora pendiente de resiliencia.

## Consequences

### Positive

- Ownership claro de los datos de pagos.
- Evita pagos duplicados mediante idempotencia.
- Reduce el acoplamiento entre bounded contexts.
- Transactional Outbox evita perder eventos.
- Auditoría puede fallar temporalmente sin perder el pago.
- Es posible observar eventos pendientes y fallos de publicación.

### Negative

- Auditoría puede quedar temporalmente desactualizada.
- Es necesario administrar reintentos y eventos pendientes.
- El Outbox agrega almacenamiento y complejidad operativa.
- Se debe monitorear la acumulación de eventos no publicados.
- La llamada a Auditoría todavía no presenta un timeout explícitamente configurado.