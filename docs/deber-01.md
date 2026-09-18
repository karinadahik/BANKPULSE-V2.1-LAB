# Deber 01 — El falso verde

## 1. Capacidad de negocio seleccionada

La capacidad crítica seleccionada en BANKPULSE es:

> **Procesar una misma intención de pago exactamente una vez.**

Cuando un cliente o una red reintentan una solicitud, BANKPULSE utiliza
`X-Idempotency-Key` para reconocer que se trata de la misma operación de
negocio.

La propiedad esperada es:

```text
Misma intención de pago
+
Misma X-Idempotency-Key
+
2 solicitudes
=
1 único pago
```

Esta capacidad evita que un reintento técnico se transforme en un nuevo cobro.

---

## 2. Escenario de falso verde

BANKPULSE puede permanecer técnicamente disponible:

```text
Payments API      UP
Base de datos     UP
Docker            healthy
HTTP              disponible
Health check      UP
```

y, al mismo tiempo, incumplir la capacidad del negocio.

El escenario seleccionado es:

```text
Request #1
Idempotency-Key = ABC
        |
        v
Payment A

Request #2
Idempotency-Key = ABC
        |
        v
Payment B
```

El resultado es:

```text
Tecnología = VERDE

pero

Negocio = ROJO
```

La plataforma continúa respondiendo, pero una misma intención de pago genera
dos pagos diferentes.

Eso constituye el **falso verde**.

---

## 3. Riesgo / pérdida potencial

Un defecto de idempotencia puede producir:

- cobros duplicados;
- pérdida financiera;
- reclamos de clientes;
- necesidad de reversos;
- costos operativos adicionales;
- inconsistencias de auditoría;
- pérdida de confianza en la plataforma.

Por esta razón, comprobar únicamente que el sistema está disponible no es
suficiente.

BANKPULSE también debe producir evidencia automática de que mantiene el
comportamiento crítico del negocio.

---

## 4. Release Gate

Se implementó un Release Gate dentro de GitHub Actions.

El flujo utilizado es:

```text
Feature Branch
      |
      v
Commit / Push
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

El script:

1. verifica que Payments API esté disponible;
2. genera una solicitud de pago;
3. reintenta la misma operación con la misma `X-Idempotency-Key`;
4. compara los identificadores de ambos pagos;
5. valida que exista una sola operación correspondiente;
6. permite o bloquea el release.

La condición de aceptación es:

```text
Same Idempotency-Key
-> 2 requests
-> 1 payment
```

---

# 5. Épica y KPIs estratégicos

## 5.1 Épica seleccionada

Para complementar el Release Gate con observabilidad de negocio se seleccionó
la épica:

> **Social Split para consumo colaborativo**

El objetivo es permitir que varios socios distribuyan el costo de una
experiencia compartida, autoricen su participación y completen la operación
colectiva únicamente cuando se cumplan las reglas del negocio.

El bounded context principal es:

```text
SOCIAL SPLIT
```

Dentro de este contexto se manejan conceptos como:

```text
Split Session
Participantes
Monto compartido
Autorizaciones
Estado de la operación
Cierre del consumo compartido
```

La relación conceptual utilizada es:

```text
SOCIAL SPLIT
sesión + participantes + autorizaciones
             |
             v
PAYMENTS / CORE FINANCIERO
procesamiento del pago
             |
             v
AUDIT
trazabilidad
```

---

## 5.2 KPI 1 — Tasa de cierre exitoso de consumos compartidos

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

### Valor observado en la prueba

```text
100 %
```

### Interpretación

Durante el escenario controlado, todas las operaciones Social Split iniciadas
por la prueba llegaron correctamente a `COMPLETED`.

---

## 5.3 KPI 2 — Tasa de adhesión de participantes

### Pregunta de negocio

¿Qué porcentaje de las personas incorporadas al consumo compartido acepta y
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

### Valor observado en la prueba

```text
100 %
```

### Interpretación

Los dos participantes incorporados al escenario automatizado autorizaron su
participación.

---

## 5.4 KPI 3 — Tiempo promedio de cierre

### Pregunta de negocio

¿Cuánto tiempo necesita un grupo para completar una operación compartida desde
su creación hasta su cierre?

### Fórmula

```text
Suma de tiempos de cierre
-------------------------
Operaciones completadas
```

### Métricas

```text
bankpulse_social_split_sessions_close_duration_seconds_sum
bankpulse_social_split_sessions_close_duration_seconds_count
```

El modelo registra:

```text
createdAt
completedAt
```

por lo que:

```text
duración = completedAt - createdAt
```

### Valor observado en la prueba

```text
aproximadamente 1.17 segundos
```

---

## 5.5 KPI 4 — Tasa de intentos de cierre bloqueados por autorización incompleta

### Pregunta de negocio

¿Qué porcentaje de los intentos de concretar una operación compartida debe ser
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

### Valor observado en la prueba

```text
50 %
```

### Interpretación

La prueba realiza deliberadamente dos intentos de cierre:

```text
Intento #1
faltan autorizaciones
-> BLOCKED

