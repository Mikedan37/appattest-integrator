import Foundation

/// Environment configuration for the integrator daemon.
/// See README "Explicit Non-Goals" section.
struct Environment {
    /// Backend base URL (default: http://127.0.0.1:8080)
    static var backendBaseURL: String {
        ProcessInfo.processInfo.environment["APP_ATTEST_BACKEND_BASE_URL"] ?? "http://127.0.0.1:8080"
    }
    
    /// Integrator listen port (default: 8090)
    static var integratorPort: Int {
        Int(ProcessInfo.processInfo.environment["APP_ATTEST_INTEGRATOR_PORT"] ?? "8090") ?? 8090
    }
    
    /// Backend request timeout in milliseconds (default: 3000)
    static var backendTimeoutMS: Int {
        Int(ProcessInfo.processInfo.environment["APP_ATTEST_BACKEND_TIMEOUT_MS"] ?? "3000") ?? 3000
    }
    
    /// Debug logging level for artifacts (0=none, 1=lengths+SHA256, 2=full dumps DEV-ONLY)
    static var debugLogArtifacts: Int {
        Int(ProcessInfo.processInfo.environment["APP_ATTEST_DEBUG_LOG_ARTIFACTS"] ?? "0") ?? 0
    }
    
    /// Build SHA256 if available from environment
    static var buildSha256: String? {
        ProcessInfo.processInfo.environment["APP_ATTEST_BUILD_SHA256"]
    }
}
