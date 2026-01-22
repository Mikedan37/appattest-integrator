# Zero-Authority Integrator: Tradeoffs and Applicability

## Purpose of This Document

This document defines decision boundaries for the Zero-Authority Integrator Pattern. It exists to prevent over-application, guide operational decisions, and clarify when alternative approaches are more appropriate.

This document is written for operators, reviewers, and architects making deployment decisions. It assumes familiarity with the pattern itself (see [ZERO_AUTHORITY_INTEGRATOR_PATTERN.md](ZERO_AUTHORITY_INTEGRATOR_PATTERN.md)) and focuses on tradeoffs, limits, and correct applicability.

## When NOT to Use This Pattern

Do not deploy this pattern if any of the following conditions apply:

**Single-shot or stateless requests.** If each request is independent and requires no sequencing, use direct backend calls with client-side retries and backoff.

**Throughput-first systems where retries are cheap.** If your system can absorb retry amplification without destabilizing, explicit sequencing adds unnecessary coordination overhead.

**Ultra-low-latency paths where coordination cost dominates.** If every millisecond matters and state coordination latency exceeds acceptable bounds, this pattern introduces unacceptable overhead.

**Systems without external retry pressure.** If clients are trusted, rate-limited at the edge, or naturally back off, explicit flow control provides no benefit.

**Flows without human or long-lived interaction.** If protocol steps complete in seconds and clients do not retry aggressively, sequencing enforcement adds complexity without solving a real problem.

**Backend systems that handle sequencing internally.** If the authoritative backend already enforces protocol ordering and rejects invalid transitions, adding an orchestration layer duplicates logic and creates failure modes.

**Systems where ambiguity is acceptable.** If occasional out-of-order execution or duplicate processing is harmless, deterministic sequencing is unnecessary overhead.

If your use case matches any of these conditions, stop here. This pattern is not appropriate.

## Comparative Tradeoff Table

| Approach | Failure Visibility | Retry Amplification Risk | Observability Quality | Blast Radius | Operator Intervention Cost | Determinism |
|----------|-------------------|-------------------------|---------------------|--------------|---------------------------|-------------|
| Client retries + backoff | Low (client-side only) | High (uncontrolled) | Poor (no server-side state) | High (all clients retry) | High (must coordinate clients) | Low |
| Backend retries | Medium (backend logs only) | Medium (backend-controlled) | Medium (backend-dependent) | Medium (backend-dependent) | Medium (backend configuration) | Medium |
| Circuit breakers | Medium (breaker state) | Low (breaker prevents retries) | Medium (breaker metrics) | Low (isolated to circuit) | Low (breaker configuration) | Medium |
| Token buckets / rate limiting | Low (rate limit only) | Medium (retries still occur) | Low (rate metrics only) | Medium (affects all clients) | Low (rate configuration) | Low |
| Queue-based buffering | Medium (queue depth) | Low (queue absorbs) | Medium (queue metrics) | Low (isolated to queue) | Medium (queue management) | Low |
| Zero-authority integrator | High (full flow state) | Low (explicit rejection) | High (complete flow visibility) | Low (per-flow isolation) | Low (state queries + metrics) | High |
| Zero-authority integrator + admission control | High (flow + latency state) | Very Low (admission gates retries) | Very High (flow + control metrics) | Very Low (per-flow + rate control) | Low (state queries + PID tuning) | Very High |

## What This Pattern Trades Away

**Latency overhead.** Every protocol step requires state coordination. Typical overhead ranges from 1-5ms per request depending on state store implementation. For high-frequency, low-latency paths, this cost may be unacceptable.

**Implementation complexity.** The integrator requires state management, TTL cleanup, concurrency control, and observability instrumentation. This is non-trivial infrastructure that must be maintained, tested, and operated.

**Reduced peak throughput.** Explicit sequencing and admission control limit concurrent flows. Systems that prioritize raw throughput over stability will see lower peak capacity.

**Additional state management.** The integrator maintains bounded but non-zero state. This requires storage, cleanup, and monitoring. State store failures become a new failure mode.

**More explicit rejection instead of silent retries.** Clients receive deterministic errors (sequence violations, expired flows) instead of backend timeouts or ambiguous failures. This improves debuggability but requires client error handling changes.

**Coordination dependency.** The integrator becomes a coordination point. If it fails, flows cannot progress. This creates a single point of coordination (though not a single point of failure if state is replicated).

These are intentional design choices, not flaws. The pattern trades raw performance and simplicity for stability, observability, and deterministic behavior.

## Why Control-Loop Admission Is Used

Retry feedback loops destabilize distributed systems. When backend latency increases, clients retry. Retries increase load, which increases latency further. This positive feedback continues until the system collapses or clients give up.

The control loop breaks this feedback by measuring latency and adjusting admission rate. If latency exceeds a target, admission decreases. This reduces concurrent load, which reduces latency. The loop stabilizes around the target latency.

Boundedness matters. Without admission control, concurrent flows can grow unbounded: $n(t+1) = n(t) + \lambda(t) - \mu(t)$ where $\lambda(t)$ is arrival rate and $\mu(t)$ is completion rate. If $\lambda(t) > \mu(t)$ during latency spikes, $n(t)$ grows without bound. Admission control ensures $\lambda(t) \leq \mu_{\max}$ where $\mu_{\max}$ is the maximum sustainable completion rate.

