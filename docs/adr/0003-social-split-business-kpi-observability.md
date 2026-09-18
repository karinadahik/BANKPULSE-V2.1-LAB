# 3. Social Split business KPI observability

Date: 2026-09-17

## Status

Accepted

## Context

BANKPULSE includes the Social Split business capability, where multiple
participants distribute and authorize a shared consumption operation.

Technical health indicators such as container availability, CPU, memory or
HTTP responses are not sufficient to determine whether this business
capability is delivering value correctly.

The Social Split epic requires observable evidence of participant
authorization, successful completion, completion time, protection against
premature closure and integrity of the distributed amount.

The platform already uses Micrometer, Spring Boot Actuator, Prometheus and
Grafana, making it possible to expose business-level signals in addition to
technical infrastructure metrics.

## Decision

BANKPULSE will expose business metrics for the Social Split bounded context
using Micrometer through Spring Boot Actuator.

Five business KPIs will be observed:

1. Successful Social Split completion rate.
2. Participant authorization rate.
3. Average Social Split completion time.
4. Rate of close attempts blocked because authorization is incomplete.
5. Integrity rate of the distributed shared amount.

Prometheus will collect these metrics from `social-split-api`.

Grafana will visualize them through the dashboard:

`BANKdragon — Social Split Business KPIs`

The CI pipeline will execute an automated Social Split Business KPI Gate and
will verify that the corresponding metrics are available in Prometheus.

## Consequences

Business behavior becomes observable independently from infrastructure health.

The CI pipeline can validate that the Social Split capability exposes the
expected business signals before accepting a change.

Prometheus and Grafana become part of the evidence used to evaluate the
behavior of the Social Split bounded context.

The Social Split domain model records completion time so that the duration of
a successful shared consumption operation can be measured.

The platform gains additional instrumentation and dashboard maintenance
responsibilities.

Changes to the business meaning of these KPIs may require corresponding
updates to the metrics, CI validation and Grafana dashboard.
