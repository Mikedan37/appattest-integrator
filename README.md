# flow-integrator

Zero-authority flow orchestration daemon for multi-step protocol flows.

## Mental Model

flow-integrator enforces sequencing, correlates identifiers, and records backend responses verbatim. It maintains flow state and exposes status endpoints. It does not interpret results or make authorization decisions.

This system implements the [Zero-Authority Integrator Pattern](docs/ZERO_AUTHORITY_INTEGRATOR_PATTERN.md), providing deterministic sequencing, state observability, and retry protection for multi-step protocol flows where authority belongs to backend subsystems.

## Behavior

The integrator:
- Enforces state machine transitions according to protocol rules
- Generates correlation IDs and propagates them to backend
- Stores flow state with TTL-based expiration
- Returns backend responses verbatim
- Exposes Prometheus metrics and structured logs
- Optionally gates admission based on backend latency (admission control)

## Explicit Non-Goals

- No cryptographic verification
- No trust decisions
- No policy logic
- No freshness guarantees beyond backend TTL
- No replay prevention beyond backend semantics
- No authorization decisions

## Architecture

```
Product Backend → flow-integrator → Authoritative Backend
```

The integrator receives flow requests, forwards them to authoritative backends with correlation headers, stores state transitions, and returns backend responses unchanged.

## Component Boundaries

The integrator operates in the control plane, coordinating with:
- **Authoritative backends**: Make trust, authorization, and verification decisions
- **Data plane components**: Perform structural parsing and cryptographic operations
- **flow-integrator**: Flow orchestration only (sequencing, correlation, observability)

The integrator never interprets authoritative responses or makes security decisions.

## Deployment

### Requirements

- Debian Linux
- Swift 6.2+
- Authoritative backend running (default: `http://127.0.0.1:8080`)

### Environment Variables

- `APP_ATTEST_BACKEND_BASE_URL`: Backend base URL (default: `http://127.0.0.1:8080`)
- `APP_ATTEST_INTEGRATOR_PORT`: Listen port (default: `8090`)
- `APP_ATTEST_BACKEND_TIMEOUT_MS`: Backend request timeout (default: `3000`)
- `APP_ATTEST_DEBUG_LOG_ARTIFACTS`: Debug logging level (0=none, 1=lengths+SHA256, 2=full dumps, default: `0`)
- `APP_ATTEST_BUILD_SHA256`: Build SHA256 for health endpoint (optional)

**Note:** Environment variable names retain `APP_ATTEST_` prefix for backward compatibility with existing deployments. The system is protocol-agnostic and can orchestrate any multi-step protocol flow.

### Admission Control (Optional)

Admission control regulates flow admission based on observed backend latency to prevent retry storms and overload spirals. See [docs/ADMISSION_CONTROL_PID.md](docs/ADMISSION_CONTROL_PID.md) for details.

Environment variables:
- `APP_ATTEST_ADMISSION_CONTROL_ENABLED`: Enable admission control (default: `false`)
- `APP_ATTEST_TARGET_LATENCY_MS`: Target latency in milliseconds (default: `200`)
- `APP_ATTEST_EWMA_ALPHA`: EWMA smoothing factor (default: `0.2`)
- `APP_ATTEST_PID_KP`: PID proportional gain (default: `0.5`)
- `APP_ATTEST_PID_KI`: PID integral gain (default: `0.05`)
- `APP_ATTEST_PID_KD`: PID derivative gain (default: `0.1`)
- `APP_ATTEST_CONTROL_DT_MS`: Control update period in milliseconds (default: `500`)
- `APP_ATTEST_RATE_MIN_TPS`: Minimum admission rate in tokens per second (default: `1`)
- `APP_ATTEST_RATE_MAX_TPS`: Maximum admission rate in tokens per second (default: `200`)
- `APP_ATTEST_BURST_MAX_TOKENS`: Maximum burst tokens (default: `50`)

When admission control is enabled and rate limited, endpoints return HTTP 429 with `code="admission_limited"` and metadata including current EWMA latency, target latency, current rate, and retry-after time.

### Build

```bash
swift build -c release
```

### Run

```bash
.build/release/AppAttestIntegrator
```

Development:

```bash
./scripts/run_dev.sh
```

### Systemd

```bash
sudo ./scripts/install_systemd.sh
```

Service file: `/etc/systemd/system/appattest-integrator.service`

## API Endpoints

The API is protocol-agnostic. Endpoints accept protocol-specific payloads and enforce sequencing constraints. The examples below show the App Attest use case; other protocols use the same endpoints with different payload fields.

### POST /v1/flows/start

Initiates a flow. Returns integrator-scoped `flowHandle` and backend-authored `flowID`.

**Request (App Attest example):**
```json
{
  "keyID_base64": "<base64>",
  "attestationObject_base64": "<base64>",
  "verifyRunID": "<optional uuid>"
}
```

**Request (OAuth device flow example):**
```json
{
  "device_code": "<device code>",
  "client_id": "<client identifier>",
  "verifyRunID": "<optional uuid>"
}
```

**Response:**
```json
{
  "flowHandle": "<opaque string>",
  "flowID": "<uuid>",
  "keyID_base64": "<base64>",
  "verifyRunID": "<optional uuid>",
  "state": "registered",
  "issuedAt": "<ISO8601>",
  "expiresAt": "<optional ISO8601>"
}
```

**Example:**
```bash
curl -X POST http://localhost:8090/v1/flows/start \
  -H "Content-Type: application/json" \
  -d '{
    "keyID_base64": "dGVzdA==",
    "attestationObject_base64": "dGVzdA=="
  }'
```