Intento #2
todos autorizaron
-> COMPLETED
```

Por tanto:

```text
1 cierre bloqueado
------------------
2 intentos

= 50 %
```

Este valor no representa una meta comercial.

Demuestra que la regla que evita cerrar prematuramente una operación Social
Split está funcionando.

---

## 5.6 KPI 5 — Tasa de integridad de distribución del monto

### Pregunta de negocio

¿Qué porcentaje de las operaciones distribuye correctamente el monto total
acordado entre sus participantes?

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

Para este laboratorio se considera una distribución válida cuando:

```text
suma de shareAmount
=
totalAmount
```

El escenario automatizado utiliza:

```text
Monto total = USD 100

Participante A = USD 40
Participante B = USD 60

40 + 60 = 100
```

### Valor observado en la prueba

```text
100 %
```

Esta validación comprueba la distribución del monto dentro de Social Split.

La validación completa de que cada `paymentReference` corresponde a una
transacción financiera real pertenece al contexto Payments.

---

# 6. Instrumentación de los KPIs

Los KPIs fueron instrumentados utilizando:

```text
Spring Boot Actuator
Micrometer
Prometheus
Grafana
```

La cadena implementada es:

```text
Épica Social Split
        |
        v
Reglas del dominio
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

Prometheus recolecta las métricas desde:

```text
social-split-api:8086
```

Se creó el script:

```text
scripts/business-kpi-social-split.sh
```

que ejecuta automáticamente:

```text
Crear Social Split de USD 100
        |
        v
Agregar participante A = USD 40
Agregar participante B = USD 60
        |
        v
Intentar cerrar sin autorización
        |
        v
BLOCK
        |
        v
Autorizar A y B
        |
        v
Cerrar Social Split
        |
        v
COMPLETED
        |
        v
Validar 5 KPI
```

El resultado obtenido fue:

```text
KPI 1 PASS - Social Split completed
KPI 2 PASS - Participants authorized
KPI 3 PASS - Completion time observed
KPI 4 PASS - Premature close blocked
KPI 5 PASS - Financial distribution balanced

BUSINESS KPI GATE: PASS
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

Los valores observados durante la prueba fueron:

| KPI | Resultado |
|---|---:|
| Cierre exitoso de consumos compartidos | 100 % |
| Adhesión de participantes | 100 % |
| Tiempo promedio de cierre | 1.17 s |
| Cierres bloqueados por autorización incompleta | 50 % |
| Integridad de distribución del monto | 100 % |

Estos valores corresponden a un escenario automatizado y controlado.

No se definieron umbrales comerciales artificiales porque el laboratorio no
establece SLA o metas oficiales para estos indicadores.

---

# 8. Integración con CI

El workflow:

```text
.github/workflows/ci.yml
```

incluye actualmente:

```text
ADR governance
Architecture contract
Build and start BANKdragon
Business release gate - payment idempotency
Business KPI gate - Social Split
Domain and regression smoke tests
Prometheus
Grafana
Validate Social Split KPIs in Prometheus
```

De esta forma, el pipeline no valida únicamente:

```text
¿compila?
¿está UP?
¿responde HTTP?
```

sino también:

```text
¿conserva el comportamiento crítico del negocio?
¿expone las señales estratégicas esperadas?
```

---

# 9. PR exitoso inicial

Antes de provocar deliberadamente el falso verde se ejecutó correctamente el
Release Gate de Payments.

En el PR correspondiente, GitHub Actions terminó con:

```text
ADR governance                         PASS
Architecture contract                  PASS
Build, integration and observability   PASS
```

Dentro del job de integración:

```text
Build and start BANKdragon V2                 PASS
Validate interactive edge UI                  PASS
Business release gate - payment idempotency   PASS
Domain and regression smoke tests             PASS
Start Prometheus and Grafana                  PASS
Validate observability endpoints              PASS
```

El Business Release Gate confirmó:

```text
Payments API: UP

Same Idempotency-Key
-> 2 requests
-> 1 payment

BUSINESS RELEASE GATE: PASS
```

Esto representa el comportamiento correcto previo al experimento.

---

# 10. PR de KPIs y observabilidad

Posteriormente se incorporaron los cinco KPIs de Social Split al pipeline.

El PR de KPIs terminó con:

```text
ADR governance                         PASS
Architecture contract                  PASS
Build, integration and observability   PASS
```

Además se incorporó un ADR para documentar la decisión de observar el
bounded context Social Split mediante métricas de negocio, Prometheus y
Grafana.

El pipeline verificó:

```text
Business release gate - payment idempotency   PASS
Business KPI gate - Social Split              PASS
Validate Social Split KPIs in Prometheus      PASS
```

---

# 11. Falso verde provocado

Para demostrar el falso verde se creó la rama:

```text
feature/false-green-experiment
```

Se introdujo deliberadamente un defecto en:

```text
services/payments-api/src/main/java/com/bankpulse/payments/PaymentService.java
```

La implementación correcta utiliza:

```java
payments.findByIdempotencyKey(idempotencyKey)
```

para devolver el pago existente cuando recibe nuevamente la misma intención.

Durante el experimento se ignoró deliberadamente esa regla y se generó una
clave interna diferente en cada solicitud.

Conceptualmente:

```text
Request #1
Idempotency-Key = ABC
        |
        v
