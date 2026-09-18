# Deber 01 — El falso verde

## 1. Capacidad de negocio seleccionada

BANKPULSE debe procesar una operación de pago **exactamente una vez**, incluso
cuando el cliente o la red reintenten la misma solicitud.

La operación utiliza `X-Idempotency-Key` para identificar una misma intención
de pago.

La capacidad crítica protegida es:

> **Un mismo intento lógico de pago no debe generar más de un pago real.**

Esta capacidad es especialmente importante para experiencias como
**Social Split**, donde varios participantes pueden intervenir en una misma
operación financiera y un reintento no debe convertirse en un cobro duplicado.

---

## 2. Escenario de falso verde

La plataforma puede permanecer técnicamente disponible:

- Payments API: UP
- MariaDB: UP
- Contenedores Docker: healthy
- HTTP: 200
- Health check: UP

Sin embargo, un defecto en la lógica de idempotencia podría provocar que dos
solicitudes con la misma `X-Idempotency-Key` creen dos pagos distintos.

En este escenario:

```text
Infraestructura    -> VERDE
Health checks      -> VERDE
HTTP               -> VERDE
Base de datos      -> VERDE

pero...

Capacidad de negocio
"procesar una vez" -> ROJO
```

El sistema estaría técnicamente disponible, pero el negocio estaría generando
un cobro duplicado.

Ese comportamiento representa un **falso verde**.

---

## 3. Riesgo / pérdida potencial

Un fallo de idempotencia puede producir:

- Cobros duplicados.
- Pérdida financiera.
- Reclamos de clientes.
- Procesos de reverso.
- Costos operativos adicionales.
- Pérdida de confianza del socio.
- Inconsistencias entre pagos y procesos asociados.

Por esta razón no es suficiente validar únicamente que los servicios estén
encendidos.

También debe validarse el comportamiento crítico del negocio.

---

## 4. Release Gate

El pipeline incorpora una validación automática de la capacidad crítica antes
de considerar una versión apta para continuar.

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
```

La prueba automática se encuentra en:

```text
scripts/business-gate-payment-idempotency.sh
```

La regla validada es:

```text
misma Idempotency-Key
        +
2 solicitudes
        =
1 único pago
```

El Release Gate comprueba que:

1. las dos solicitudes devuelvan el mismo `payment id`;
2. exista exactamente un pago asociado a la operación;
3. la disponibilidad técnica no sea utilizada como único criterio de éxito.

Si la regla se incumple, el pipeline debe bloquear la entrega.

---

# 5. KPIs estratégicos — Épica Social Split

## 5.1 Épica seleccionada

La épica seleccionada es:

> **Social Split para consumo colaborativo**

Su objetivo de negocio es permitir que varios socios distribuyan de manera
coordinada el costo de una experiencia compartida.

La experiencia requiere:

- incorporar participantes;
- distribuir el monto del consumo;
- obtener autorización explícita;
- mantener visible el progreso;
- cerrar la operación colectiva solamente cuando se cumplan las reglas del
  negocio.

El bounded context principal utilizado para estos KPI es:

```text
Social Split
```

Su responsabilidad incluye:

```text
Split Session
Participantes
Distribución del monto
Autorizaciones
Estado de la operación
Cierre del consumo compartido
```

La relación conceptual con el contexto financiero puede representarse como:

```text
SOCIAL SPLIT
sesión + participantes + autorizaciones
             |
             | referencia / necesidad financiera
             v
PAYMENTS / CORE FINANCIERO
procesamiento de pagos
             |
             v
