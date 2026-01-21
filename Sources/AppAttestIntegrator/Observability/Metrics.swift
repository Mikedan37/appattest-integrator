import Foundation

/// Simple in-memory metrics counters.
/// 
/// Extension point: Can be replaced with Prometheus client library.
actor Metrics {
    private var flowStartedTotal: Int = 0
    private var flowCompletedTotal: Int = 0
    private var flowFailedTotal: Int = 0
    private var backendRequestsTotal: [String: Int] = [:]
    private var sequenceViolationTotal: Int = 0
    
    func incrementFlowStarted() {
        flowStartedTotal += 1
    }
    
    func incrementFlowCompleted() {
        flowCompletedTotal += 1
    }
    
    func incrementFlowFailed() {
        flowFailedTotal += 1
    }
    
    func incrementBackendRequest(route: String) {
        backendRequestsTotal[route, default: 0] += 1
    }
    
    func incrementSequenceViolation() {
        sequenceViolationTotal += 1
    }
    
    /// Get Prometheus-format metrics string.
    func getPrometheusMetrics() -> String {
        var lines: [String] = []
        
        lines.append("# HELP flow_started_total Total flows started")
        lines.append("# TYPE flow_started_total counter")
        lines.append("flow_started_total \(flowStartedTotal)")
        
        lines.append("# HELP flow_completed_total Total flows completed")
        lines.append("# TYPE flow_completed_total counter")
        lines.append("flow_completed_total \(flowCompletedTotal)")
        
        lines.append("# HELP flow_failed_total Total flows failed")
        lines.append("# TYPE flow_failed_total counter")
        lines.append("flow_failed_total \(flowFailedTotal)")
        
        lines.append("# HELP backend_requests_total Total backend requests by route")
        lines.append("# TYPE backend_requests_total counter")
        for (route, count) in backendRequestsTotal {
            let sanitized = route.replacingOccurrences(of: "\"", with: "\\\"")
            lines.append("backend_requests_total{route=\"\(sanitized)\"} \(count)")
        }
        
        lines.append("# HELP sequence_violation_total Total sequence violations")
        lines.append("# TYPE sequence_violation_total counter")
        lines.append("sequence_violation_total \(sequenceViolationTotal)")
        
        return lines.joined(separator: "\n")
    }
}
