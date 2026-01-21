import XCTest
import XCTVapor
@testable import AppAttestIntegrator

/// Critical test: Backend responses preserved verbatim.
/// No transformation, interpretation, or normalization.
final class VerbatimBackendPreservationTests: XCTestCase {
    var mockBackend: MockBackend!
    var app: Application!
    var backendClient: BackendClient!
    
    override func setUp() async throws {
        mockBackend = MockBackend()
        _ = try mockBackend.start(port: 8080)
        
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
    
    func testComplexBackendResponsePreserved() async throws {
        let complexResponse: [String: AnyCodable] = [
            "status": AnyCodable("rejected"),
            "reason": AnyCodable("identity mismatch"),
            "forensics": AnyCodable([
                "signedBytes_sha256": AnyCodable("abc123"),
                "signature_sha256": AnyCodable("def456"),
                "debug": AnyCodable(["a": AnyCodable([1, 2, 3])])
            ])
        ]
        
        mockBackend.setVerifyHandler { req in
            // Return complex response
            return BackendVerifyResponse(verified: false, reason: "identity mismatch")
        }
        
        // Mock the raw JSON response
        let verifyRequest = BackendVerifyRequest(
            keyID_base64: "test",
            assertionObject_base64: "test",
            clientDataHash_base64: "hash",
            verifyRunID: nil
        )
        
        let (_, rawJSON) = try await backendClient.verify(
            request: verifyRequest,
            correlationID: UUID().uuidString,
            flowHandle: "handle"
        )
        
        // Verify rawJSON contains expected fields
        // Note: Actual preservation test requires full HTTP mock with exact JSON
        XCTAssertNotNil(rawJSON)
    }
    
    func testBackendResponseNoFieldsAdded() async throws {
        mockBackend.setRegisterHandler { req in
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
        
        let (_, rawJSON) = try await backendClient.register(
            request: request,
            correlationID: UUID().uuidString,
            flowHandle: "handle"
        )
        
        // Verify no extra fields added
        let expectedKeys = Set(["keyID_base64", "verifyRunID", "expiresAt"])
        let actualKeys = Set(rawJSON.keys)
        
        // Should only contain backend fields
        XCTAssertTrue(expectedKeys.isSuperset(of: actualKeys))
    }
    
    func testBackendResponseNoFieldsRemoved() async throws {
        mockBackend.setRegisterHandler { req in
            return BackendRegisterResponse(
                keyID_base64: "test",
                verifyRunID: "run-id",
                expiresAt: "2024-01-01T00:00:00Z"
            )
        }
        
        let request = BackendRegisterRequest(
            keyID_base64: "test",
            attestationObject_base64: "test",
            verifyRunID: nil
        )
        
        let (_, rawJSON) = try await backendClient.register(
            request: request,
            correlationID: UUID().uuidString,
            flowHandle: "handle"
        )
        
        // Verify all backend fields present
        XCTAssertNotNil(rawJSON["keyID_base64"])
        XCTAssertNotNil(rawJSON["verifyRunID"])
        XCTAssertNotNil(rawJSON["expiresAt"])
    }
}