### POST /v1/flows/{flowHandle}/client-data-hash

Requests intermediate challenge (e.g., clientDataHash for App Attest). Requires flow in `registered` state.

**Request:**
```json
{
  "verifyRunID": "<optional uuid>"
}
```

**Response:**
```json
{
  "clientDataHash_base64": "<base64>",
  "expiresAt": "<ISO8601>",
  "state": "hash_issued"
}
```

**Example:**
```bash
curl -X POST http://localhost:8090/v1/flows/abc123/client-data-hash \
  -H "Content-Type: application/json" \
  -d '{}'
```

### POST /v1/flows/{flowHandle}/assert

Submits final step payload (e.g., assertion for App Attest). Requires flow in `hash_issued` state. Returns backend response verbatim.

**Request:**
```json
{
  "assertionObject_base64": "<base64>",
  "verifyRunID": "<optional uuid>"
}
```

**Response:**
```json
{
  "state": "verified",
  "backend": { ...verbatim backend response... },
  "terminal": true
}
```

**Example:**
```bash
curl -X POST http://localhost:8090/v1/flows/abc123/assert \
  -H "Content-Type: application/json" \
  -d '{
    "assertionObject_base64": "dGVzdA=="
  }'
```

### GET /v1/flows/{flowHandle}/status

Returns current flow state. Does not imply authorization or trust.

**Response:**
```json
{
  "flowHandle": "...",
  "flowID": "...",
  "keyID_base64": "...",
  "verifyRunID": "...",
  "state": "...",
  "issuedAt": "...",
  "expiresAt": "...",
  "lastBackendStatus": "...",
  "terminal": true
}
```

**Example:**
```bash
curl http://localhost:8090/v1/flows/abc123/status
```

### GET /health

Health check with flow counts and backend URL.

**Response:**
```json
{
  "status": "ok",
  "uptimeSeconds": 123.4,
  "flowCount": 10,
  "terminalFlowCount": 3,
  "backendBaseURL": "http://127.0.0.1:8080",
  "buildSha256": "<hex if available>"
}
```

### GET /metrics

Prometheus-format metrics.

## Error Responses

```json
{
  "error": {
    "code": "sequence_violation",
    "message": "short human-readable",
    "details": { ...optional... }
  }
}
```

**Error Codes:**
- `sequence_violation`: 409 Conflict - Invalid state transition
- `not_found`: 404 Not Found - Flow not found
- `expired`: 410 Gone - Flow has expired
- `backend_error`: 502 Bad Gateway - Backend request failed
- `invalid_input`: 400 Bad Request - Invalid request payload

## State Machine

The state machine enforces protocol sequencing. States and transitions are protocol-specific but follow a common pattern:

**States (App Attest example):**
- `created`: Initial state (internal)
- `registered`: Backend reported registration
- `hash_issued`: Backend issued intermediate challenge
- `verified`: Terminal - Backend reported verification success
- `rejected`: Terminal - Backend reported verification failure
- `expired`: Terminal - Flow expired
- `error`: Terminal - Error occurred

**Transitions (App Attest example):**
- `start` → `registered`
- `registered` → `hash_issued`
- `hash_issued` → `verified` | `rejected`
- Any state → `expired` (when `now > expiresAt`)

Terminal states reject further mutations. The state machine structure is protocol-agnostic; state names and transitions are configured per protocol.

## Flow Store

In-memory thread-safe store with TTL cleanup. Extension point for persistence (Redis/SQLite/BlazeDB).

## Backend Integration

Correlation headers sent to backend:
- `X-Correlation-ID`: Flow correlation ID
- `X-Flow-Handle`: Integrator-scoped flow handle

Backend endpoints are protocol-specific. The integrator forwards requests to authoritative backends unchanged and records responses verbatim.

**App Attest backend endpoints (example):**
- `POST /app-attest/register`
- `POST /app-attest/client-data-hash`
- `POST /app-attest/verify`

Other protocols use different backend endpoints. The integrator does not interpret backend responses; it records them verbatim.

## Observability

**Logging:**
- Structured logs with correlationID, flowHandle, flowID
- State transitions
- Backend request/response status
- Artifact lengths + SHA256 (if debug enabled)

**Metrics:**
- `flow_started_total`: Counter
- `flow_completed_total`: Counter
- `flow_failed_total`: Counter
- `backend_requests_total{route=...}`: Counter
- `sequence_violation_total`: Counter

## Applicability

This integrator is designed for multi-step protocol flows where:
- Sequencing must be enforced deterministically
- State must be observable without side effects
- Authority (verification, authorization, policy) belongs to backend subsystems
- Retry storms and state desynchronization are operational concerns

**Example use cases:**
- Apple App Attest flows (attestation → hash request → assertion)
- OAuth device authorization flows (device code → user authorization → token exchange)
- WebAuthn registration + assertion flows
- Payment authorization handshakes
- Multi-step provisioning workflows

See [docs/ZERO_AUTHORITY_INTEGRATOR_PATTERN.md](docs/ZERO_AUTHORITY_INTEGRATOR_PATTERN.md) for the architectural pattern and [docs/ZERO_AUTHORITY_INTEGRATOR_TRADEOFFS.md](docs/ZERO_AUTHORITY_INTEGRATOR_TRADEOFFS.md) for when to use and when not to use this pattern.

## Development

```bash
swift test
swiftlint
```
