import Foundation
import Vapor

/// Mock backend server for testing integrator behavior.
/// Simulates appattest-backend endpoints with configurable responses.
final class MockBackend {
    private var app: Application?
    private var registerHandler: ((Request) throws -> BackendRegisterResponse)?
    private var clientDataHashHandler: ((Request) throws -> BackendClientDataHashResponse)?
    private var verifyHandler: ((Request) throws -> BackendVerifyResponse)?
    
    var receivedHeaders: [String: String] = [:]
    var receivedBodies: [String: Data] = [:]
    
    func start(port: Int = 8080) throws -> Application {
        let app = Application(.testing)
        
        app.post("app-attest", "register") { req -> BackendRegisterResponse in
            self.receivedHeaders["register"] = req.headers.first(name: "X-Correlation-ID")
            self.receivedBodies["register"] = req.body.data
            
            if let handler = self.registerHandler {
                return try handler(req)
            }
            
            return BackendRegisterResponse(
                keyID_base64: try req.content.decode(BackendRegisterRequest.self).keyID_base64,
                verifyRunID: nil,
                expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
            )
        }
        
        app.post("app-attest", "client-data-hash") { req -> BackendClientDataHashResponse in
            self.receivedHeaders["client-data-hash"] = req.headers.first(name: "X-Correlation-ID")
            self.receivedBodies["client-data-hash"] = req.body.data
            
            if let handler = self.clientDataHashHandler {
                return try handler(req)
            }
            
            return BackendClientDataHashResponse(
                clientDataHash_base64: "mock-client-data-hash",
                expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
            )
        }
        
        app.post("app-attest", "verify") { req -> BackendVerifyResponse in
            self.receivedHeaders["verify"] = req.headers.first(name: "X-Correlation-ID")
            self.receivedBodies["verify"] = req.body.data
            
            if let handler = self.verifyHandler {
                return try handler(req)
            }
            
            return BackendVerifyResponse(
                verified: true,
                reason: nil
            )
        }
        
        try app.server.start(address: .hostname("127.0.0.1", port: port))
        self.app = app
        
        return app
    }
    
    func setRegisterHandler(_ handler: @escaping (Request) throws -> BackendRegisterResponse) {
        self.registerHandler = handler
    }
    
    func setClientDataHashHandler(_ handler: @escaping (Request) throws -> BackendClientDataHashResponse) {
        self.clientDataHashHandler = handler
    }
    
    func setVerifyHandler(_ handler: @escaping (Request) throws -> BackendVerifyResponse) {
        self.verifyHandler = handler
    }
    
    func shutdown() {
        try? app?.server.shutdown()
        app = nil
    }
}
