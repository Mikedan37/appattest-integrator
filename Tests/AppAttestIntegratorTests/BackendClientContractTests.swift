import XCTest
import XCTVapor
@testable import AppAttestIntegrator

/// Backend client contract validation.
/// Tests correlation headers, request shapes, and verbatim response preservation.
final class BackendClientContractTests: XCTestCase {
    var mockBackend: MockBackend!
    var app: Application!
    var backendClient: BackendClient!
    
    override func setUp() async throws {
        mockBackend = MockBackend()
        let backendApp = try mockBackend.start(port: 8080)
        
        app = Application(.testing)
        backendClient = BackendClient(
            baseURL: "http://127.0.0.1:8080",
            timeoutMS: 3000,
            client: app.http.client
        )
    }
    
    override func tearDown() async throws {
        mockBackend.shutdown()
        try await app.asyncShutdown()
    }
    
    func testCorrelationHeadersForwarded() async throws {
        let correlationID = UUID().uuidString
        let flowHandle = "test-handle"
        
        mockBackend.setRegisterHandler { req in
            XCTAssertEqual(req.headers.first(name: "X-Correlation-ID"), correlationID)
            XCTAssertEqual(req.headers.first(name: "X-Flow-Handle"), flowHandle)
            
            return BackendRegisterResponse(
                keyID_base64: "test",
                verifyRunID: nil,
                expiresAt: nil
            )
        }
        
        let request = BackendRegisterRequest(
            keyID_base64: "test",
            attestationObject_base64: "test",
            verifyRunID: nil
        )
        
        _ = try await backendClient.register(
            request: request,
            correlationID: correlationID,
            flowHandle: flowHandle
        )
    }
    
    func testClientDataHashCorrelationHeaders() async throws {
        let correlationID = UUID().uuidString
        let flowHandle = "test-handle"
        
        mockBackend.setClientDataHashHandler { req in
            XCTAssertEqual(req.headers.first(name: "X-Correlation-ID"), correlationID)
            XCTAssertEqual(req.headers.first(name: "X-Flow-Handle"), flowHandle)
            
            return BackendClientDataHashResponse(
                clientDataHash_base64: "hash",
                expiresAt: ISO8601DateFormatter().string(from: Date())
            )
        }
        
        _ = try await backendClient.requestClientDataHash(
            keyID_base64: "test",
            verifyRunID: nil,
            correlationID: correlationID,
            flowHandle: flowHandle
        )
    }
    
    func testVerifyCorrelationHeaders() async throws {
        let correlationID = UUID().uuidString
        let flowHandle = "test-handle"
        
        mockBackend.setVerifyHandler { req in
            XCTAssertEqual(req.headers.first(name: "X-Correlation-ID"), correlationID)
            XCTAssertEqual(req.headers.first(name: "X-Flow-Handle"), flowHandle)
            
            return BackendVerifyResponse(verified: true, reason: nil)
        }
        
        let request = BackendVerifyRequest(
            keyID_base64: "test",
            assertionObject_base64: "test",
            clientDataHash_base64: "hash",
            verifyRunID: nil
        )
        
        _ = try await backendClient.verify(
            request: request,
            correlationID: correlationID,
            flowHandle: flowHandle
        )
    }
    
    func testRequestBodiesMatchExpectedShapes() async throws {
        let registerRequest = BackendRegisterRequest(
            keyID_base64: "key123",
            attestationObject_base64: "attest456",
            verifyRunID: "run789"
        )
        
        mockBackend.setRegisterHandler { req in
            let decoded = try req.content.decode(BackendRegisterRequest.self)
            XCTAssertEqual(decoded.keyID_base64, "key123")
            XCTAssertEqual(decoded.attestationObject_base64, "attest456")
            XCTAssertEqual(decoded.verifyRunID, "run789")
            
            return BackendRegisterResponse(
                keyID_base64: decoded.keyID_base64,
                verifyRunID: decoded.verifyRunID,
                expiresAt: nil
            )
        }
        
        _ = try await backendClient.register(
            request: registerRequest,
            correlationID: UUID().uuidString,
            flowHandle: "handle"
        )
    }
}
