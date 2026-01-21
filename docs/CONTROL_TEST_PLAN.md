# Test as System Identification + Step Response

## Problem Statement

Everyone claims stability. Nobody measures it.

Without empirical validation, control systems may:
- Oscillate under load
- Fail to converge to setpoint
- Exhibit unbounded behavior under disturbance

## Solution: Step Response Testing

Define setpoint, perturb system, measure response, prove boundedness empirically.

## Methodology

### 1. Define Setpoint

Set target latency:

\[ r = \text{target latency} \quad \text{(e.g., 100 ms)} \]

### 2. Perturb System (Step Input)

Apply step change in load:

\[ u(t) = \begin{cases} u_0 & t < t_0 \\ u_1 & t \ge t_0 \end{cases} \]

Where:
- \(u_0\): Baseline load (e.g., 10 flows/sec)
- \(u_1\): Step load (e.g., 100 flows/sec)
- \(t_0\): Step time

### 3. Measure Response

Record:
- Latency \(y(t)\) over time
- Admission rate \(u'(t)\) over time
- Overshoot \(M_p\)
- Settling time \(T_s\)
- Steady-state error

### 4. Validate Stability

Prove:
- Bounded output under bounded disturbance
- Convergence to setpoint
- No sustained oscillation

## Metrics

### Overshoot

\[ M_p = \frac{y_{\max} - r}{r} \]

Maximum percentage overshoot above setpoint.

Acceptable: \(M_p < 20\%\)

### Settling Time

\[ T_s = \min\{t: |y(t) - r| < \epsilon r \quad \forall t' \ge t\} \]

Time to converge within tolerance \(\epsilon\) (e.g., 5%).

Acceptable: \(T_s < 10\) seconds

### Steady-State Error

\[ e_{ss} = \lim_{t \to \infty} |y(t) - r| \]

Final error after settling.

Acceptable: \(e_{ss} < 5\%\) of setpoint

### Bounded Output Under Bounded Disturbance

\[ |d(t)| < D \Rightarrow |y(t)| < Y \]

For bounded disturbance \(D\), output remains bounded \(Y\).

Acceptable: \(Y < 2r\) (output never exceeds 2x setpoint)

## Test Scenarios

### Scenario 1: Step Increase in Load

1. Start at baseline load (10 flows/sec)
2. Apply step to high load (100 flows/sec)
3. Measure:
   - Overshoot
   - Settling time
   - Steady-state latency

Expected: System converges to setpoint with acceptable overshoot.

### Scenario 2: Step Decrease in Load

1. Start at high load (100 flows/sec)
2. Apply step to low load (10 flows/sec)
3. Measure:
   - Undershoot
   - Settling time
   - Steady-state latency

Expected: System converges to setpoint without oscillation.

### Scenario 3: Disturbance Rejection

1. Maintain constant load
2. Inject disturbance (latency spike)
3. Measure:
   - Maximum deviation
   - Recovery time
   - Steady-state return

Expected: System rejects disturbance and returns to setpoint.

### Scenario 4: Sustained Load

1. Apply constant load above capacity
2. Measure:
   - Latency over time
   - Admission rate over time
   - Boundedness

Expected: Latency remains bounded, admission rate saturates.

## Validation Criteria

System is stable if:

1. **Boundedness**: \(|y(t)| < 2r\) for all \(t\)
2. **Convergence**: \(|y(t) - r| < 0.05r\) for \(t > T_s\)
3. **No Sustained Oscillation**: No periodic behavior after settling
4. **Disturbance Rejection**: \(|y(t) - r| < 0.1r\) within 5 seconds of disturbance

## Implementation

See `Tests/AppAttestIntegratorTests/ControlLoopTests.swift` for step-response test implementation.

## References

See `ADMISSION_CONTROL_PID.md` for PID control model.
See `CONTROL_MODEL.md` for supervisory control model.
