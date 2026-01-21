import Foundation
import Vapor

// MARK: - Request Models

struct StartFlowRequest: Content {
    let keyID_base64: String
    let attestationObject_base64: String
    let verifyRunID: String?
}

struct ClientDataHashRequest: Content {
    let verifyRunID: String?
}

struct AssertRequest: Content {
    let assertionObject_base64: String
    let verifyRunID: String?
}

// MARK: - Response Models

struct StartFlowResponse: Content {
    let flowHandle: String
    let flowID: String
    let keyID_base64: String
    let verifyRunID: String?
    let state: String
    let issuedAt: String
    let expiresAt: String?
}

struct ClientDataHashResponse: Content {
    let clientDataHash_base64: String
    let expiresAt: String
    let state: String
}

struct AssertResponse: Content {
    let state: String
    let backend: [String: AnyCodable]
    let terminal: Bool
}

/// Status represents observed flow progress.
/// It does not imply authorization, trust, or acceptance.
struct FlowStatusResponse: Content {
    let flowHandle: String
    let flowID: String
    let keyID_base64: String
    let verifyRunID: String?
    let state: String
    let issuedAt: String
    let expiresAt: String?
    let lastBackendStatus: String?
    let terminal: Bool
}

struct HealthResponse: Content {
    let status: String
    let uptimeSeconds: Double
    let flowCount: Int
    let terminalFlowCount: Int
    let backendBaseURL: String
    let buildSha256: String?
}

// MARK: - Error Models

struct ErrorResponse: Content {
    let error: ErrorDetail
}

struct ErrorDetail: Content {
    let code: String
    let message: String
    let details: [String: AnyCodable]?
    
    init(code: String, message: String, details: [String: AnyCodable]? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

// MARK: - AnyCodable Helper

/// Helper to encode/decode arbitrary JSON values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let codableArray = array.map { AnyCodable($0) }
            try container.encode(codableArray)
        case let dict as [String: Any]:
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable value cannot be encoded"
                )
            )
        }
    }
}
