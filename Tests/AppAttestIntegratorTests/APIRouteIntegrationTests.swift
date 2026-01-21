import XCTest
import XCTVapor
@testable import AppAttestIntegrator

/// API route integration tests.
/// Tests full flow lifecycle through HTTP endpoints.
final class APIRouteIntegrationTests: XCTestCase {
    var app: Application!
    var mockBackend: MockBackend!
    var flowStore: FlowStore!
    var metrics: Metrics!
    
    override func setUp() async throws {
        mockBackend = MockBackend()
        _ = try mockBackend.start(port: 8080)
        
        app = Application(.testing)
        flowStore = FlowStore()
        metrics = Metrics()
        
        let logger = AppLogger(app.logger, debugLevel: 0)
        let backendClient = BackendClient(
            baseURL: "http://127.0.0.1:8080",
            timeoutMS: 3000,
            client: app.http.client
        )
        
        configureRoutes(app, flowStore: flowStore, backendClient: backendClient, metrics: metrics, logger: logger)
    }
    
    override func tearDown() async throws {
        mockBackend.shutdown()
        try await app.asyncShutdown()
    }
    
    func testHappyPathFlow() async throws {
        // Step 1: Start flow
        let startResponse = try await app.test(.POST, "/v1/flows/start", beforeRequest: { req in
            try req.content.encode([
                "keyID_base64": "dGVzdA==",
                "attestationObject_base64": "dGVzdA=="
            ])
        })
        
        XCTAssertEqual(startResponse.status, .ok)
        let startBody = try startResponse.content.decode(StartFlowResponse.self)
        XCTAssertEqual(startBody.state, "registered")
        XCTAssertNotNil(startBody.flowHandle)
        XCTAssertNotNil(startBody.flowID)
        
        let flowHandle = startBody.flowHandle
        
        // Step 2: Request clientDataHash
        let hashResponse = try await app.test(.POST, "/v1/flows/\(flowHandle)/client-data-hash", beforeRequest: { req in
            try req.content.encode([String: String]())
        })
        
        XCTAssertEqual(hashResponse.status, .ok)
        let hashBody = try hashResponse.content.decode(ClientDataHashResponse.self)
        XCTAssertEqual(hashBody.state, "hash_issued")
        XCTAssertNotNil(hashBody.clientDataHash_base64)
        
        // Step 3: Assert
        let assertResponse = try await app.test(.POST, "/v1/flows/\(flowHandle)/assert", beforeRequest: { req in
            try req.content.encode([
                "assertionObject_base64": "dGVzdA=="
            ])
        })
        
        XCTAssertEqual(assertResponse.status, .ok)
        let assertBody = try assertResponse.content.decode(AssertResponse.self)
        XCTAssertTrue(assertBody.terminal)
        XCTAssertNotNil(assertBody.backend)
        
        // Step 4: Status check
        let statusResponse = try await app.test(.GET, "/v1/flows/\(flowHandle)/status")
        XCTAssertEqual(statusResponse.status, .ok)
        let statusBody = try statusResponse.content.decode(FlowStatusResponse.self)
        XCTAssertTrue(statusBody.terminal)
        XCTAssertNotNil(statusBody.lastBackendStatus)
    }
    
    func testSequenceViolation_AssertBeforeHash() async throws {
        // Start flow
        let startResponse = try await app.test(.POST, "/v1/flows/start", beforeRequest: { req in
            try req.content.encode([
                "keyID_base64": "dGVzdA==",
                "attestationObject_base64": "dGVzdA=="
            ])
        })
        
        let startBody = try startResponse.content.decode(StartFlowResponse.self)
        let flowHandle = startBody.flowHandle
        
        // Attempt assert before hash
        let assertResponse = try await app.test(.POST, "/v1/flows/\(flowHandle)/assert", beforeRequest: { req in
            try req.content.encode([
                "assertionObject_base64": "dGVzdA=="
            ])
        })
        
        XCTAssertEqual(assertResponse.status, .conflict)
        
        // Verify state unchanged
        let statusResponse = try await app.test(.GET, "/v1/flows/\(flowHandle)/status")
        let statusBody = try statusResponse.content.decode(FlowStatusResponse.self)
        XCTAssertEqual(statusBody.state, "registered")
    }
    
    func testSequenceViolation_CallHashTwice() async throws {
        // Start flow
        let startResponse = try await app.test(.POST, "/v1/flows/start", beforeRequest: { req in
            try req.content.encode([
                "keyID_base64": "dGVzdA==",
                "attestationObject_base64": "dGVzdA=="
            ])
        })
        
        let startBody = try startResponse.content.decode(StartFlowResponse.self)
        let flowHandle = startBody.flowHandle
        
        // First hash request
        _ = try await app.test(.POST, "/v1/flows/\(flowHandle)/client-data-hash", beforeRequest: { req in
            try req.content.encode([String: String]())
        })
        
        // Second hash request (should fail)
        let hashResponse2 = try await app.test(.POST, "/v1/flows/\(flowHandle)/client-data-hash", beforeRequest: { req in
            try req.content.encode([String: String]())
        })
        
        XCTAssertEqual(hashResponse2.status, .conflict)
    }
    
    func testSequenceViolation_AssertAfterTerminal() async throws {
        // Complete flow
        let startResponse = try await app.test(.POST, "/v1/flows/start", beforeRequest: { req in
            try req.content.encode([
                "keyID_base64": "dGVzdA==",
                "attestationObject_base64": "dGVzdA=="
            ])
        })
        
        let startBody = try startResponse.content.decode(StartFlowResponse.self)
        let flowHandle = startBody.flowHandle
        
        _ = try await app.test(.POST, "/v1/flows/\(flowHandle)/client-data-hash", beforeRequest: { req in
            try req.content.encode([String: String]())
        })
        
        _ = try await app.test(.POST, "/v1/flows/\(flowHandle)/assert", beforeRequest: { req in
            try req.content.encode([
                "assertionObject_base64": "dGVzdA=="
            ])
        })
        
        // Attempt second assert (should fail)
        let assertResponse2 = try await app.test(.POST, "/v1/flows/\(flowHandle)/assert", beforeRequest: { req in
            try req.content.encode([
                "assertionObject_base64": "dGVzdA=="
            ])
        })
        
        XCTAssertEqual(assertResponse2.status, .conflict)
    }
    
    func testFlowHandleStability() async throws {
        let startResponse = try await app.test(.POST, "/v1/flows/start", beforeRequest: { req in
            try req.content.encode([
                "keyID_base64": "dGVzdA==",
                "attestationObject_base64": "dGVzdA=="
            ])
        })
        
        let startBody = try startResponse.content.decode(StartFlowResponse.self)
        let flowHandle = startBody.flowHandle
        
        // Verify handle remains stable through flow
        let status1 = try await app.test(.GET, "/v1/flows/\(flowHandle)/status")
        let statusBody1 = try status1.content.decode(FlowStatusResponse.self)
        XCTAssertEqual(statusBody1.flowHandle, flowHandle)
        
        _ = try await app.test(.POST, "/v1/flows/\(flowHandle)/client-data-hash", beforeRequest: { req in
            try req.content.encode([String: String]())
        })
        
        let status2 = try await app.test(.GET, "/v1/flows/\(flowHandle)/status")
        let statusBody2 = try status2.content.decode(FlowStatusResponse.self)
        XCTAssertEqual(statusBody2.flowHandle, flowHandle)
    }
}
