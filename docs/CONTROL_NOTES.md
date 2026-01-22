# Supervisory Control for Protocol Orchestration

## Problem Statement

Protocol flows are often implemented as "just call endpoints." This approach creates:

- **Step skipping**: Clients skip required protocol steps, causing backend errors
- **Retry storms**: Failed requests trigger uncontrolled retries, amplifying load
- **State desync**: No single source of truth for "where in the flow" a device is
- **Debug hell**: Failures cannot be classified (sequence violation vs backend rejection vs expiration)

Without deterministic sequencing and observable state, protocol integration becomes error-prone and difficult to reason about.

## What This Fixes

The supervisory control model provides:

### Deterministic Sequencing

Invalid transitions are rejected deterministically:

$$
x(t+1) = x(t) \quad \text{if } (x(t), u(t)) \notin \mathcal{T}
$$

No step skipping. No implicit recovery. No ambiguity about what happened.

### Observable State Without Side Effects

State queries are read-only:

$$
y(t) = g(x(t)), \quad \frac{\partial x}{\partial y} = 0
$$

You can observe "where in the flow" without affecting the flow.

### Classifiable Failures

Failures are deterministic functions of state and input:

$$
y(t) = \text{error}(x(t), u(t))
$$

Failures are:
- **Sequence violations**: Invalid transition attempted
- **Backend rejections**: Backend returned rejection (recorded verbatim)
- **Expiration**: TTL exceeded

No ambiguity. No guessing.

## What This Proves

### Formalization of Software Control Plane

You can model a software control plane as a discrete-time supervisory controller:

$$
x(t+1) = f(x(t), u(t), r(t))
$$

Where:
- $x(t)$ is accumulated protocol state
- $u(t)$ are discrete protocol events
- $r(t)$ is exogenous backend feedback

This is not academic. It is a precise model of what the system does.

### Invariant Enforcement

The system enforces invariants:

- **Transition constraints**: Only valid state transitions occur
- **State immutability**: Past state cannot be modified
- **Terminal absorption**: Terminal states cannot be exited

These invariants prevent entire classes of bugs.

### Observability Without Coupling

The observation operator is explicitly decoupled:

$$
y(t) = g(x(t)), \quad \frac{\partial x}{\partial y} = 0
$$

You can observe state without creating feedback loops or side effects.

### Prevention of Illegal Feedback Paths

The diagram shows:
- Single accumulation point (integrator only)
- No algebraic loops
- Feedback enters only via backend responses $r(t)$
- No hidden controller-in-controller coupling

This prevents accidental coupling and makes the system easier to reason about.

## Core Mathematics

### Discrete-Time Event Index

$$
t \in \mathbb{N}, \quad t \mapsto \text{protocol event}
$$

Time advances in event time, not wall-clock time.

### State Update

$$
x(t+1) = f(x(t), u(t), r(t))
$$

Where:
- $f$ is deterministic
- $r(t)$ is backend response (if invoked)
- Past state is immutable

### Observation Operator (No Back-Action)

$$
y(t) = g(x(t)), \quad \frac{\partial x}{\partial y} = 0
$$

Observation does not affect state evolution.

### Hard Constraint Enforcement

$$
x(t+1) = x(t) \quad \text{if } (x(t), u(t)) \notin \mathcal{T}
$$

Invalid transitions are rejected deterministically.

### Absorbing Terminal States

$$
x(t) \in \mathcal{X}_T \Rightarrow x(t+1) = x(t)
$$

Terminal states cannot be exited.

## Application to App Attest

The App Attest protocol requires strict sequencing:

1. **Registration**: Submit attestation object
2. **Hash Request**: Request client data hash
3. **Assertion**: Submit assertion object

Without deterministic sequencing:
- Clients skip steps
- Backend rejects with cryptic errors
- No way to debug "where did it fail"

With supervisory control:
- Invalid transitions rejected immediately
- State observable at any point
- Failures classifiable and debuggable

## Non-Goals

This model does not:
- Make cryptographic verification decisions
- Make trust or authorization decisions
- Evaluate policy
- Provide freshness guarantees beyond TTL
- Prevent replay beyond backend semantics

These responsibilities belong to other subsystems.

## References

See `CONTROL_MODEL.md` for the complete formal model.
