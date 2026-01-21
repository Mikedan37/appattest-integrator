# PID Control Loop Schematic

Closed-loop feedback control for admission rate regulation based on observed backend latency.

**References:**
- `ADMISSION_CONTROL_PID.md`: Complete admission control documentation
- `CONTROL_TEST_PLAN.md`: Step-response validation methodology
- `CONTROL_MODEL.md`: Supervisory control model (protocol sequencing)

## 1. Scope

This document schematics the closed-loop PID control system used for optional admission control in appattest-integrator. The controller measures backend latency, computes admission rate using PID control, and gates flow-mutating endpoints to maintain target latency.

This is a discrete-time sampled-data control system operating at fixed intervals $\Delta t$.

## 2. Signals and Variables

| Symbol | Description | Units | Source |
|--------|-------------|-------|--------|
| $r$ | Setpoint (target latency) | ms | Configuration |
| $L(t)$ | Measured backend latency | ms | BackendClient instrumentation |
| $y(t)$ | Filtered latency (EWMA output) | ms | EWMAFilter |
| $e(t)$ | Error signal ($r - y(t)$) | ms | Controller computation |
| $u(t)$ | Controller output (computed rate) | tokens/sec | PIDController |
| $u'(t)$ | Saturated controller output | tokens/sec | Saturation/clip |
| $n(t)$ | Effective concurrency | flows | Plant state |
| $d(t)$ | Disturbance | ms | External (network, CPU, retries) |
| $\lambda(t)$ | Admission rate (controlled) | flows/interval | TokenBucket |
| $\mu(t)$ | Completion rate | flows/interval | Plant output |
| $\Delta t$ | Sampling period | seconds | Configuration (default: 0.5s) |
| $\alpha$ | EWMA smoothing factor | dimensionless | Configuration (default: 0.2) |
| $K_p, K_i, K_d$ | PID gains | various | Configuration |

## 3. Closed-Loop Block Diagram

```mermaid
flowchart TB
    subgraph Ref["Reference"]
        R[Setpoint r<br/>target_latency_ms]
    end
    
    subgraph Sum["Summing Junction"]
        SUM[+]
        MINUS[-]
    end
    
    subgraph Ctrl["Controller"]
        PID[PID Controller<br/>C(z)<br/>Kp, Ki, Kd]
    end
    
    subgraph Act["Actuator"]
        SAT[Saturation<br/>clip(u, umin, umax)]
        TB[Token Bucket<br/>u' tokens/sec]
    end
    
    subgraph Plant["Plant"]
        ADM[Admission Gate<br/>Routes.swift]
        CONC[Concurrency n(t)]
        BE[Backend<br/>Latency L(t)]
    end
    
    subgraph Sensor["Sensor/Filter"]
        EWMA[EWMA Filter<br/>F(z)<br/>α smoothing]
    end
    
    subgraph Dist["Disturbance"]
        D[d(t)<br/>jitter/retries/CPU]
    end
    
    R -->|r| SUM
    SUM -->|e(t) = r - y(t)| PID
    PID -->|u(t)| SAT
    SAT -->|u'(t)| TB
    TB -->|λ(t)| ADM
    ADM -->|n(t)| CONC
    CONC --> BE
    D -->|+| BE
    BE -->|L(t)| EWMA
    EWMA -->|y(t)| MINUS
    MINUS -->|y(t)| SUM
    
    style PID fill:#e1f5ff,stroke:#01579b,stroke-width:3px
    style EWMA fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style BE fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    style SUM fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
```

**Feedback path:** $y(t) \rightarrow \text{EWMA} \rightarrow \text{Summing Junction} \rightarrow e(t) \rightarrow \text{PID} \rightarrow u(t) \rightarrow u'(t) \rightarrow \text{Token Bucket} \rightarrow \lambda(t) \rightarrow n(t) \rightarrow L(t) \rightarrow y(t)$

The loop is closed: filtered latency measurement feeds back to the summing junction, completing the control loop.

## 4. Mathematical Model

### Discrete-Time Index

$$ t \in \mathbb{N}, \quad \text{sampled every } \Delta t \text{ milliseconds} $$

Time advances in discrete steps. Each control update occurs at intervals of $\Delta t$ (default: 500ms).

### Sensor: EWMA Filter

Measured backend latency is filtered using exponentially-weighted moving average:

$$ y(t) = \alpha L(t) + (1-\alpha) y(t-1) $$

Where:
- $L(t)$: Measured backend latency at time $t$ (milliseconds)
- $\alpha \in (0,1]$: Smoothing factor (default: 0.2)
- $y(t)$: Filtered latency output (milliseconds)

The filter smooths transient spikes and provides stable measurement for control.

