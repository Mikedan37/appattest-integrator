import Foundation

/// Admission controller using PID feedback to maintain target backend latency.
///
/// Measures backend latency, computes admission rate using PID control,
/// and enforces admission limits via token bucket to prevent overload.
actor AdmissionController {
    /// PID controller
    private var pid: PIDController
    
    /// EWMA filter for latency smoothing
    private var latencyFilter: EWMAFilter
    
    /// Token bucket for rate limiting
    private let tokenBucket: TokenBucket
    
    /// Current admission rate (tokens per second)
    private(set) var admissionRate: Double
    
    /// Target latency (milliseconds)
    let targetLatency: Double
    
    /// Control update period (seconds)
    let controlDT: Double
    
    /// Metrics collector
    private let metrics: ControlMetrics
    
    init(
        targetLatency: Double,
        kp: Double,
        ki: Double,
        kd: Double,
        ewmaAlpha: Double,
        minAdmissionRate: Double,
        maxAdmissionRate: Double,
        controlDT: Double,
        burstMaxTokens: Int,
        metrics: ControlMetrics
    ) {
        self.targetLatency = targetLatency
        self.controlDT = controlDT
        self.metrics = metrics
        
        self.pid = PIDController(
            kp: kp,
            ki: ki,
            kd: kd,
            setpoint: targetLatency,
            minOutput: minAdmissionRate,
            maxOutput: maxAdmissionRate,
            dt: controlDT
        )
        
        self.latencyFilter = EWMAFilter(alpha: ewmaAlpha)
        self.admissionRate = maxAdmissionRate  // Start at max, will adjust down if needed
        
        self.tokenBucket = TokenBucket(
            maxTokens: Double(burstMaxTokens),
            initialFillRate: maxAdmissionRate
        )
    }
    
    /// Record latency measurement for a route.
    ///
    /// - Parameters:
    ///   - latency: Measured backend latency (milliseconds)
    ///   - route: Route name (e.g., "/app-attest/register")
    func recordLatency(_ latency: Double, route: String) async {
        // Update route-specific latency metric
        await metrics.updateRouteLatency(route: route, latency: latency)
        
        // Filter latency measurement
        let filteredLatency = latencyFilter.update(measurement: latency)
        await metrics.updateEWMALatency(filteredLatency)
        
        // Compute admission rate using PID
        admissionRate = pid.compute(measured: filteredLatency)
        
        // Update token bucket fill rate
        await tokenBucket.updateFillRate(admissionRate)
        
        // Update metrics
        await metrics.updateAdmissionRate(admissionRate)
        await metrics.updatePID(
            error: pid.error,
            pTerm: pid.pTerm,
            iTerm: pid.iTerm,
            dTerm: pid.dTerm
        )
        
        let tokens = await tokenBucket.getTokenCount()
        await metrics.updateTokenBucketTokens(tokens)
    }
    
    /// Check if request should be admitted.
    ///
    /// - Returns: Tuple (admitted: Bool, retryAfterMS: Int?)
    func tryAdmit() async -> (admitted: Bool, retryAfterMS: Int?) {
        let admitted = await tokenBucket.tryConsume()
        
        if !admitted {
            // Calculate retry-after: time until next token available
            let fillRate = await tokenBucket.getFillRate()
            let retryAfterSeconds = 1.0 / max(fillRate, 0.001)  // Avoid division by zero
            let retryAfterMS = Int(retryAfterSeconds * 1000)
            return (false, retryAfterMS)
        }
        
        // Update metrics
        let tokens = await tokenBucket.getTokenCount()
        await metrics.updateTokenBucketTokens(tokens)
        
        return (true, nil)
    }
    
    /// Get current admission rate (for logging).
    func getAdmissionRate() -> Double {
        return admissionRate
    }
    
    /// Reset controller state.
    func reset() {
        pid.reset()
        latencyFilter.reset()
        admissionRate = pid.maxOutput
    }
}
