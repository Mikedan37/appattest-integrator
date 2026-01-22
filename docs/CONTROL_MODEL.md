# Control Model of flow-integrator

**For formal mathematical treatment, see [Formal Control Model Appendix](CONTROL_FORMALISM.md).**

## What This Is

flow-integrator enforces sequencing constraints for multi-step protocol flows, correlates identifiers, and exposes observable flow state.

It does not perform cryptographic verification, make trust decisions, or enforce policy.

## State Machine

The integrator maintains flow state through protocol-specific transitions. States and transitions are configured per protocol.

**Example (App Attest):**
- `created` → `registered` → `hash_issued` → `verified` or `rejected`
- Any state → `expired` (time-based)
- Terminal states: `verified`, `rejected`, `expired`, `error`

**Rule:** Invalid transitions are rejected. No recovery, no heuristics.

## State Updates

State changes deterministically based on:
- Current state
- Input event (start, hash, assert, status query)
- Backend response (if a backend call was made)

**Rule:** Terminal states are final. Once a flow reaches `verified`, `rejected`, `expired`, or `error`, it cannot transition further.

**Rule:** State history is immutable. Past state cannot be changed.

## Observation

The integrator exposes state through status queries.

**Rule:** Querying state has no side effects. Status queries do not modify flow state.

**Rule:** State space is finite. The number of possible states is bounded.

## Feedback

State changes occur only through:
- Backend responses (after register/hash/assert calls)
- Time-based expiration (TTL enforcement)

**Rule:** Authorization, trust, and policy decisions do not exist in this system. The integrator does not make these decisions.

## Non-Goals

The integrator does not:
- Verify cryptographic artifacts
- Make trust or authorization decisions
- Evaluate policy
- Provide freshness guarantees beyond backend TTL
- Prevent replay beyond backend semantics

These belong to other subsystems (authoritative backends, product backends).

## Architecture

```
Client → Product Backend → flow-integrator → Authoritative Backend
                              ↓
                         Status Queries
```

**Properties:**
- Single state store
- No loops or circular dependencies
- Feedback only via backend responses
- No internal decision logic

The integrator operates in the control plane, coordinating with authoritative backends that make security decisions.

## Determinism

State updates are deterministic. Same state + same input = same next state.

Time advances per event, not wall-clock time.

## Termination

State space is finite and bounded.

Terminal states ensure eventual termination. TTL enforces that flows cannot remain active indefinitely.

**Note:** Liveness is not guaranteed. Flows may stall, but TTL ensures they eventually expire.

---

**For control-theoretic formalization with equations and proofs, see [CONTROL_FORMALISM.md](CONTROL_FORMALISM.md).**
