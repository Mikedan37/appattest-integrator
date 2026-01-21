# End-to-End Test Plan

## Objective

Validate integrator behavior through complete flow lifecycle with mock backend.

## Prerequisites

- Mock backend server running on `http://127.0.0.1:8080`
- Integrator running on `http://127.0.0.1:8090`
- curl or equivalent HTTP client

## Test Flow

### 1. Start Flow

```bash
curl -X POST http://localhost:8090/v1/flows/start \
  -H "Content-Type: application/json" \
  -d '{
    "keyID_base64": "dGVzdA==",
    "attestationObject_base64": "dGVzdA=="
  }'
```

**Expected:**
- HTTP 200
- Response contains `flowHandle` (opaque string)
- Response contains `flowID` (UUID)
- `state` == "registered"
- `terminal` == false

**Validate:**
- `flowHandle` is stable and unique
- `flowID` matches backend response
- Correlation ID generated and logged

### 2. Request ClientDataHash

```bash
curl -X POST http://localhost:8090/v1/flows/{flowHandle}/client-data-hash \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Expected:**
- HTTP 200
- Response contains `clientDataHash_base64`
- `state` == "hash_issued"
- `expiresAt` present

**Validate:**
- Flow state transitioned from "registered" to "hash_issued"
- Backend received correlation headers
- `clientDataHash_base64` stored in flow state

### 3. Submit Assertion

```bash
curl -X POST http://localhost:8090/v1/flows/{flowHandle}/assert \
  -H "Content-Type: application/json" \
  -d '{
    "assertionObject_base64": "dGVzdA=="
  }'
```

**Expected:**
- HTTP 200
- Response contains `backend` object (verbatim backend response)
- `state` == "verified" or "rejected"
- `terminal` == true

**Validate:**
- Backend response preserved exactly (no transformation)
- Flow state terminal
- Metrics incremented (`flow_completed_total` or `flow_failed_total`)

### 4. Check Status

```bash
curl http://localhost:8090/v1/flows/{flowHandle}/status
```

**Expected:**
- HTTP 200
- `state` matches final state from assert
- `terminal` == true
- `lastBackendStatus` present

**Validate:**
- Status reflects completed flow
- No further mutations possible

## Sequence Violation Tests

### Test: Assert Before Hash

```bash
# Start flow
curl -X POST http://localhost:8090/v1/flows/start ...

# Attempt assert immediately (skip hash step)
curl -X POST http://localhost:8090/v1/flows/{flowHandle}/assert ...
```

**Expected:**
- HTTP 409 Conflict
- Error code: "sequence_violation"
- Flow state unchanged ("registered")

### Test: Request Hash Twice

```bash
# Start flow and request hash
curl -X POST http://localhost:8090/v1/flows/start ...
curl -X POST http://localhost:8090/v1/flows/{flowHandle}/client-data-hash ...

# Request hash again
curl -X POST http://localhost:8090/v1/flows/{flowHandle}/client-data-hash ...
```

**Expected:**
- HTTP 409 Conflict
- Error code: "sequence_violation"
- Flow state unchanged ("hash_issued")

### Test: Assert After Terminal

```bash
# Complete flow
curl -X POST http://localhost:8090/v1/flows/start ...
curl -X POST http://localhost:8090/v1/flows/{flowHandle}/client-data-hash ...
curl -X POST http://localhost:8090/v1/flows/{flowHandle}/assert ...

# Attempt second assert
curl -X POST http://localhost:8090/v1/flows/{flowHandle}/assert ...
```

**Expected:**
- HTTP 409 Conflict
- Error code: "terminal_state"
- Flow state unchanged (terminal)

## Verbatim Backend Preservation Test

Configure mock backend to return complex response:

```json
{
  "verified": false,
  "reason": "identity mismatch",
  "forensics": {
    "signedBytes_sha256": "abc123",
    "signature_sha256": "def456",
    "debug": {
      "a": [1, 2, 3]
    }
  }
}
```

**Validate:**
- Integrator returns exact JSON structure
- No fields added
- No fields removed
- No fields renamed
- Field ordering preserved (if order matters)

## Observability Validation

### Metrics

```bash
curl http://localhost:8090/metrics
```

**Expected:**
- Prometheus format
- `flow_started_total` incremented
- `backend_requests_total{route="..."}` incremented
- `sequence_violation_total` incremented on violations

### Logs

Check integrator logs for:
- Correlation ID present in all log entries
- State transitions logged
- Backend request/response status logged
- No full base64 artifacts (unless debug enabled)

## Success Criteria

All tests pass if:
1. Happy path completes with correct state transitions
2. Sequence violations return 409 with deterministic errors
3. Backend responses preserved verbatim
4. FlowHandle remains stable throughout flow
5. Terminal states reject mutations
6. Metrics reflect behavior accurately
7. Logs contain correlation IDs

## Failure Modes

Tests fail if:
- State transitions occur out of order
- Backend responses are transformed
- Terminal states accept mutations
- Metrics don't reflect behavior
- Correlation IDs missing from logs