### Error Signal

$$ e(t) = r - y(t) $$

Where:
- $r$: Setpoint (target latency, default: 200ms)
- $y(t)$: Filtered latency measurement
- $e(t)$: Error (positive when latency below target, negative when above)

### PID Controller

#### Positional Form

$$ u(t) = K_p e(t) + K_i \sum_{i=0}^{t} e(i) \Delta t + K_d \frac{e(t) - e(t-1)}{\Delta t} $$

Where:
- $K_p$: Proportional gain (default: 0.5)
- $K_i$: Integral gain (default: 0.05)
- $K_d$: Derivative gain (default: 0.1)
- $\Delta t$: Sampling period (seconds)

#### Incremental (Velocity) Form

$$ \Delta u(t) = K_p \big(e(t) - e(t-1)\big) + K_i e(t) \Delta t + K_d \frac{e(t) - 2e(t-1) + e(t-2)}{\Delta t} $$

$$ u(t) = u(t-1) + \Delta u(t) $$

The incremental form is preferred for discrete implementations as it reduces integral windup issues and provides smoother control action.

**Note:** The current implementation uses positional form. Incremental form is documented for reference and potential future use.

## 5. Controller Implementation Form

The controller computes terms separately:

$$ P(t) = K_p e(t) $$

$$ I(t) = K_i \sum_{i=0}^{t} e(i) \Delta t = I(t-1) + K_i e(t) \Delta t $$

$$ D(t) = K_d \frac{e(t) - e(t-1)}{\Delta t} $$

$$ u(t) = P(t) + I(t) + D(t) $$

Terms are exposed for observability (metrics/logging).

## 6. Saturation + Anti-Windup

### Saturation

Controller output is clipped to valid range:

$$ u'(t) = \text{clip}(u(t), u_{\min}, u_{\max}) $$

Where:
- $u_{\min}$: Minimum admission rate (default: 1 TPS)
- $u_{\max}$: Maximum admission rate (default: 200 TPS)

### Anti-Windup (Back-Calculation)

