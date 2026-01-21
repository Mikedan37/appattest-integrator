import Foundation

/// Admission controller using PID feedback to maintain target backend latency.
///
/// Measures backend latency, computes admission rate using PID control,
/// and enforces admission limits to prevent overload.
struct AdmissionController {
    /// PID controller
    private var pid: PIDController
    
    /// EWMA filter for latency smoothing
    private var latencyFilter: EWMAFilter
    
    /// Current admission rate (flows per second)
    private(set) var admissionRate: Double
    
    /// Target latency (milliseconds)
    let targetLatency: Double
    
    init(
        targetLatency: Double = 100.0,
        kp: Double = 10.0,
        ki: Double = 1.0,
        kd: Double = 0.1,
        ewmaAlpha: Double = 0.1,
        minAdmissionRate: Double = 1.0,
        maxAdmissionRate: Double = 1000.0
    ) {
        self.targetLatency = targetLatency
        self.pid = PIDController(
            kp: kp,
            ki: ki,
            kd: kd,
            setpoint: targetLatency,
            minOutput: minAdmissionRate,
            maxOutput: maxAdmissionRate
        )
        self.latencyFilter = EWMAFilter(alpha: ewmaAlpha)
        self.admissionRate = maxAdmissionRate  // Start at max, will adjust down if needed
    }
    
    /// Update controller with new latency measurement.
    ///
    /// - Parameter latency: Measured backend latency (milliseconds)
    /// - Returns: New admission rate (flows per second)
    mutating func update(latency: Double) -> Double {
        // Filter latency measurement
        let filteredLatency = latencyFilter.update(measurement: latency)
        
        // Compute admission rate using PID
        admissionRate = pid.compute(measured: filteredLatency)
        
        return admissionRate
    }
    
    /// Check if new flow should be admitted.
    ///
    /// - Parameter currentTime: Current time (seconds since epoch)
    /// - Returns: True if flow should be admitted
    func shouldAdmit(currentTime: TimeInterval) -> Bool {
        // Simple rate limiting: admit if below rate limit
        // In production, use token bucket or sliding window
        return true  // Placeholder - implement actual rate limiting
    }
    
    /// Reset controller state.
    mutating func reset() {
        pid.reset()
        latencyFilter.reset()
        admissionRate = pid.maxOutput
    }
}
