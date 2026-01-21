import Foundation

/// Prometheus-style metrics for admission control.
///
/// Thread-safe metrics collection using actor isolation.
actor ControlMetrics {
    /// Current admission rate (tokens per second)
    private(set) var admissionRateTPS: Double = 0.0
    
    /// Current EWMA latency (milliseconds)
    private(set) var backendLatencyEWMAMS: Double = 0.0
    
    /// Last measured latency per route (milliseconds)
    private var backendLatencyLastMS: [String: Double] = [:]
    
    /// Total admission-limited requests per route
    private var admissionLimitedTotal: [String: Int] = [:]
    
    /// Current PID error
    private(set) var pidError: Double = 0.0
    
    /// Current PID P term
    private(set) var pidPTerm: Double = 0.0
    
    /// Current PID I term
    private(set) var pidITerm: Double = 0.0
    
    /// Current PID D term
    private(set) var pidDTerm: Double = 0.0
    
    /// Current token bucket token count
    private(set) var tokenBucketTokens: Double = 0.0
    
    /// Update admission rate.
    func updateAdmissionRate(_ rate: Double) {
        admissionRateTPS = rate
    }
    
    /// Update EWMA latency.
    func updateEWMALatency(_ latency: Double) {
        backendLatencyEWMAMS = latency
    }
    
    /// Update last latency for a route.
    func updateRouteLatency(route: String, latency: Double) {
        backendLatencyLastMS[route] = latency
    }
    
    /// Increment admission-limited counter for a route.
    func incrementAdmissionLimited(route: String) {
        admissionLimitedTotal[route, default: 0] += 1
    }
    
    /// Update PID terms.
    func updatePID(error: Double, pTerm: Double, iTerm: Double, dTerm: Double) {
        self.pidError = error
        self.pidPTerm = pTerm
        self.pidITerm = iTerm
        self.pidDTerm = dTerm
    }
    
    /// Update token bucket token count.
    func updateTokenBucketTokens(_ tokens: Double) {
        tokenBucketTokens = tokens
    }
    
    /// Get Prometheus-formatted metrics.
    func getPrometheusMetrics() -> String {
        var lines: [String] = []
        
        lines.append("# HELP admission_rate_tps Current admission rate in tokens per second")
        lines.append("# TYPE admission_rate_tps gauge")
        lines.append("admission_rate_tps \(admissionRateTPS)")
        
        lines.append("# HELP backend_latency_ewma_ms Current EWMA backend latency in milliseconds")
        lines.append("# TYPE backend_latency_ewma_ms gauge")
        lines.append("backend_latency_ewma_ms \(backendLatencyEWMAMS)")
        
        for (route, latency) in backendLatencyLastMS {
            let routeLabel = route.replacingOccurrences(of: "/", with: "_")
            lines.append("# HELP backend_latency_last_ms Last measured backend latency per route in milliseconds")
            lines.append("# TYPE backend_latency_last_ms gauge")
            lines.append("backend_latency_last_ms{route=\"\(route)\"} \(latency)")
        }
        
        for (route, count) in admissionLimitedTotal {
            lines.append("# HELP admission_limited_total Total admission-limited requests per route")
            lines.append("# TYPE admission_limited_total counter")
            lines.append("admission_limited_total{route=\"\(route)\"} \(count)")
        }
        
        lines.append("# HELP pid_error Current PID error signal")
        lines.append("# TYPE pid_error gauge")
        lines.append("pid_error \(pidError)")
        
        lines.append("# HELP pid_p_term Current PID proportional term")
        lines.append("# TYPE pid_p_term gauge")
        lines.append("pid_p_term \(pidPTerm)")
        
        lines.append("# HELP pid_i_term Current PID integral term")
        lines.append("# TYPE pid_i_term gauge")
        lines.append("pid_i_term \(pidITerm)")
        
        lines.append("# HELP pid_d_term Current PID derivative term")
        lines.append("# TYPE pid_d_term gauge")
        lines.append("pid_d_term \(pidDTerm)")
        
        lines.append("# HELP token_bucket_tokens Current token bucket token count")
        lines.append("# TYPE token_bucket_tokens gauge")
        lines.append("token_bucket_tokens \(tokenBucketTokens)")
        
        return lines.joined(separator: "\n")
    }
}
