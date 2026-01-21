# Control Model

## 1. Scope

This document models appattest-integrator as a discrete-time control system and protocol orchestration layer.

The model describes:
- State accumulation over protocol events
- Constraint enforcement on state transitions
- Observation of accumulated state
- Forwarding of external system responses

Out of scope:
- Cryptographic verification mechanisms
- Trust decision processes
- Authorization policies
- Continuous-time dynamics
- Implementation details

This document provides optional conceptual context. Implementation correctness does not depend on understanding this model.

## 2. System Boundary

The integrator operates at the control-plane boundary between product backends and appattest-backend.

**Control-plane components:**
- appattest-integrator: Event sequencing and state accumulation
- appattest-backend: Cryptographic verification and binding enforcement

**Data-plane components:**
- appattest-decoder: Structural parsing
- appattest-validator: Cryptographic verification primitives

**External systems:**
- Product backends: Initiate flows and consume state observations
- Mobile clients: Generate protocol events

The integrator does not process cryptographic artifacts. It forwards them to appattest-backend and accumulates protocol-level state.

## 3. Inputs and Outputs

**Inputs u(t):**
- Flow initiation events: keyID, attestationObject, optional verifyRunID
- ClientDataHash requests: flowHandle, optional verifyRunID
- Assertion events: flowHandle, assertionObject, optional verifyRunID
- Status queries: flowHandle

Time index t advances discretely per request. No continuous-time signals exist.

**Outputs y(t):**
- Flow state observations: flowHandle, flowID, state, terminal flag, timestamps
- Backend responses: Verbatim JSON from appattest-backend
- Error signals: Sequence violations, expiration, not found

**State x(t):**
- FlowState: Accumulated protocol state per flowHandle
- Metrics: Counters for events and violations
- Correlation identifiers: Stable across flow lifecycle

## 4. State as an Accumulated Quantity

FlowState accumulates protocol events over time. Each event modifies state deterministically.

State transitions are functions of:
- Current state x(t)
- Input event u(t)
- Backend response r(t)

State accumulates as:
- x(t+1) = f(x(t), u(t), r(t))

Past inputs are immutable. State history cannot be rewritten. Terminal states prevent further accumulation.

The system maintains one FlowState per flowHandle. FlowHandle is an integrator-scoped identifier. flowID is backend-authored and preserved.

## 5. Discrete-Time Integrator Analogy

The system accumulates protocol events similar to a discrete-time integrator accumulating samples.

Differences from continuous-time integrator H(s) = 1/s:
- Time advances per request, not continuously
- Events are protocol messages, not analog signals
- Integration occurs over protocol state space, not signal amplitude
- No continuous-time dynamics exist

The integrator accumulates:
- Event sequence: registered → hash_issued → verified/rejected
- Correlation identifiers: Stable across requests
- Backend responses: Preserved verbatim
- Temporal metadata: issuedAt, expiresAt

This is not a signal processing integrator. It is a protocol state accumulator.

## 6. State Transitions as Constraints

The state machine enforces constraints on transitions. Invalid transitions are rejected deterministically.

Valid transitions:
- created → registered (on flow initiation)
- registered → hash_issued (on clientDataHash request)
- hash_issued → verified (on successful assertion)
- hash_issued → rejected (on failed assertion)
- any → expired (on TTL expiration)

Constraint violations:
- Transition from wrong source state: sequence_violation
- Transition from terminal state: terminal_state
- Transition after expiration: expired

Constraints are enforced synchronously. No probabilistic or heuristic enforcement exists.

The system rejects invalid transitions without modifying state. Error codes are deterministic functions of current state and attempted transition.

## 7. Feedback and Observation

**Feedback paths:**
- Backend responses: Returned verbatim, stored in FlowState.lastBackendStatus
- Expiration: Time-based feedback marks flows terminal
- Sequence violations: Increment metrics, return error codes

**No feedback:**
- Authorization decisions: Not observed or accumulated
- Trust assessments: Not part of state
- Policy evaluations: Not stored or forwarded

**Observer outputs:**
- Status endpoint: Returns current FlowState
- Metrics endpoint: Returns accumulated counters
- Health endpoint: Returns system-level observations

Observations are read-only. Querying state does not modify it. Multiple observers can query the same state concurrently.

## 8. Stability and Termination

Terminal states are absorbing states. Once reached, no further state transitions occur.

Terminal states:
- verified: Backend reported verification success
- rejected: Backend reported verification failure
- expired: TTL exceeded
- error: System error occurred

Expiration acts as a time-bounded stability condition. Flows must reach a terminal state before expiresAt. After expiration, the system rejects mutations deterministically.

The system does not guarantee all flows reach terminal states. Flows may remain in non-terminal states indefinitely if no further events occur. TTL cleanup marks expired flows terminal asynchronously.

## 9. Non-Goals (Formal)

The integrator does not perform:
- Cryptographic verification
- Trust decisions
- Policy logic
- Freshness guarantees beyond backend TTL
- Replay prevention beyond backend semantics
- Authorization decisions

These responsibilities exist in other system components. The integrator forwards requests and accumulates protocol state only.

## 10. Interpretation Notes

This model provides one valid lens for understanding the system. Other models may be equally valid:
- Protocol state machine
- Request-response orchestrator
- Correlation and sequencing service

Implementation correctness does not depend on understanding this model. The system behaves as specified regardless of conceptual framing.

The model uses control theory terminology where it provides clarity. It does not claim the system is novel or superior. It describes observed behavior using established concepts.
