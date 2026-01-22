// flow-integrator: Zero-Authority Flow Orchestration
//
// This system implements the Zero-Authority Integrator Pattern for multi-step protocol flows.
// It enforces sequencing, correlates identifiers, records authoritative responses verbatim,
// and exposes observable state without making security decisions.
//
// Originally developed for Apple App Attest flows, this system is protocol-agnostic and
// can orchestrate any multi-step protocol where authority belongs to backend subsystems.
//
// See docs/ZERO_AUTHORITY_INTEGRATOR_PATTERN.md for the architectural pattern.
// See docs/ZERO_AUTHORITY_INTEGRATOR_TRADEOFFS.md for applicability guidance.

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
        
        // Initialize admission control (optional)
        let controlConfig = ControlConfig()
        controlConfig.log()
        
        let admissionController: AdmissionController?
        let controlMetrics: ControlMetrics?
        
        if controlConfig.enabled {
            controlMetrics = ControlMetrics()
            admissionController = AdmissionController(
                targetLatency: controlConfig.targetLatencyMS,
                kp: controlConfig.pidKp,
                ki: controlConfig.pidKi,
                kd: controlConfig.pidKd,
                ewmaAlpha: controlConfig.ewmaAlpha,
                minAdmissionRate: controlConfig.rateMinTPS,
                maxAdmissionRate: controlConfig.rateMaxTPS,
                controlDT: Double(controlConfig.controlDTMS) / 1000.0,
                burstMaxTokens: controlConfig.burstMaxTokens,
                metrics: controlMetrics!
            )
            
            app.logger.info("Admission control enabled", metadata: [
                "target_latency_ms": "\(controlConfig.targetLatencyMS)",
                "rate_min_tps": "\(controlConfig.rateMinTPS)",
                "rate_max_tps": "\(controlConfig.rateMaxTPS)"
            ])
        } else {
            admissionController = nil
            controlMetrics = nil
        }
        
        // Configure HTTP client for backend
        app.http.client.configuration.timeout = HTTPClient.Configuration.Timeout(
            connect: .milliseconds(Int64(Environment.backendTimeoutMS)),
            read: .milliseconds(Int64(Environment.backendTimeoutMS))
        )
        
        let backendClient = BackendClient(
            baseURL: Environment.backendBaseURL,
            timeoutMS: Environment.backendTimeoutMS,
            client: app.http.client,
            admissionController: admissionController
        )
        
        // Configure error handling middleware
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))
        
        // Configure routes
        configureRoutes(
            app,
            flowStore: flowStore,
            backendClient: backendClient,
            metrics: metrics,
            logger: logger,
            admissionController: admissionController,
            controlMetrics: controlMetrics
        )
        
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