AUDIT
trazabilidad
```

Los KPI se definen primero utilizando lenguaje de negocio y luego se traducen
a métricas técnicas observables.

---

## 5.2 Resumen de los 5 KPI

| KPI | Pregunta de negocio |
|---|---|
| **KPI 1 — Tasa de cierre exitoso de consumos compartidos** | ¿Qué porcentaje de los consumos compartidos iniciados logra concretarse correctamente? |
| **KPI 2 — Tasa de adhesión de participantes** | ¿Qué porcentaje de las personas incorporadas acepta y autoriza su participación? |
| **KPI 3 — Tiempo promedio de cierre** | ¿Cuánto tiempo necesita un grupo para concretar el consumo compartido? |
| **KPI 4 — Tasa de intentos de cierre bloqueados por autorización incompleta** | ¿Qué porcentaje de intentos de cierre debe ser bloqueado porque todavía faltan autorizaciones? |
| **KPI 5 — Tasa de integridad de distribución del monto compartido** | ¿Qué porcentaje de operaciones distribuye correctamente el monto total acordado entre sus participantes? |

---

## 5.3 KPI 1 — Tasa de cierre exitoso de consumos compartidos

### Pregunta de negocio

¿Qué porcentaje de los consumos compartidos iniciados logra concretarse
correctamente?

### Fórmula

```text
Social Splits completados
------------------------- x 100
Social Splits iniciados
```

### Métricas

```text
bankpulse_social_split_sessions_completed_total
bankpulse_social_split_sessions_initiated_total
```

### Qué protege

Permite observar si una experiencia Social Split que comienza realmente logra
convertirse en una operación colectiva completada.

Una cantidad elevada de operaciones abiertas que nunca terminan puede indicar
fricción o pérdida de valor para el negocio.

---

## 5.4 KPI 2 — Tasa de adhesión de participantes

### Pregunta de negocio

¿Qué porcentaje de las personas incorporadas a un consumo compartido acepta y
autoriza su participación?

### Fórmula

```text
Participantes autorizados
------------------------- x 100
Participantes incorporados
```

### Métricas

```text
bankpulse_social_split_participants_authorized_total
bankpulse_social_split_participants_added_total
```

### Qué protege

Permite identificar si los participantes realmente continúan con la experiencia
después de ser incorporados al consumo compartido.

Una baja adhesión puede impedir que la operación colectiva llegue a concretarse.

---

## 5.5 KPI 3 — Tiempo promedio de cierre

### Pregunta de negocio

¿Cuánto tiempo necesita un grupo para concretar un consumo compartido desde su
creación hasta el cierre?

### Fórmula

```text
Suma del tiempo de cierre
-------------------------
Operaciones completadas
```

### Métricas

```text
bankpulse_social_split_sessions_close_duration_seconds_sum
bankpulse_social_split_sessions_close_duration_seconds_count
```

### Implementación

El modelo registra:

```text
createdAt
completedAt
```

Por lo tanto:

```text
duración = completedAt - createdAt
```

### Qué protege

Permite identificar fricción en la experiencia.

Una operación puede terminar correctamente y, sin embargo, tardar demasiado
tiempo para resultar conveniente para los participantes.

---

## 5.6 KPI 4 — Tasa de intentos de cierre bloqueados por autorización incompleta

### Pregunta de negocio

¿Qué porcentaje de los intentos de concretar un consumo compartido debe ser
bloqueado porque todavía faltan autorizaciones?

### Fórmula

```text
Cierres bloqueados
------------------ x 100
Intentos de cierre
```

### Métricas

```text
bankpulse_social_split_sessions_close_blocked_total
bankpulse_social_split_sessions_close_attempts_total
```

### Regla de negocio

Social Split no debe completar una operación mientras exista al menos un
participante pendiente de autorización.

Conceptualmente:

```text
faltan autorizaciones
        |
        v
     BLOCK
```

y:

```text
todos autorizaron
        |
        v
    COMPLETED
```

### Qué protege

Evita cerrar una operación colectiva antes de que todos los participantes hayan
confirmado su participación.

Este KPI no representa por sí mismo una meta positiva o negativa. Su
interpretación depende del contexto operativo y del comportamiento de los
usuarios.

---

## 5.7 KPI 5 — Tasa de integridad de distribución del monto compartido

### Pregunta de negocio

¿Qué porcentaje de los consumos compartidos distribuye correctamente el monto
total acordado entre los participantes?

### Fórmula

```text
Distribuciones válidas
------------------------------------- x 100
Distribuciones válidas + inválidas
```

### Métricas

```text
bankpulse_social_split_settlements_valid_total
bankpulse_social_split_settlements_invalid_total
```

### Regla utilizada

Para la instrumentación del laboratorio se considera válida la distribución
cuando:

```text
suma de shareAmount de participantes
=
totalAmount de la sesión
```

Ejemplo:

```text
Monto total: $100

Participante A: $40
Participante B: $60

$40 + $60 = $100

