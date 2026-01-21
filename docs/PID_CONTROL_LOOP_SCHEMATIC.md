# PID Control Loop Schematic

Closed-loop feedback control for admission rate regulation based on observed backend latency.

## System Overview

The integrator implements a discrete-time PID controller that adjusts flow admission rate to maintain target backend latency. This is a closed-loop control system: measured latency feeds back to the controller, which adjusts admission rate, which affects latency.

## Control-System Block Diagram

```mermaid
flowchart LR
    subgraph Reference["Reference Input"]
        R[Setpoint r<br/>target_latency_ms]
    end
    
    subgraph Summing["Summing Junction"]
        SUM[+]
        MINUS[-]
    end
    
    subgraph Controller["Controller"]
        PID[PID Controller<br/>C(z)<br/>Kp, Ki, Kd]
    end
    
    subgraph Actuator["Actuator"]
        SAT[Saturation<br/>clip(u, umin, umax)]
        TB[Token Bucket<br/>u' tokens/sec]
    end
    
    subgraph Plant["Plant"]
        ADM[Admission<br/>n(t) flows]
        BE[Backend<br/>Latency L(t)]
    end
    
    subgraph Sensor["Sensor/Filter"]
        EWMA[EWMA Filter<br/>F(z)<br/>α smoothing]
    end
    
    subgraph Disturbance["Disturbance"]
        D[d(t)<br/>jitter/retries/CPU]
    end
    
    R -->|r| SUM
    SUM -->|e(t) = r - y(t)| PID
    PID -->|u(t)| SAT
    SAT -->|u'(t)| TB
    TB -->|admission rate| ADM
    ADM -->|concurrency n(t)| BE
    D -->|+| BE
    BE -->|L(t)| EWMA
    EWMA -->|y(t)| MINUS
    MINUS -->|y(t)| SUM
    
    style PID fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    style EWMA fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style BE fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
```

