# appattest-integrator

Flow orchestration daemon for Apple App Attest verification flows.

## Mental Model

appattest-integrator enforces sequencing, correlates identifiers, and records backend responses verbatim. It maintains flow state and exposes status endpoints. It does not interpret results or make authorization decisions.

## Behavior

The integrator:
- Enforces state machine transitions (registered → hash_issued → verified/rejected)
- Generates correlation IDs and propagates them to backend
- Stores flow state with TTL-based expiration
- Returns backend responses verbatim
- Exposes Prometheus metrics and structured logs

## Explicit Non-Goals

- No cryptographic verification
- No trust decisions
- No policy logic
- No freshness guarantees beyond backend TTL
- No replay prevention beyond backend semantics
- No authorization decisions

## Architecture

```
Product Backend → appattest-integrator → appattest-backend
```

The integrator receives flow requests, forwards them to appattest-backend with correlation headers, stores state transitions, and returns backend responses unchanged.

## Component Boundaries

- **appattest-decoder**: Structural parsing only
- **appattest-validator**: Cryptographic verification only
- **appattest-backend**: Verification + binding enforcement (authoritative)
- **appattest-integrator**: Flow orchestration only

## Deployment

### Requirements

- Debian Linux
- Swift 6.2+
- appattest-backend running (default: `http://127.0.0.1:8080`)

### Environment Variables

- `APP_ATTEST_BACKEND_BASE_URL`: Backend base URL (default: `http://127.0.0.1:8080`)
- `APP_ATTEST_INTEGRATOR_PORT`: Listen port (default: `8090`)
- `APP_ATTEST_BACKEND_TIMEOUT_MS`: Backend request timeout (default: `3000`)
- `APP_ATTEST_DEBUG_LOG_ARTIFACTS`: Debug logging level (0=none, 1=lengths+SHA256, 2=full dumps, default: `0`)
- `APP_ATTEST_BUILD_SHA256`: Build SHA256 for health endpoint (optional)

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

### POST /v1/flows/start

Initiates a flow. Returns integrator-scoped `flowHandle` and backend-authored `flowID`.

**Request:**
```json
{
  "keyID_base64": "<base64>",
  "attestationObject_base64": "<base64>",
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

Requests clientDataHash. Requires flow in `registered` state.

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

Submits assertion. Requires flow in `hash_issued` state. Returns backend response verbatim.

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

**States:**
- `created`: Initial state (internal)
- `registered`: Backend reported registration
- `hash_issued`: Backend issued clientDataHash
- `verified`: Terminal - Backend reported verification success
- `rejected`: Terminal - Backend reported verification failure
- `expired`: Terminal - Flow expired
- `error`: Terminal - Error occurred

**Transitions:**
- `start` → `registered`
- `registered` → `hash_issued`
- `hash_issued` → `verified` | `rejected`
- Any state → `expired` (when `now > expiresAt`)

Terminal states reject further mutations.

## Flow Store

In-memory thread-safe store with TTL cleanup. Extension point for persistence (Redis/SQLite/BlazeDB).

## Backend Integration

Correlation headers sent to backend:
- `X-Correlation-ID`: Flow correlation ID
- `X-Flow-Handle`: Integrator-scoped flow handle

Backend endpoints:
- `POST /app-attest/register`
- `POST /app-attest/client-data-hash`
- `POST /app-attest/verify`

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

## Development

```bash
swift test
swiftlint
```
