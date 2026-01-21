# Control Model of appattest-integrator

## 1. Scope

This document models appattest-integrator as a discrete-time control system and protocol orchestration layer.
This is supervisory control over discrete protocol events, not continuous-time feedback control, PID regulation, or signal control.

The model characterizes:
- Discrete-time state accumulation over protocol events
- Deterministic constraint enforcement on state transitions
- Observation of accumulated state without state mutation
- Verbatim forwarding of external subsystem responses

Out of scope:
- Cryptographic verification mechanisms
- Trust and authorization decisions
- Policy evaluation
- Continuous-time dynamics
- Implementation-level concerns

This document provides conceptual and analytical context.
System correctness does not depend on understanding this model.

## 2. System Boundary and Decomposition

The system is decomposed into four orthogonal subsystems, with the integrator operating strictly in the control plane.

**Control-plane components**
- **appattest-integrator**
  Discrete-time state accumulator, sequence enforcer, and observation surface.
- **appattest-backend**
  Cryptographic verification and binding enforcement authority.

**Data-plane components**
- **appattest-decoder**
  Structural parsing of protocol artifacts.
- **appattest-validator**
  Cryptographic verification primitives.

**External actors**
- Product backends: initiate flows, consume observations.
- Mobile clients: generate protocol events.

The integrator does not interpret cryptographic artifacts.
It forwards them unchanged and accumulates protocol-level state only.

## 3. Inputs, Outputs, and State

### Discrete-time index

Time advances in event time, not wall-clock time.

\[ t \in \mathbb{N}, \quad t \mapsto \text{protocol event} \]

There is no continuous-time signal \(x(t)\).

### Inputs \(u(t)\)

\[ u(t) \in \mathcal{U} \]

Where \(\mathcal{U}\) includes:
- Flow initiation events
  \[ u_{\text{start}} = (\text{keyID}, \text{attestationObject}, \text{verifyRunID?}) \]
- ClientDataHash requests
  \[ u_{\text{hash}} = (\text{flowHandle}, \text{verifyRunID?}) \]
- Assertion submissions
  \[ u_{\text{assert}} = (\text{flowHandle}, \text{assertionObject}, \text{verifyRunID?}) \]
- State observation queries
  \[ u_{\text{status}} = (\text{flowHandle}) \]

### Outputs \(y(t)\)

\[ y(t) \in \mathcal{Y} \]

Including:
- State observations
  \[ y_{\text{state}} = (\text{flowHandle}, \text{flowID}, \text{state}, \text{terminal}, \text{timestamps}) \]
- Backend responses
  \[ y_{\text{backend}} = r(t) \text{ (verbatim JSON)} \]
- Deterministic error signals
  \[ y_{\text{error}} \in \{\text{sequence\_violation}, \text{expired}, \text{not\_found}, \dots\} \]

### State \(x(t)\)

For each flowHandle \(h\):

\[ x_h(t) = \begin{bmatrix} \text{state}_h \\ \text{flowID}_h \\ \text{keyID}_h \\ \text{verifyRunID}_h \\ \text{timestamps}_h \\ \text{lastBackendStatus}_h \end{bmatrix} \]

Global auxiliary state:
- Metrics counters
- Correlation identifiers

## 4. State Evolution (Discrete Accumulation)

State evolves according to:

\[ x(t+1) = f\big(x(t), u(t), r(t)\big) \]

Where:
- \(f\) is deterministic
- \(r(t)\) is the backend response (if invoked)
- Past state is immutable
- State history is append-only in effect

Terminal states impose:

\[ x(t+1) = x(t) \quad \forall u(t) \text{ that mutate state} \]

## 5. Discrete-Time Integrator Analogy (Supervisory, Not Linear)

This system behaves analogously to a discrete-time integrator, but over protocol state, not signal amplitude.

**Continuous-time integrator (for reference)**

\[ H(s) = \frac{1}{s} \]

**Discrete-time signal integrator**

\[ x[k+1] = x[k] + u[k] \]

**Protocol-state integrator (this system)**

\[ x(t+1) = \begin{cases} f(x(t), u(t), r(t)) & \text{if transition valid} \\ x(t) & \text{if transition invalid} \end{cases} \]

Key differences:
- No linear superposition
- No scalar accumulation
- State space is finite and symbolic
- Integration occurs over event history
- No continuous-time transfer functions

This is not signal processing or linear control.
It is discrete protocol-state accumulation under supervisory constraints.

## 6. State Transitions as Hard Constraints

The state machine defines a constraint surface.

**Valid transitions**

\[ \begin{aligned} \text{created} &\rightarrow \text{registered} \\ \text{registered} &\rightarrow \text{hash\_issued} \\ \text{hash\_issued} &\rightarrow \text{verified} \\ \text{hash\_issued} &\rightarrow \text{rejected} \\ \forall s &\rightarrow \text{expired} \end{aligned} \]

