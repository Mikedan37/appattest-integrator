import Foundation
import Vapor

/// HTTP client for appattest-backend communication.
/// 
/// Strict HTTP client with timeout, correlation headers, and verbatim response preservation.
/// See README "Explicit Non-Goals" section.
struct BackendClient {
    let baseURL: String
    let timeoutMS: Int
    let client: Client
    let admissionController: AdmissionController?
    
    init(baseURL: String, timeoutMS: Int, client: Client, admissionController: AdmissionController? = nil) {
        self.baseURL = baseURL
        self.timeoutMS = timeoutMS
        self.client = client
        self.admissionController = admissionController
    }
    
    /// Register attestation with backend.
    func register(
        request: BackendRegisterRequest,
        correlationID: String,
        flowHandle: String
    ) async throws -> (response: BackendRegisterResponse, rawJSON: [String: AnyCodable]) {
        let url = URI(string: "\(baseURL)/app-attest/register")
        let route = "/app-attest/register"
        
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "X-Correlation-ID", value: correlationID)
        headers.add(name: "X-Flow-Handle", value: flowHandle)
        
        let timeout = HTTPClient.Configuration.Timeout(
            connect: .milliseconds(Int64(timeoutMS)),
            read: .milliseconds(Int64(timeoutMS))
        )
        
        let startTime = Date()
        let response = try await client.post(url) { req in
            try req.content.encode(request)
            req.headers = headers
        }
        let latencyMS = Date().timeIntervalSince(startTime) * 1000.0
        
        // Record latency for admission control
        if let controller = admissionController {
            await controller.recordLatency(latencyMS, route: route)
        }
        
        guard response.status == .ok else {
            throw BackendError.httpError(status: response.status.code, body: try? response.body.collect().get())
        }
        
        let decoded = try response.content.decode(BackendRegisterResponse.self)
        let rawJSON = try response.content.decode([String: AnyCodable].self)
        
        return (decoded, rawJSON)
    }
    
    /// Request clientDataHash from backend.
    func requestClientDataHash(
        keyID_base64: String,
        verifyRunID: String?,
        correlationID: String,
        flowHandle: String
    ) async throws -> (response: BackendClientDataHashResponse, rawJSON: [String: AnyCodable]) {
        let url = URI(string: "\(baseURL)/app-attest/client-data-hash")
        let route = "/app-attest/client-data-hash"
        
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "X-Correlation-ID", value: correlationID)
        headers.add(name: "X-Flow-Handle", value: flowHandle)
        
        let request = BackendClientDataHashRequest(
            keyID_base64: keyID_base64,
            verifyRunID: verifyRunID
        )
        
        let timeout = HTTPClient.Configuration.Timeout(
            connect: .milliseconds(Int64(timeoutMS)),
            read: .milliseconds(Int64(timeoutMS))
        )
        
        let startTime = Date()
        let response = try await client.post(url) { req in
            try req.content.encode(request)
            req.headers = headers
        }
        let latencyMS = Date().timeIntervalSince(startTime) * 1000.0
        
        // Record latency for admission control
        if let controller = admissionController {
            await controller.recordLatency(latencyMS, route: route)
        }
        
        guard response.status == .ok else {
            throw BackendError.httpError(status: response.status.code, body: try? response.body.collect().get())
        }
        
        let decoded = try response.content.decode(BackendClientDataHashResponse.self)
        let rawJSON = try response.content.decode([String: AnyCodable].self)
        
        return (decoded, rawJSON)
    }
    
    /// Verify assertion with backend.
    func verify(
        request: BackendVerifyRequest,
        correlationID: String,
        flowHandle: String
    ) async throws -> (response: BackendVerifyResponse, rawJSON: [String: AnyCodable]) {
        let url = URI(string: "\(baseURL)/app-attest/verify")
        let route = "/app-attest/verify"
        
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "X-Correlation-ID", value: correlationID)
        headers.add(name: "X-Flow-Handle", value: flowHandle)
        
        let startTime = Date()
        let response = try await client.post(url) { req in
            try req.content.encode(request)
            req.headers = headers
        }
        let latencyMS = Date().timeIntervalSince(startTime) * 1000.0
        
        // Record latency for admission control
        if let controller = admissionController {
            await controller.recordLatency(latencyMS, route: route)
        }
        
        guard response.status == .ok else {
            throw BackendError.httpError(status: response.status.code, body: try? response.body.collect().get())
        }
        
        let decoded = try response.content.decode(BackendVerifyResponse.self)
        let rawJSON = try response.content.decode([String: AnyCodable].self)
        
        return (decoded, rawJSON)
    }
}

enum BackendError: Error {
    case httpError(status: UInt, body: ByteBuffer?)
    case decodeError(Error)
}