Distribución válida
```

### Qué protege

Permite detectar operaciones que técnicamente llegaron a completarse pero cuya
distribución económica no representa correctamente el monto acordado.

Esta validación protege la integridad de la distribución dentro de Social Split.

La validación de que cada `paymentReference` corresponde efectivamente a un pago
financiero válido pertenece a una integración posterior con el contexto de
Payments.

---

# 6. Instrumentación y observabilidad de los KPI

Las métricas fueron implementadas utilizando:

```text
Spring Boot Actuator
Micrometer
Prometheus
Grafana
```

El flujo de observabilidad implementado es:

```text
DDD / Épica Social Split
          |
          v
Reglas de negocio
          |
          v
Eventos del dominio
          |
          v
Micrometer
          |
          v
/actuator/prometheus
          |
          v
Prometheus
          |
          v
Grafana
```

El endpoint del servicio expone las métricas mediante:

```text
/actuator/prometheus
```

Prometheus recolecta las métricas desde:

```text
social-split-api:8086
```

---

## 6.1 Business KPI Gate

Se creó el script:

```text
scripts/business-kpi-social-split.sh
```

Este script ejecuta automáticamente un escenario completo:

```text
Crear Social Split de $100
        |
        v
Agregar participante A = $40
Agregar participante B = $60
        |
        v
Intentar cerrar sin autorizaciones
        |
        v
BLOCK esperado
        |
        v
Autorizar participante A
Autorizar participante B
        |
        v
Cerrar Social Split
        |
        v
COMPLETED
        |
        v
Validar los 5 KPI
```

Resultado obtenido:

```text
KPI 1 PASS - Social Split completed
KPI 2 PASS - Participants authorized
KPI 3 PASS - Completion time observed
KPI 4 PASS - Premature close blocked
KPI 5 PASS - Financial distribution balanced

BUSINESS KPI GATE: PASS
```

---

## 6.2 Resultado del escenario controlado

Durante la prueba automatizada se observaron los siguientes valores:

| KPI | Resultado |
|---|---:|
| Tasa de cierre exitoso | 100.00 % |
| Tasa de adhesión | 100.00 % |
| Tiempo promedio de cierre | aproximadamente 1.17 s |
| Intentos de cierre bloqueados | 50.00 % |
| Integridad de distribución | 100.00 % |

Estos valores corresponden al **escenario controlado del laboratorio**.

No representan todavía metas comerciales ni SLA oficiales de producción.

El 50 % observado en el KPI 4 se explica porque el escenario realiza
deliberadamente:

```text
Intento de cierre #1
faltan autorizaciones
-> BLOCKED

Intento de cierre #2
todos autorizados
-> COMPLETED
```

Por lo tanto:

```text
1 bloqueo
---------
2 intentos
=
50 %
```

---

# 7. Dashboard Grafana

Se creó el dashboard:

```text
BANKdragon — Social Split Business KPIs
```

Archivo:

```text
observability/grafana/dashboards/social-split-business-kpis.json
```

El dashboard permite visualizar:

1. Cierre exitoso de consumos compartidos.
2. Adhesión de participantes.
3. Tiempo promedio de cierre.
4. Cierres bloqueados por autorización incompleta.
5. Integridad de distribución del monto.

No se configuraron umbrales comerciales artificiales porque el caso no define
todavía metas oficiales de producción.

Por esta razón los paneles presentan los valores observados sin clasificarlos
automáticamente como buenos o malos.

---

# 8. Integración con CI

El workflow:

```text
.github/workflows/ci.yml
```

incorpora validaciones de arquitectura, comportamiento de negocio y
observabilidad.

El flujo relevante queda:

```text
Pull Request
     |
     v
ADR Governance
     |
     v
Architecture Contract
     |
     v
Build BANKPULSE
     |
     v
Technical Validation
     |
     +------------------------------+
     |                              |
     v                              v
Payment Business Gate       Social Split KPI Gate
     |                              |
     v                              v
Idempotency                  5 KPI de negocio
     |                              |
     +--------------+---------------+
                    |
                    v
             Smoke Tests
                    |
                    v
               Prometheus
                    |
                    v
                 Grafana