When saturation occurs ($u(t) \ne u'(t)$), the integrator is back-calculated to prevent windup:

$$ I(t) = \frac{u'(t) - P(t) - D(t)}{K_i} $$

$$ \text{integral}(t) = \frac{I(t)}{\Delta t} $$

This resets the integrator state such that $P(t) + I(t) + D(t) = u'(t)$, preventing unbounded integral accumulation during saturation.

**Implementation:** When `output != clippedOutput` in `PIDController.compute()`, the integrator is reset to match the saturated output.

## 7. Plant Approximation + Disturbances

### Plant Model

Backend latency is approximated as:

$$ L(t) \approx L_0 + b \cdot n(t) + d(t) $$

Where:
- $L_0$: Base latency (milliseconds)
- $b$: Latency per concurrent flow (milliseconds/flow)
- $n(t)$: Effective concurrency (number of concurrent flows)
- $d(t)$: Disturbance (network jitter, CPU spikes, client retries)

### Concurrency Evolution

$$ n(t+1) = n(t) + \lambda(t) - \mu(t) $$

Where:
- $\lambda(t)$: Admission rate (flows per interval, controlled by token bucket fill rate $u'(t)$)
- $\mu(t)$: Completion rate (completed flows per interval)

**Actuation:** The token bucket refill rate $u'(t)$ controls admission rate $\lambda(t)$, which affects concurrency $n(t)$, which affects latency $L(t)$.

### Disturbances

Disturbance $d(t)$ includes:
- Network jitter
- CPU spikes
- Client retry storms
- Backend processing delays

Disturbances are not controlled but are observed and rejected by the controller.

## 8. Stability/Performance Metrics

### Overshoot

$$ M_p = \frac{y_{\max} - r}{r} $$

Maximum percentage overshoot above setpoint after step input.

**Expected:** $M_p < 20\%$ for typical tuning.

### Settling Time

$$ T_s = \min\{t: |y(t) - r| < \epsilon r \quad \forall t' \ge t\} $$

Time to converge within tolerance $\epsilon$ (e.g., 5%).

**Expected:** $T_s < 10$ seconds for step changes.

### Steady-State Error

$$ e_{ss} = \lim_{t \to \infty} (r - y(t)) $$

Final error after settling.

**Expected:** $e_{ss} < 5\%$ of setpoint (integral term eliminates steady-state error).

### Disturbance Rejection

The derivative term $K_d$ provides disturbance rejection by responding to rate of change:

$$ D(t) = K_d \frac{e(t) - e(t-1)}{\Delta t} $$

When latency spikes suddenly (disturbance), the derivative term provides immediate corrective action proportional to the rate of change.

**Expected:** System recovers to within 10% of setpoint within 5 seconds of bounded disturbance.

### Bounded Output Under Bounded Disturbance

$$ |d(t)| < D \Rightarrow |y(t)| < Y $$

For bounded disturbance $D$, output remains bounded $Y$.

**Expected:** $Y < 2r$ (output never exceeds 2x setpoint under bounded disturbance).

### Discrete-Time Boundedness

$$ \exists\, M < \infty \;\text{s.t.}\; |u(t)| \le M \quad \forall t $$

Controller output is bounded by saturation limits: $u_{\min} \le u'(t) \le u_{\max}$.

## 9. Mapping: Signal → Code

| Signal | Code Artifact | File |
|--------|---------------|------|
| $r$ | `APP_ATTEST_TARGET_LATENCY_MS` env var | `ControlConfig.swift` |
| $L(t)$ | Measured latency per route | `BackendClient.swift` (instrumentation) |
| $y(t)$ | `EWMAFilter.update()` return value | `EWMAFilter.swift` |
| $e(t)$ | `pid.error` property | `PIDController.swift` |
| $P(t)$ | `pid.pTerm` property | `PIDController.swift` |
| $I(t)$ | `pid.iTerm` property | `PIDController.swift` |
| $D(t)$ | `pid.dTerm` property | `PIDController.swift` |
| $u(t)$ | `pid.compute()` return value | `PIDController.swift` |
| $u'(t)$ | `tokenBucket.updateFillRate()` argument | `TokenBucket.swift` |
| $\lambda(t)$ | Token bucket fill rate | `TokenBucket.swift` |
| Admission decision | `admissionController.tryAdmit()` | `AdmissionController.swift` |
| Gate enforcement | Route handlers check `tryAdmit()` | `Routes.swift` |
| Metrics | `ControlMetrics` actor | `ControlMetrics.swift` |
| Configuration | `ControlConfig` struct | `ControlConfig.swift` |

**Implementation flow:**
1. `BackendClient` measures latency $L(t)$ per route
2. `AdmissionController.recordLatency()` filters via `EWMAFilter`, computes PID via `PIDController`
3. `PIDController.compute()` returns $u(t)$, applies saturation
4. `TokenBucket.updateFillRate()` receives $u'(t)$
5. `Routes.swift` gates endpoints via `admissionController.tryAdmit()`
6. `ControlMetrics` records all signals for observability

## 10. Loop Closure

The control loop is closed as follows:

1. **Measurement:** Backend latency $L(t)$ is measured per request in `BackendClient` (register, client-data-hash, verify routes).

2. **Filtering:** Measured latency is filtered via EWMA: $y(t) = \alpha L(t) + (1-\alpha) y(t-1)$.

3. **Error computation:** Error is computed: $e(t) = r - y(t)$ where $r$ is target latency.

4. **Controller action:** PID controller computes admission rate: $u(t) = K_p e(t) + K_i \sum e(i) \Delta t + K_d (e(t)-e(t-1))/\Delta t$.

5. **Saturation:** Controller output is clipped: $u'(t) = \text{clip}(u(t), u_{\min}, u_{\max})$.

6. **Actuation:** Token bucket fill rate is updated to $u'(t)$, controlling admission rate $\lambda(t)$.

7. **Plant response:** Admission rate affects concurrency $n(t+1) = n(t) + \lambda(t) - \mu(t)$, which affects latency $L(t) \approx L_0 + b \cdot n(t) + d(t)$.

8. **Feedback:** Measured latency $L(t)$ feeds back to step 1, closing the loop.

The loop is closed: filtered latency measurement $y(t)$ feeds back to the summing junction, completing the control loop.

## 11. Validation Plan

### Step Response Testing

1. Establish steady state at baseline load
2. Apply step change (increase load or base latency)
3. Measure:
   - Overshoot $M_p$
   - Settling time $T_s$
   - Steady-state error $e_{ss}$
4. Verify boundedness and no integral windup

See `CONTROL_TEST_PLAN.md` for detailed methodology.

### Disturbance Rejection Testing

1. Maintain constant load
2. Inject disturbance (latency spike)
3. Measure:
   - Maximum deviation
   - Recovery time
   - Steady-state return

See `Tests/AppAttestIntegratorTests/Control/DisturbanceRejectionTests.swift` for implementation.

### Implementation Tests

- `StepResponseTests.swift`: Step response validation
- `DisturbanceRejectionTests.swift`: Disturbance rejection and plant model simulation

## 12. Non-Goals

This control loop:
- Does not make cryptographic verification decisions
- Does not make trust or authorization decisions
- Does not evaluate policy
- Only controls admission rate based on observed latency

These responsibilities belong to other subsystems.
