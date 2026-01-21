# appattest-integrator

Stateless-or-lightly-stateful integration daemon that orchestrates Apple App Attest flows by coordinating existing components.

## Mental Model

appattest-integrator is a flow orchestrator.
It enforces sequence, correlates identifiers, and records backend responses.
It does not validate cryptography, interpret results, or make decisions.
Treat it as a status board, not a gate.

## What It Is

Infrastructure-grade orchestration daemon providing deterministic sequencing, explicit flow state, stable API contract for product backends, and strong observability.

## What It Does

- Flow sequencing: Enforces state machine transitions (registered → hash_issued → verified/rejected)
- Correlation: Generates and propagates correlation IDs to backend
- Stable API: HTTP endpoints for product backends to initiate and progress flows
- Observability: Structured logging and Prometheus metrics

## What It Does NOT Do

- **No cryptographic verification**: Delegated to appattest-backend
- **No trust decisions**: All verification handled by backend
- **No policy logic**: Policy enforcement is backend responsibility
- **No freshness guarantees**: Beyond backend TTL surfaced as metadata
- **No replay prevention**: Beyond backend semantics
- **No "verified => authorized" logic**: Authorization is product backend concern

## Architecture

```
Product Backend → appattest-integrator → appattest-backend
```

The integrator:
1. Receives flow initiation requests from product backends
2. Coordinates with appattest-backend for cryptographic operations
3. Maintains flow state and enforces sequencing
4. Returns stable API responses with verbatim backend data

## Deployment

### Host Requirements

- Debian Linux (tested on Orange Pi)
- Swift 6.2+
- Same machine as appattest-backend (default)

### Environment Variables

- `APP_ATTEST_BACKEND_BASE_URL`: Backend base URL (default: `http://127.0.0.1:8080`)
- `APP_ATTEST_INTEGRATOR_PORT`: Listen port (default: `8090`)
- `APP_ATTEST_BACKEND_TIMEOUT_MS`: Backend request timeout (default: `3000`)
- `APP_ATTEST_DEBUG_LOG_ARTIFACTS`: Debug logging level (0=none, 1=lengths+SHA256, 2=full dumps DEV-ONLY, default: `0`)
- `APP_ATTEST_BUILD_SHA256`: Build SHA256 for health endpoint (optional)

### Build

```bash
swift build -c release
```

### Run

```bash
.build/release/AppAttestIntegrator
```

Or use the development script:

```bash
./scripts/run_dev.sh
```

### Systemd Service

Install systemd unit:

```bash
sudo ./scripts/install_systemd.sh
```

Service file location: `/etc/systemd/system/appattest-integrator.service`

## API Endpoints

### POST /v1/flows/start

Initiate a new flow.

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

Request clientDataHash for assertion.

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

Submit assertion for verification.

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

Get flow status.

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

Health check endpoint.

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

**Example:**
```bash
curl http://localhost:8090/health
```

### GET /metrics

Prometheus metrics endpoint.

**Example:**
```bash
curl http://localhost:8090/metrics
```

## Error Responses

All errors return JSON:

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
- `registered`: Attestation registered with backend
- `hash_issued`: ClientDataHash issued
- `verified`: Terminal - Verification succeeded
- `rejected`: Terminal - Verification failed
- `expired`: Terminal - Flow expired
- `error`: Terminal - Error occurred

**Transitions:**
- `start` → `registered`
- `registered` → `hash_issued`
- `hash_issued` → `verified` | `rejected`
- Any state → `expired` (when `now > expiresAt`)

Terminal states reject further mutation calls with deterministic error codes.

## Flow Store

In-memory thread-safe store with TTL cleanup. Extension point for persistence (Redis/SQLite/BlazeDB).

## Backend Integration

The integrator sends correlation headers to backend:
- `X-Correlation-ID`: Flow correlation ID
- `X-Flow-Handle`: Flow handle

Backend endpoints:
- `POST /app-attest/register`
- `POST /app-attest/client-data-hash`
- `POST /app-attest/verify`

## Observability

**Logging:**
- Structured logs with correlationID, flowHandle, flowID
- State transitions logged
- Backend request/response status logged
- Artifacts logged as lengths + SHA256 (if debug enabled)

**Metrics:**
- `flow_started_total`: Counter
- `flow_completed_total`: Counter
- `flow_failed_total`: Counter
- `backend_requests_total{route=...}`: Counter
- `sequence_violation_total`: Counter

## Development

Run tests:

```bash
swift test
```

Run linter:

```bash
swiftlint
```

## License

[Specify license]
