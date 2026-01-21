# Control Model of appattest-integrator

**For formal mathematical treatment, see [Formal Control Model Appendix](CONTROL_FORMALISM.md).**

## Overview

appattest-integrator is a finite-state supervisory controller that enforces sequencing constraints on Apple App Attest flows. It accumulates protocol state, enforces valid transitions, and exposes observable state without making trust or authorization decisions.

This document describes the conceptual model. The system functions correctly without understanding this model.

## System Boundary

The integrator operates in the control plane, coordinating with:

- **appattest-backend**: Cryptographic verification authority (data plane)
- **appattest-decoder/validator**: Parsing and crypto primitives (data plane)
- **Product backends**: Policy and business logic
- **Mobile clients**: Protocol event sources

The integrator forwards cryptographic artifacts unchanged and accumulates only protocol-level state.

## Core Invariants

### State Machine

The integrator maintains a finite-state machine with these states:
- `created` → `registered` → `hash_issued` → `verified` or `rejected`
- Any state → `expired` (time-based)
- Terminal states: `verified`, `rejected`, `expired`, `error`

**Invariant:** Invalid transitions are rejected deterministically. No heuristics, no recovery, no implicit correction.

### State Accumulation

State evolves deterministically based on:
- Current state
- Input event type
- Backend response (if invoked)

**Invariant:** Terminal states are absorbing. Once a flow reaches a terminal state, it cannot transition to another state.

**Invariant:** Past state is immutable. State history is effectively append-only.

### Observation

The integrator exposes state through observation queries.

**Invariant:** Observation has no side effects. Querying state does not modify state.

**Invariant:** State space is finite and bounded. The number of possible states is limited.

### Feedback

Feedback enters the system only through:
- Backend responses (affect state transitions)
- Time-based expiration (moves flows to `expired`)

**Invariant:** Authorization outcomes, trust assessments, and policy decisions do not exist in this system. These signals are absent by design.

## Explicit Non-Goals

The integrator explicitly does not:
- Perform cryptographic verification
- Make trust decisions
- Implement authorization logic
- Evaluate policy
- Provide freshness guarantees beyond backend TTL
- Prevent replay beyond backend semantics

These responsibilities belong to other subsystems.

## Control Structure

The integrator implements a supervisory control pattern:

```
Mobile Client → Product Backend → appattest-integrator → appattest-backend
                                      ↓
                                 State Observation
```

**Key properties:**
- Single state accumulation point
- No algebraic loops
- Feedback enters only via backend responses
- No decision loops inside the integrator

## Discrete-Time Behavior

Time advances in event time, not wall-clock time. Each protocol event corresponds to a discrete time step.

**Invariant:** There is no continuous-time signal. The system operates on discrete events.

**Invariant:** State updates are deterministic. Given the same state and input, the system produces the same next state.

## Boundedness and Termination

**Invariant:** State space is finite. The number of possible states is bounded.

**Invariant:** Terminal states enforce eventual termination. Flows cannot remain in non-terminal states indefinitely (TTL enforcement).

**Note:** Liveness is not guaranteed. Flows may stall, but TTL enforces eventual termination. This is intentional.

## Interpretation

This control-theoretic framing is one valid analytical lens. Equivalent interpretations include:
- Protocol state machine
- Control-plane orchestrator
- Correlation and sequencing service

The control model is descriptive, not performative. The system functions identically without understanding this model.

---

**For formal mathematical treatment including equations, set notation, and detailed proofs, see [CONTROL_FORMALISM.md](CONTROL_FORMALISM.md).**
