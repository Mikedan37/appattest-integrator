import Foundation

// MARK: - Backend Request Models

struct BackendRegisterRequest: Codable {
    let keyID_base64: String
    let attestationObject_base64: String
    let verifyRunID: String?
}

struct BackendClientDataHashRequest: Codable {
    let keyID_base64: String
    let verifyRunID: String?
}

struct BackendVerifyRequest: Codable {
    let keyID_base64: String
    let assertionObject_base64: String
    let clientDataHash_base64: String
    let verifyRunID: String?
}

// MARK: - Backend Response Models

struct BackendRegisterResponse: Codable {
    let keyID_base64: String
    let verifyRunID: String?
    let expiresAt: String? // ISO8601
}

struct BackendClientDataHashResponse: Codable {
    let clientDataHash_base64: String
    let expiresAt: String // ISO8601
}

struct BackendVerifyResponse: Codable {
    let verified: Bool
    let reason: String?
    // Additional fields may exist; preserve verbatim via AnyCodable
}
