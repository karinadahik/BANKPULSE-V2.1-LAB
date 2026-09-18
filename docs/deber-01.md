# Deber 01 — El falso verde

## 1. Capacidad de negocio seleccionada

BANKPULSE debe procesar una operación de pago exactamente una vez,
incluso cuando el cliente o la red reintenten la misma solicitud.

La operación utiliza `X-Idempotency-Key` para identificar una misma
intención de pago.

## 2. Escenario de falso verde

La plataforma puede permanecer técnicamente disponible:

- Payments API: UP
- MariaDB: UP
- Contenedores Docker: healthy
- HTTP: 200
- Health check: UP

pero un defecto de idempotencia podría provocar que dos solicitudes
con la misma `X-Idempotency-Key` creen dos pagos distintos.

En este escenario la tecnología estaría verde mientras el negocio
estaría generando un cobro duplicado.

## 3. Riesgo / pérdida potencial

- Cobro duplicado.
- Pérdida financiera.
- Reclamos de clientes.
- Necesidad de reversos.
- Pérdida de confianza.

## 4. Release Gate

```text
Feature Branch
      |
      v
Pull Request
      |
      v
GitHub Actions
      |
      v
Build / Docker
      |
      v
Technical Health
      |
      v
Business Release Gate
      |
      | misma Idempotency-Key
      | 2 requests
      | 1 payment
      |
   +--+--+
   |     |
 PASS   BLOCK