PID control is appropriate here because:
- The system has measurable output (latency)
- There is a clear setpoint (target latency)
- The plant (backend) responds predictably to load changes
- Disturbances (retry storms, network jitter) are bounded
- Operator tuning confidence is required (PID parameters have known effects)

The control loop provides stability intuition: if latency is above target, reduce admission. If latency is below target, increase admission. The integral term eliminates steady-state error. The derivative term rejects disturbances quickly.

This is not academic. It is operational necessity for systems with untrusted clients and non-stationary load.

## Where This Is Extremely Useful

**OAuth device / PKCE flows.** Multi-step authorization with device codes, user consent, and token exchange. Clients retry aggressively. Flow state is ambiguous without explicit sequencing. Authority (authorization decisions) belongs to the OAuth provider.

**WebAuthn registration + assertion.** Credential registration followed by assertion challenges. Sequencing prevents assertion before registration. Cryptographic verification belongs to WebAuthn validators, not the orchestrator.

**App Attest–style protocols.** Attestation submission, hash requests, and assertion submission must occur in sequence. Backend verification is authoritative. Orchestrator enforces ordering without interpreting attestations.

**Payment authorization handshakes.** Payment initiation, authorization requests, and settlement confirmations form a sequence. Payment processors are authoritative. Orchestrator tracks flow state without making payment decisions.

**Provisioning pipelines.** Multi-step resource provisioning with dependencies. Sequencing ensures steps complete in order. Resource availability decisions belong to provisioning backends.

**Long-lived onboarding flows.** User onboarding with multiple steps over hours or days. State must persist and be queryable. Onboarding decisions belong to business logic, not orchestration.

**Systems with untrusted or opaque clients.** Mobile apps, third-party integrations, or clients with aggressive retry logic. Explicit rejection prevents retry storms. Authority remains with backend subsystems.

In each case, the pattern reduces operational pain: retry storms decrease, failures become classifiable, and state becomes observable without requiring cryptographic or authorization expertise.

## Why This Feels Uncommon

Most systems rely on implicit control loops. Clients retry with backoff. Backends handle load with timeouts and circuit breakers. Load balancers distribute requests. These mechanisms work together implicitly, but they do not coordinate explicitly.

This pattern makes control explicit. The integrator enforces sequencing. Admission control enforces rate limits based on measured latency. State is observable and queryable. Failures are deterministic and classifiable.

Explicit rejection feels "worse" than silent failure. A client receiving "sequence violation" must handle this error explicitly. A client receiving a timeout can retry optimistically. The former requires more client logic, but the latter creates retry storms.

Institutions often prefer ambiguity for flexibility. If flow state is implicit, operators can interpret failures differently. If sequencing is enforced, there is one correct interpretation. This reduces flexibility but increases correctness.

The pattern is uncommon because it requires upfront investment in infrastructure that pays off during incidents, not during normal operation. Most systems optimize for the happy path. This pattern optimizes for the failure path.

## Operational Guidance

**Monitor first:**
- Flow state distribution (are flows stuck in non-terminal states?)
- Sequence violation rate (are clients misusing the protocol?)
- Backend latency percentiles (is admission control needed?)
- State store size (is TTL cleanup working?)

**Metrics that indicate misuse:**
- High sequence violation rate with low backend latency (clients skipping steps)
- Flows stuck in non-terminal states with high backend error rate (backend issues, not client issues)
- State store growth without corresponding flow completion (TTL misconfiguration)
- Admission control rejecting all requests (PID tuning too conservative or backend capacity exceeded)

**Tuning mistakes:**
- Setting TTL too short (flows expire before completion)
- Setting TTL too long (state store grows unbounded)
- Admission control setpoint too low (unnecessary rejection)
- Admission control setpoint too high (retry storms still occur)
- Disabling admission control during incidents (amplifies the incident)

**Safely disable or bypass:**
- Disable admission control: set `APP_ATTEST_ADMISSION_CONTROL_ENABLED=false`. Flows continue, but retry protection is lost.
- Bypass integrator: route requests directly to backend. Sequencing enforcement is lost, but system continues operating.
- Emergency state cleanup: manually expire flows via admin API if state store is corrupted. This is a last resort.

**What to check during incidents:**
1. Backend latency (p50, p95, p99)
2. Flow state distribution (which states are accumulating?)
3. Sequence violation rate (are clients retrying incorrectly?)
4. Admission control status (if enabled, is it rejecting appropriately?)
5. State store health (is TTL cleanup running?)

If admission control is rejecting too aggressively, temporarily increase the setpoint or disable it. If flows are stuck, check backend availability and TTL configuration. If sequence violations are high, investigate client retry logic.

## Closing Boundary Statement

This is a tool, not a default. Correct use yields stability, observability, and classifiable failures. Incorrect use yields unnecessary complexity, latency overhead, and operational burden.

The pattern is appropriate when: multi-step protocols require sequencing, clients retry aggressively, authority belongs to backend subsystems, and operational clarity matters more than peak throughput.

The pattern is inappropriate when: requests are stateless, retries are cheap, latency is critical, or ambiguity is acceptable.

This document exists so operators can make that call deliberately. If deployment decisions are made without understanding these tradeoffs, the pattern will be misapplied and create more problems than it solves.
