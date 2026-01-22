# Zero-Authority Integrator Pattern

## Problem Statement

Multi-step protocol flows require sequencing enforcement, identifier correlation, and state observability.

The common failure mode is **authority bleed**: orchestration layers gradually take on cryptographic interpretation, authorization decisions, or policy enforcement. That coupling makes production failures ambiguous and recovery brittle.

Typical symptoms:
- Retry storms caused by ambiguous flow state
- State desynchronization across components
- Unclear error attribution (orchestrator vs verifier vs client)
- Low-quality observability during incidents

## Pattern Definition

A zero-authority integrator is a protocol orchestration layer that enforces sequencing constraints, correlates identifiers, records authoritative responses verbatim, and exposes observable state. It operates without making trust, authorization, or policy decisions.

### What the Integrator Does

- Enforces valid state transitions according to protocol rules
- Correlates identifiers across protocol steps
- Records authoritative subsystem responses verbatim
- Exposes observable state through query interfaces
- Rejects invalid transitions deterministically
- Maintains bounded state with TTL-based expiration

### What the Integrator Never Does

- Performs cryptographic verification
- Makes trust or authorization decisions
- Evaluates policy
- Interprets or transforms authoritative responses
- Provides freshness guarantees beyond authoritative subsystem TTL
- Prevents replay beyond authoritative subsystem semantics

### Why Separation Matters

Separation makes failures classifiable and contained:

- **Attribution:** orchestration errors vs authority errors are distinguishable
- **Isolation:** verification/policy changes do not require orchestration changes
- **Operability:** state queries show flow progression without interpreting security meaning
- **Testability:** orchestration can be validated without cryptographic fixtures

## Interface Contract

### Inputs

- Flow initiation events (with identifiers and artifacts)
- Protocol step requests (with flow handle and step-specific data)
- State observation queries (with flow handle)

### Outputs

- State observations (flow handle, identifiers, current state, terminal flag, timestamps)
- Verbatim authoritative subsystem responses (unchanged)
- Deterministic error signals (sequence violations, expired, not found)

### Guarantees

- Deterministic state transitions (same state + same input = same next state)
- No authority decisions (integrator never makes trust/authorization/policy calls)
- Verbatim forwarding (authoritative responses are unchanged)
- Terminal state absorption (terminal states do not transition)

### Non-Guarantees

- Liveness (flows may stall; TTL enforces eventual expiration)
- Freshness (integrator does not provide freshness beyond authoritative subsystem TTL)
- Replay prevention (integrator does not prevent replay beyond authoritative subsystem semantics)

## Applicability

This pattern applies to any multi-step protocol flow where sequencing, correlation, and observability are needed, but where trust decisions belong to authoritative subsystems.

### OAuth / Device Authorization Flows

**Integrator observes:**
- Device code issuance
- User authorization completion
- Token exchange requests

**Integrator never decides:**
- Whether user is authorized
- Token validity
- Scope enforcement

### WebAuthn Registration + Assertion

**Integrator observes:**
- Credential registration requests
- Assertion challenges and responses
- Credential lifecycle state

**Integrator never decides:**
- Attestation validity
- User authentication
- Credential binding

### Payment Authorization Handshakes

**Integrator observes:**
- Payment initiation
- Authorization requests
- Settlement confirmations

**Integrator never decides:**
- Payment authorization
- Fraud detection
- Risk assessment

### Multi-Step Provisioning Workflows

**Integrator observes:**
- Provisioning step completion
- Resource allocation state
- Dependency satisfaction

**Integrator never decides:**
- Resource availability
- Quota enforcement
- Access permissions

## Operational Signals

### Metrics

- Flow state distribution (counts per state)
- Transition rejection rate (sequence violations)
- Backend request latency (per route)
- Flow expiration rate (TTL enforcement)
- State store size (boundedness)

### Logs

- State transitions with correlation IDs
- Invalid transition attempts with current state
- Backend request/response pairs (verbatim)
- Flow expiration events