**Key signals:**
- \(r\): Setpoint (target latency in milliseconds)
- \(y(t)\): Measured output (EWMA-filtered latency)
- \(e(t)\): Error signal (\(r - y(t)\))
- \(u(t)\): Controller output (computed admission rate)
- \(u'(t)\): Actuator output (saturated admission rate, tokens/sec)
- \(n(t)\): Effective concurrency (admitted flows)
- \(L(t)\): Measured backend latency (milliseconds)
- \(d(t)\): Disturbance (network jitter, client retries, CPU spikes)

**Update period:** \(\Delta t\) (control interval, default 500ms)

## Mathematical Model

### Discrete-Time Index

\[ t \in \mathbb{N}, \quad \text{sampled every } \Delta t \text{ milliseconds} \]

Time advances in discrete steps corresponding to control update intervals.

### Sensor: EWMA Filter

Measured backend latency is filtered using exponentially-weighted moving average:

\[ y(t) = \alpha \cdot L(t) + (1-\alpha) \cdot y(t-1) \]

Where:
- \(L(t)\): Measured backend latency at time \(t\) (milliseconds)
- \(\alpha \in (0,1]\): Smoothing factor (default: 0.2)
- \(y(t)\): Filtered latency output (milliseconds)

The filter smooths transient spikes and provides stable measurement for control.

### Error Signal

\[ e(t) = r - y(t) \]

Where:
- \(r\): Setpoint (target latency, default: 200ms)
- \(y(t)\): Filtered latency measurement
- \(e(t)\): Error (positive when latency below target, negative when above)

### PID Controller

#### Positional Form

\[ u(t) = K_p e(t) + K_i \sum_{i=0}^{t} e(i) \Delta t + K_d \frac{e(t) - e(t-1)}{\Delta t} \]

Where:
- \(K_p\): Proportional gain (default: 0.5)
- \(K_i\): Integral gain (default: 0.05)
- \(K_d\): Derivative gain (default: 0.1)
- \(\Delta t\): Sampling period (seconds)

#### Incremental (Velocity) Form

\[ \Delta u(t) = K_p (e(t) - e(t-1)) + K_i e(t) \Delta t + K_d \frac{e(t) - 2e(t-1) + e(t-2)}{\Delta t} \]

\[ u(t) = u(t-1) + \Delta u(t) \]

The incremental form is preferred for implementation stability and reduces integral windup issues.

### Saturation and Anti-Windup

Controller output is clipped to valid range:

\[ u'(t) = \text{clip}(u(t), u_{\min}, u_{\max}) \]

Where:
- \(u_{\min}\): Minimum admission rate (default: 1 TPS)
- \(u_{\max}\): Maximum admission rate (default: 200 TPS)

**Anti-windup (back-calculation):**

When saturation occurs, the integrator is back-calculated to prevent windup:

\[ I(t+1) = I(t) + e(t) \Delta t + K_{aw} (u'(t) - u(t)) \]

Where \(K_{aw} = 1/K_i\) (back-calculation gain).

In the implementation, when \(u(t) \ne u'(t)\), the integrator is reset to:

\[ I(t) = \frac{u'(t) - P(t) - D(t)}{K_i} \]

This prevents unbounded integral accumulation during saturation.

### Plant Model

Backend latency is approximated as:

\[ L(t) \approx L_0 + b \cdot n(t) + d(t) \]

Where:
- \(L_0\): Base latency (milliseconds)
- \(b\): Latency per concurrent flow (milliseconds/flow)
- \(n(t)\): Effective concurrency (number of concurrent flows)
- \(d(t)\): Disturbance (network jitter, CPU spikes, client retries)

**Concurrency evolution:**

\[ n(t+1) = n(t) + u'(t) - c(t) \]

Where:
- \(u'(t)\): Admission rate (flows per interval)
- \(c(t)\): Completion rate (completed flows per interval)

**Actuation:** The token bucket refill rate \(u'(t)\) controls admission, which affects concurrency \(n(t)\), which affects latency \(L(t)\).

## Signal-to-Code Mapping

| Signal | Code Artifact | Location |
|--------|---------------|----------|
| \(r\) | `APP_ATTEST_TARGET_LATENCY_MS` | `ControlConfig.swift` |
| \(y(t)\) | `EWMAFilter.update()` output | `EWMAFilter.swift` |
| \(e(t)\) | `pid.error` | `PIDController.swift` |
| \(u(t)\) | `pid.compute()` output | `PIDController.swift` |
| \(u'(t)\) | `tokenBucket.updateFillRate()` | `TokenBucket.swift` |
| \(L(t)\) | Measured latency per route | `BackendClient.swift` |
| \(d(t)\) | Observed disturbances | External (network, CPU, retries) |
| \(\alpha\) | `APP_ATTEST_EWMA_ALPHA` | `ControlConfig.swift` |
| \(K_p, K_i, K_d\) | `APP_ATTEST_PID_KP/KI/KD` | `ControlConfig.swift` |
| \(\Delta t\) | `APP_ATTEST_CONTROL_DT_MS` | `ControlConfig.swift` |

**Implementation modules:**
- `ControlConfig.swift`: Configuration and environment variable parsing
- `EWMAFilter.swift`: Latency smoothing filter
- `PIDController.swift`: Discrete-time PID control
- `AdmissionController.swift`: Controller orchestration and latency recording
- `TokenBucket.swift`: Rate-limiting actuator
- `BackendClient.swift`: Latency measurement instrumentation
- `Routes.swift`: Admission gating on flow-mutating endpoints
- `ControlMetrics.swift`: Prometheus metrics for observability

## Stability and Behavior Expectations

### Overshoot

\[ M_p = \frac{y_{\max} - r}{r} \]

Maximum percentage overshoot above setpoint after step input.

**Expected:** \(M_p < 20\%\) for typical tuning.

### Settling Time

\[ T_s = \min\{t: |y(t) - r| < \epsilon r \quad \forall t' \ge t\} \]

Time to converge within tolerance \(\epsilon\) (e.g., 5%).

**Expected:** \(T_s < 10\) seconds for step changes.

### Steady-State Error

\[ e_{ss} = \lim_{t \to \infty} |y(t) - r| \]

Final error after settling.

**Expected:** \(e_{ss} < 5\%\) of setpoint (integral term eliminates steady-state error).

### Disturbance Rejection

The derivative term \(K_d\) provides disturbance rejection by responding to rate of change in latency:

\[ D(t) = K_d \frac{e(t) - e(t-1)}{\Delta t} \]

When latency spikes suddenly (disturbance), the derivative term provides immediate corrective action proportional to the rate of change.

**Expected:** System recovers to within 10% of setpoint within 5 seconds of bounded disturbance.

### Bounded Output Under Bounded Disturbance

\[ |d(t)| < D \Rightarrow |y(t)| < Y \]

For bounded disturbance \(D\), output remains bounded \(Y\).

**Expected:** \(Y < 2r\) (output never exceeds 2x setpoint under bounded disturbance).

## Validation

Step-response testing validates controller behavior:

1. Apply step change in load or base latency
2. Measure overshoot \(M_p\)
3. Measure settling time \(T_s\)
4. Verify boundedness and no integral windup

See `CONTROL_TEST_PLAN.md` for detailed test methodology and `Tests/AppAttestIntegratorTests/Control/StepResponseTests.swift` for implementation.

## Non-Goals

This control loop:
- Does not make cryptographic verification decisions
- Does not make trust or authorization decisions
- Does not evaluate policy
- Only controls admission rate based on observed latency

These responsibilities belong to other subsystems.

## References

- `ADMISSION_CONTROL_PID.md`: Complete admission control documentation
- `CONTROL_MODEL.md`: Supervisory control model (protocol sequencing)
- `CONTROL_TEST_PLAN.md`: Step-response validation methodology