**Constraint violations**

Invalid transition \(u(t)\) from state \(x(t)\) yields:

\[ y(t) = \text{error}(x(t), u(t)) \]

and:

\[ x(t+1) = x(t) \]

No heuristics.
No recovery.
No implicit correction.

## 7. Feedback and Observation

### Feedback paths
- Backend response feedback
  \[ r(t) \rightarrow x(t+1) \]
- Time-based expiration
  \[ \text{now} > \text{expiresAt} \Rightarrow \text{expired} \]
- Violation counters increment metrics

### Explicitly absent feedback
- Authorization outcomes
- Trust assessments
- Policy decisions

These signals do not exist in this system.

### Observation operator

Define an observation function:

\[ y(t) = g(x(t)) \]

Where:
- \(g\) is read-only
- \(\frac{\partial x}{\partial y} = 0\) (no observer back-action)
- Observation does not affect state

## 8. Stability and Termination

Terminal states are absorbing states:

\[ x(t) \in \{\text{verified}, \text{rejected}, \text{expired}, \text{error}\} \Rightarrow x(t+1) = x(t) \]

The system is bounded-input, bounded-state.

\[ \exists\, M < \infty \;\text{s.t.}\; \|x(t)\| \le M \quad \forall t \]

Liveness is not guaranteed:
- Flows may stall
- TTL enforces eventual termination

This is intentional.

## 9. Formal Non-Goals

The system explicitly excludes:

\[ \begin{aligned} &\text{Cryptographic verification} \\ &\text{Trust decisions} \\ &\text{Authorization logic} \\ &\text{Policy evaluation} \\ &\text{Freshness guarantees beyond TTL} \\ &\text{Replay prevention beyond backend semantics} \end{aligned} \]

These responsibilities belong to other subsystems.

## 10. Control-System Block Diagram

```
                     ┌────────────────────────────┐
                     │        Mobile Client        │
                     │  (App Attest event source)  │
                     └─────────────┬──────────────┘
                                   │   u(t)
                                   │   protocol events
                                   ▼
┌────────────────────────────┐     │
│        Product Backend     │─────┘
│  (business logic, policy) │
└─────────────┬──────────────┘
              │ u(t)
              ▼
┌──────────────────────────────────────────────────────────┐
│                    appattest-integrator                  │
│                    (CONTROL PLANE)                       │
│                                                          │
│   State accumulator: x(t)                                │
│   ────────────────────────────────────────────────       │
│   x(t+1) = f(x(t), u(t), r(t))                            │
│                                                          │
│   • Enforces sequencing constraints                      │
│   • Correlates flowHandle ↔ flowID ↔ verifyRunID         │
│   • Records backend responses verbatim                   │
│   • Exposes state observation y(t) = g(x(t))             │
│                                                          │
│   NO cryptography                                        │
│   NO trust / authorization                               │
│   NO policy logic                                        │
└─────────────┬────────────────────────────────────────────┘
              │ r(t)
              │ backend responses (verbatim)
              ▼
┌──────────────────────────────────────────────────────────┐
│                   appattest-backend                      │
│                (VERIFICATION AUTHORITY)                  │
│                                                          │
│   • Binding enforcement                                  │
│   • Cryptographic verification                           │
│   • Signature normalization                              │
│                                                          │
│   Produces authoritative verification artifacts          │
└─────────────┬────────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────────┐
│        appattest-decoder / appattest-validator           │
│                   (DATA PLANE)                           │
│                                                          │
│   • Structural parsing (CBOR, ASN.1, COSE)               │
│   • Cryptographic primitives (ECDSA math)                │
│                                                          │
│   Stateless, pure functions                              │
└──────────────────────────────────────────────────────────┘
```

### Mermaid Diagram

```mermaid
flowchart TB
    MC[Mobile Client]
    PB[Product Backend]
    INT["appattest-integrator<br/>CONTROL PLANE"]
    BE["appattest-backend<br/>VERIFICATION AUTHORITY"]
    DP["Decoder / Validator<br/>DATA PLANE"]

    MC -->|u(t)| PB
    PB -->|u(t)| INT
    INT -->|r(t)| BE
    BE --> DP
    INT -->|y(t)| PB
```

**Key properties:**
- Single accumulation point
- No algebraic loops
- Feedback enters only via backend responses \(r(t)\)
- No decision loops inside the integrator
- Supervisory control structure

## 11. Interpretation Notes

This is one valid analytical lens.

Equivalent interpretations:
- Protocol state machine
- Control-plane orchestrator
- Correlation and sequencing service

The control-theoretic framing is descriptive, not performative.
The system functions identically without it.
