import Vapor
import Foundation

@main
enum AppAttestIntegrator {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = Application(env)
        defer { app.shutdown() }
        
        // Initialize components
        let flowStore = FlowStore()
        let metrics = Metrics()
        let logger = AppLogger(app.logger, debugLevel: Environment.debugLogArtifacts)
        
        // Configure HTTP client for backend
        app.http.client.configuration.timeout = HTTPClient.Configuration.Timeout(
            connect: .milliseconds(Int64(Environment.backendTimeoutMS)),
            read: .milliseconds(Int64(Environment.backendTimeoutMS))
        )
        
        let backendClient = BackendClient(
            baseURL: Environment.backendBaseURL,
            timeoutMS: Environment.backendTimeoutMS,
            client: app.http.client
        )
        
        // Configure error handling middleware
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))
        
        // Configure routes
        configureRoutes(app, flowStore: flowStore, backendClient: backendClient, metrics: metrics, logger: logger)
        
        // Configure server
        app.http.server.configuration.hostname = "0.0.0.0"
        app.http.server.configuration.port = Environment.integratorPort
        
        app.logger.info("Starting AppAttestIntegrator", metadata: [
            "port": "\(Environment.integratorPort)",
            "backendURL": Environment.backendBaseURL
        ])
        
        try await app.run()
    }
}