```

El pipeline incluye:

```text
Business release gate - payment idempotency
Business KPI gate - Social Split
Validate Social Split KPIs in Prometheus
```

De esta manera CI no valida únicamente que la aplicación compile o que los
contenedores estén encendidos.

También verifica comportamiento observable del negocio.

---

# 9. Evidencia de PR exitoso

Se creó el Pull Request:

```text
PR #3
feature/business-release-gate
```

GitHub Actions ejecutó correctamente:

```text
ADR governance                           PASS
Architecture contract                    PASS
Build, integration and observability     PASS
```

Dentro del job de integración se observó:

```text
Build and start BANKdragon V2                 PASS
Validate interactive edge UI                  PASS
Business release gate - payment idempotency   PASS
Domain and regression smoke tests             PASS
Start Prometheus and Grafana                  PASS
Validate observability endpoints              PASS
```

Esta ejecución representa el comportamiento correcto antes de provocar
deliberadamente el falso verde.

---

# 10. Escenario de falso verde provocado

> **Pendiente de completar durante la prueba deliberada final.**

Para demostrar el falso verde se modificará temporalmente el comportamiento de
idempotencia de Payments.

El escenario esperado será:

```text
Payments API       UP
Docker             healthy
Base de datos      UP
HTTP               disponible
Health check       UP

pero

misma operación
2 requests
2 payments

BUSINESS RELEASE GATE -> BLOCK
```

El objetivo no es provocar una caída técnica.

El objetivo es demostrar que la plataforma puede estar técnicamente saludable
mientras incumple una capacidad crítica del negocio.

---

# 11. Evidencia del bloqueo

> **Pendiente de capturar durante la ejecución del escenario deliberadamente defectuoso.**

La evidencia deberá mostrar:

```text
Build and start BANKdragon V2                 PASS
Validate interactive edge UI                  PASS
Business release gate - payment idempotency   FAIL
Capture evidence on failure                   EXECUTED
```

El Business Release Gate deberá producir un mensaje equivalente a:

```text
RELEASE BLOCKED
```

La evidencia debe demostrar que la infraestructura estaba disponible pero que
el comportamiento del negocio era incorrecto.

---

# 12. Diagnóstico y corrección

> **Pendiente de completar después de provocar el falso verde.**

El diagnóstico deberá identificar que el fallo pertenece a la lógica de
idempotencia y no a la disponibilidad técnica.

La corrección deberá restaurar la propiedad:

```text
misma intención de pago
+
mismo X-Idempotency-Key
=
mismo payment
```

Después de aplicar la corrección se ejecutará nuevamente el pipeline.

---

# 13. Ejecución final

> **Pendiente de completar después de aplicar la corrección.**

El resultado final esperado es:

```text
Technical Health              PASS
Payment Business Gate         PASS
Social Split KPI Gate         PASS
Smoke Tests                   PASS
Prometheus                    PASS
Grafana                       PASS
```

Esto demostrará el ciclo completo:

```text
Comportamiento correcto
        |
        v
Pipeline verde
        |
        v
Defecto deliberado
        |
        v
Tecnología verde / negocio rojo
        |
        v
Release bloqueado
        |
        v
Diagnóstico
        |
        v
Corrección
        |
        v
Pipeline verde nuevamente
```

---

# 14. Conclusión

El laboratorio demuestra que la disponibilidad técnica no es suficiente para
determinar si una plataforma está funcionando correctamente.

BANKPULSE puede mantener:

```text
servicios UP
contenedores healthy
HTTP disponible
base de datos disponible
```

y aun así generar pérdida de valor si una regla crítica del negocio se rompe.

Por esta razón se incorporaron dos niveles complementarios de protección:

```text
Payments
-> Business Release Gate
-> evita pagos duplicados

Social Split
-> Business KPI Gate
-> valida comportamiento y señales estratégicas
```

Finalmente, las métricas del dominio son recolectadas mediante Prometheus y
visualizadas en Grafana.

El recorrido implementado conecta:

```text
DDD
|
v
Bounded Context
|
v
Épica Social Split
|
v
KPIs estratégicos
|
v
Reglas de negocio
|
v
CI / Release Gates
|
v
Prometheus
|
v
Grafana
|
v
Observabilidad del negocio
```

El objetivo final no es únicamente demostrar que BANKPULSE está encendido, sino
demostrar con evidencia que las capacidades críticas del negocio continúan
funcionando correctamente.