ABC-fault-1
        |
        v
Payment A

Request #2
Idempotency-Key = ABC
        |
        v
ABC-fault-2
        |
        v
Payment B
```

La API continuó técnicamente saludable.

Docker mostró:

```text
payments-api
Up
healthy
```

El Business Release Gate también comprobó:

```text
Payments API: UP
```

Sin embargo, al repetir la misma operación produjo:

```text
RELEASE BLOCKED: retry created a different payment

First payment:
5a7e6c96-3313-44e5-b789-21774651b21b

Second payment:
0ad7a7f3-2f1c-4539-9a00-d4d0e1e7460c
```

Por tanto:

```text
Tecnología = VERDE

Negocio = ROJO
```

---

# 12. Evidencia del bloqueo

La versión defectuosa fue enviada mediante Pull Request.

Los controles de arquitectura continuaron aprobando:

```text
ADR governance          PASS
Architecture contract   PASS
```

Sin embargo:

```text
Build, integration and observability   FAIL
```

Dentro del job, la infraestructura alcanzó correctamente el estado esperado,
pero falló:

```text
Business release gate - payment idempotency   FAIL
```

El Release Gate produjo:

```text
Payments API: UP
```

seguido de:

```text
RELEASE BLOCKED:
retry created a different payment
```

Por tanto, CI evitó que una versión técnicamente saludable pero incorrecta
desde el punto de vista del negocio pudiera ser aceptada.

---

# 13. Diagnóstico

El diagnóstico mostró que la falla no correspondía a:

```text
Docker
Base de datos
Health check
Disponibilidad de Payments API
HTTP
```

La causa pertenecía a la lógica de negocio.

La versión defectuosa ignoraba la `X-Idempotency-Key` recibida y generaba una
clave distinta para cada ejecución.

Por tanto, una misma intención lógica era interpretada como operaciones
diferentes.

La causa raíz fue:

> **Pérdida de la propiedad de idempotencia en PaymentService.**

---

# 14. Corrección

Se restauró la implementación original de `PaymentService`.

La lógica correcta volvió a utilizar:

```java
return payments.findByIdempotencyKey(idempotencyKey)
    .orElseGet(() -> persist(idempotencyKey, request));
```

La regla volvió a ser:

```text
Misma Idempotency-Key
        |
        v
¿Existe el pago?
   |          |
  SÍ         NO
   |          |
   v          v
devolver     crear
el mismo     uno nuevo
pago
```

Después de la corrección se ejecutó nuevamente el Business Release Gate.

El resultado volvió a ser:

```text
Payments API: UP

Same Idempotency-Key
-> 2 requests
-> 1 payment

BUSINESS RELEASE GATE: PASS
```

---

# 15. Ejecución final

Después de corregir la idempotencia, el mismo Pull Request fue ejecutado
nuevamente.

La ejecución final terminó:

```text
ADR governance                         PASS
Architecture contract                  PASS
Build, integration and observability   PASS
```

El pipeline completo volvió a estado verde.

Esto demuestra el ciclo requerido:

```text
Sistema correcto
        |
        v
CI PASS
        |
        v
Defecto deliberado
        |
        v
Tecnología UP
Negocio incorrecto
        |
        v
Business Release Gate
BLOCK
        |
        v
Diagnóstico
        |
        v
Corrección
        |
        v
CI nuevamente
        |
        v
PASS
```

---

# 16. Evidencia resumida

## Estado correcto inicial

```text
Technical Health      PASS
Payment Business Gate PASS
```

## Falso verde

```text
Payments API          UP
Docker                healthy
Business behavior     FAIL
Release Gate          BLOCK
```

## Estado corregido

```text
ADR Governance        PASS
Architecture Contract PASS
Payment Business Gate PASS
Social Split KPI Gate PASS
Prometheus            PASS
Grafana               PASS
Pipeline final        PASS
```

---

# 17. Conclusión

El ejercicio demuestra que:

> **Disponibilidad técnica no significa comportamiento correcto del negocio.**

BANKPULSE puede mantener:

```text
API UP
Docker healthy
Base de datos UP
HTTP disponible
Health checks verdes
```

y simultáneamente producir:

```text
dos pagos
para una misma intención
```

El Release Gate permite detectar esa diferencia antes de aceptar la versión.

Además, la incorporación de los cinco KPIs de Social Split amplía la
observabilidad desde métricas puramente técnicas hacia señales relacionadas con
el valor del negocio.

El recorrido implementado queda:

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
Business Tests
 |
 v
CI / Release Gate
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

El resultado final no busca demostrar únicamente que BANKPULSE está
encendido.

Busca producir evidencia automática de que, **mientras permanece disponible,
continúa cumpliendo las promesas críticas que hizo al negocio**.