### Observable Rules

- Terminal states do not transition.
- Invalid transitions do not mutate state.
- Status queries are read-only.
- TTL cleanup prevents unbounded state growth.

### Diagnosability

The integrator exposes sufficient signals to diagnose:
- Protocol flow progression
- Backend subsystem behavior
- Client retry patterns
- State desynchronization

It does not diagnose:
- Cryptographic failures (belongs to authoritative subsystem)
- Authorization failures (belongs to authoritative subsystem)
- Policy violations (belongs to authoritative subsystem)

## Failure Modes

### Backend Unavailability

**Integrator behavior:**
- Returns 502/504 to client
- Does not advance flow state
- Flow remains in current state until backend recovers or TTL expires

**Observability:**
- Backend request failure rate metric
- Flow state distribution shows flows stuck in non-terminal states

### Backend Latency Spikes

**Integrator behavior:**
- Optional admission control gates new requests (see admission control documentation)
- Existing flows continue; backend timeout applies per request
- No state mutation until backend responds

**Observability:**
- Backend latency percentiles (p50, p95, p99)
- Admission control rejection rate (if enabled)

### Duplicate Requests

**Integrator behavior:**
- Same flow handle + same transition = idempotent (no state change, returns current state)
- Same flow handle + different transition = rejected as sequence violation
- Different flow handles = independent flows

**Observability:**
- Sequence violation rate (indicates client retry patterns)
- Idempotent request detection (same correlation ID + same transition)

### Clock Skew

**Integrator behavior:**
- TTL uses monotonic time if available, otherwise wall-clock time
- Bounded drift acceptable (TTL is approximate, authoritative subsystems handle freshness)

**Observability:**
- Flow expiration rate (should match expected TTL distribution)

## Incident Playbook

### High Sequence Violation Rate

**Check:**
- Client retry patterns (logs show correlation IDs)
- Flow state distribution (are flows stuck?)

**Action:**
- If client misuse: throttle or reject invalid transitions
- If backend slow: check backend latency metrics
- If state desync: investigate state store consistency

### High Backend Latency

**Check:**
- Backend latency percentiles (p50, p95, p99)
- Backend error rate
- Admission control status (if enabled)

**Action:**
- Enable admission control if not already enabled
- Investigate backend route-specific latency
- Check for backend capacity issues

### Flows Stuck in Non-Terminal States

**Check:**
- Flow state distribution (which states are accumulating?)
- Backend availability (are requests succeeding?)
- TTL expiration rate (are flows expiring?)

**Action:**
- If backend down: wait for recovery or manually expire flows
- If TTL not working: check clock synchronization
- If state store issue: investigate persistence layer

### State Store Growth

**Check:**
- State store size metric
- Flow expiration rate
- TTL cleanup task status

**Action:**
- Verify TTL cleanup is running
- Check for TTL configuration errors
- Consider reducing TTL if appropriate

## Implementation Considerations

### State Management

State can be stored in-memory with TTL cleanup, or in persistent stores (Redis, SQLite, distributed databases) depending on requirements.

### Concurrency

The integrator handles concurrent requests for the same flow handle. Invalid transitions are rejected deterministically regardless of concurrency.

### Extension Points

- State persistence (in-memory → Redis → distributed database)
- Metrics backend (Prometheus → custom collectors)
- Logging backend (structured logs → centralized logging)
- Admission control (optional rate limiting based on backend latency)

## Relationship to Control Theory

The integrator is equivalent to a deterministic finite-state supervisor over protocol events with read-only observation. Formalization exists in [CONTROL_FORMALISM.md](CONTROL_FORMALISM.md) and is optional.

## References

- [CONTROL_MODEL.md](CONTROL_MODEL.md): Conceptual model of the integrator
- [CONTROL_FORMALISM.md](CONTROL_FORMALISM.md): Formal mathematical treatment
