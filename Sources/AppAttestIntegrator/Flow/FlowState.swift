import Foundation

/// Flow state machine states.
/// 
/// These represent observed backend-reported states, not authorization decisions.
/// Terminal states: verified, rejected, expired, error
enum FlowStateEnum: String, Codable {
    case created
    case registered
    case hashIssued = "hash_issued"
    case verified
    case rejected
    case expired
    case error
}

/// Flow state representation.
/// 
/// Contains all metadata needed for orchestration sequencing and correlation.
/// See README "Explicit Non-Goals" section.
struct FlowState: Codable {
    let flowHandle: String
    let flowID: String
    let keyID_base64: String
    let verifyRunID: String?
    let issuedAt: Date
    var expiresAt: Date?
    var clientDataHash_base64: String?
    var lastBackendStatus: String?
    var lastBackendReason: String?
    var terminal: Bool
    var state: FlowStateEnum
    let correlationID: String
    
    init(
        flowHandle: String,
        flowID: String,
        keyID_base64: String,
        verifyRunID: String?,
        issuedAt: Date = Date(),
        expiresAt: Date? = nil,
        clientDataHash_base64: String? = nil,
        lastBackendStatus: String? = nil,
        lastBackendReason: String? = nil,
        terminal: Bool = false,
        state: FlowStateEnum = .created,
        correlationID: String
    ) {
        self.flowHandle = flowHandle
        self.flowID = flowID
        self.keyID_base64 = keyID_base64
        self.verifyRunID = verifyRunID
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.clientDataHash_base64 = clientDataHash_base64
        self.lastBackendStatus = lastBackendStatus
        self.lastBackendReason = lastBackendReason
        self.terminal = terminal
        self.state = state
        self.correlationID = correlationID
    }
}
