# Closed-Loop Reliability Control (PID) for Flow Admission

## Problem Statement

When mobile clients retry and backend latency spikes, uncontrolled admission creates:

- **Request pileups**: Concurrent requests exceed backend capacity
- **Timeout cascades**: Timeouts trigger retries, which trigger more timeouts
- **Outage spirals**: Positive feedback loop amplifies load until collapse

This is a control problem: keep latency bounded while demand fluctuates.

## Solution: Admission Control with PID

The integrator measures backend latency and adjusts admission rate to maintain target latency.

This prevents:
- Thundering herd
- Retry amplification
- Collapse under load

## Control Model

### Measured Output

Define measured output as exponentially-weighted moving average (EWMA) of backend latency:

\[ y(t) = \text{EWMA}_{\text{latency}}(t) = \alpha \cdot \text{latency}(t) + (1-\alpha) \cdot y(t-1) \]

Where \(\alpha \in (0,1]\) is the smoothing factor.

### Setpoint

Define target latency:

\[ r = \text{target latency} \]

### Error Signal

\[ e(t) = r - y(t) \]

### PID Controller (Discrete-Time Form)

\[ u(t) = K_p e(t) + K_i \sum_{i=0}^{t} e(i)\Delta t + K_d \frac{e(t) - e(t-1)}{\Delta t} \]

Where:
- \(K_p\): Proportional gain
- \(K_i\): Integral gain
- \(K_d\): Derivative gain
- \(\Delta t\): Sampling period (control interval at which backend latency is measured and admission decisions are applied, e.g., per second or per request batch)

### Saturation (Anti-Windup)

Admission rate is clipped to valid range:

\[ u'(t) = \text{clip}(u(t), u_{\min}, u_{\max}) \]

Where:
- \(u_{\min}\): Minimum admission rate (e.g., 1 flow/sec)
- \(u_{\max}\): Maximum admission rate (e.g., 1000 flows/sec)

### Plant Approximation

Backend latency rises with concurrency:

\[ y(t) \approx a + b \cdot n(t) + d(t) \]

Where:
- \(a\): Base latency
- \(b\): Latency per concurrent flow
- \(n(t)\): Number of concurrent flows
- \(d(t)\): Disturbance (network jitter, CPU spikes, client retries)

Concurrency evolves according to:

\[ n(t+1) = n(t) + u'(t) - c(t) \]

Where:
- \(u'(t)\): Admission rate (flows per interval)
- \(c(t)\): Completion rate (completed flows per interval)

### Closed-Loop Feedback

The control loop:

1. Integrator measures backend latency \(y(t)\)
2. Integrator computes error \(e(t) = r - y(t)\)
3. PID controller computes admission rate \(u'(t)\)
4. Admission changes concurrency \(n(t)\)
5. Concurrency affects backend latency \(y(t+1)\)

This is a real feedback loop: latency affects admission, admission affects latency.

## Implementation Notes

### EWMA Smoothing

Use \(\alpha = 0.1\) for slow, stable response or \(\alpha = 0.3\) for faster response to latency spikes.

### PID Tuning

Initial tuning (Ziegler-Nichols approximation):
- \(K_p = 0.6 \cdot K_u\)
- \(K_i = 1.2 \cdot K_u / T_u\)
- \(K_d = 3 \cdot K_u \cdot T_u / 40\)

Where \(K_u\) is ultimate gain and \(T_u\) is ultimate period (determined experimentally).

Conservative starting point:
- \(K_p = 10\)
- \(K_i = 1\)
- \(K_d = 0.1\)

### Anti-Windup

When saturation occurs, disable integral term accumulation to prevent windup:

\[ \text{if } u(t) \ne u'(t) \text{ then } K_i = 0 \text{ for next step} \]

### Disturbance Rejection

The derivative term \(K_d\) provides disturbance rejection by responding to rate of change in latency.

## Stability Properties

### Bounded Output Under Bounded Disturbance

\[ |d(t)| < D \Rightarrow |y(t)| < Y \]

For bounded disturbance \(D\), output remains bounded \(Y\).

### Settling Time

System converges to setpoint within settling time:

\[ T_s = \min\{t: |y(t) - r| < \epsilon r \quad \forall t' \ge t\} \]

Where \(\epsilon\) is tolerance (e.g., 0.05 for 5% tolerance).

### Overshoot

Maximum overshoot:

\[ M_p = \frac{y_{\max} - r}{r} \]

Tuned controllers minimize overshoot while maintaining fast response.

## Non-Goals

This admission control:
- Does not make cryptographic verification decisions
- Does not make trust or authorization decisions
- Does not evaluate policy
- Only controls admission rate based on observed latency

These responsibilities belong to other subsystems.

## References

See `CONTROL_MODEL.md` for the supervisory control model.
See `CONTROL_TEST_PLAN.md` for step-response validation methodology.
