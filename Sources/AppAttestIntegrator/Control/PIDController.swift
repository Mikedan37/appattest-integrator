import Foundation

/// PID controller for admission rate control based on backend latency.
///
/// Implements discrete-time PID control:
/// u(t) = K_p * e(t) + K_i * sum(e(i)) + K_d * (e(t) - e(t-1))
///
/// Where:
/// - e(t) = r - y(t) (error signal)
/// - r is setpoint (target latency)
/// - y(t) is measured output (EWMA latency)
/// - u(t) is control output (admission rate)
struct PIDController {
    /// Proportional gain
    let kp: Double
    
    /// Integral gain
    let ki: Double
    
    /// Derivative gain
    let kd: Double
    
    /// Setpoint (target latency in milliseconds)
    let setpoint: Double
    
    /// Minimum control output (minimum admission rate)
    let minOutput: Double
    
    /// Maximum control output (maximum admission rate)
    let maxOutput: Double
    
    /// Sampling period (seconds)
    let dt: Double
    
    /// Internal state
    private var integral: Double = 0.0
    private var previousError: Double = 0.0
    private var previousOutput: Double = 0.0
    
    /// Last computed P, I, D terms (for observability)
    private(set) var pTerm: Double = 0.0
    private(set) var iTerm: Double = 0.0
    private(set) var dTerm: Double = 0.0
    private(set) var error: Double = 0.0
    
    init(
        kp: Double = 10.0,
        ki: Double = 1.0,
        kd: Double = 0.1,
        setpoint: Double,
        minOutput: Double = 1.0,
        maxOutput: Double = 1000.0,
        dt: Double = 1.0
    ) {
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.setpoint = setpoint
        self.minOutput = minOutput
        self.maxOutput = maxOutput
        self.dt = dt
    }
    
    /// Compute control output given measured value.
    ///
    /// - Parameter measured: Measured output (EWMA latency)
    /// - Returns: Control output (admission rate), clipped to [minOutput, maxOutput]
    mutating func compute(measured: Double) -> Double {
        error = setpoint - measured
        
        // Proportional term: P(t) = Kp * e(t)
        pTerm = kp * error
        
        // Integral term: I(t) = I(t-1) + Ki * e(t) * Δt
        integral += error * dt
        iTerm = ki * integral
        
        // Derivative term: D(t) = Kd * (e(t) - e(t-1)) / Δt
        dTerm = kd * (error - previousError) / dt
        
        // PID output: u(t) = P(t) + I(t) + D(t)
        let output = pTerm + iTerm + dTerm
        
        // Saturation: u'(t) = clip(u(t), u_min, u_max)
        let clippedOutput = max(minOutput, min(maxOutput, output))
        
        // Anti-windup: if saturated, back-calculate integrator to prevent windup
        if output != clippedOutput {
            // Back-calculate: I_term should be such that P + I + D = clipped
            // I_term = (clipped - P - D) / Ki
            let desiredITerm = (clippedOutput - pTerm - dTerm) / ki
            integral = desiredITerm / dt  // Adjust integral to match desired I term
            iTerm = ki * integral
        }
        
        previousError = error
        previousOutput = clippedOutput
        
        return clippedOutput
    }
    
    /// Reset controller state.
    mutating func reset() {
        integral = 0.0
        previousError = 0.0
        previousOutput = 0.0
        pTerm = 0.0
        iTerm = 0.0
        dTerm = 0.0
        error = 0.0
    }
}

/// Exponentially-weighted moving average (EWMA) filter for latency smoothing.
struct EWMAFilter {
    /// Smoothing factor (0 < alpha <= 1)
    let alpha: Double
    
    /// Current filtered value
    private var value: Double?
    
    init(alpha: Double = 0.1) {
        precondition(alpha > 0 && alpha <= 1, "alpha must be in (0, 1]")
        self.alpha = alpha
    }
    
    /// Update filter with new measurement.
    ///
    /// - Parameter measurement: New measurement value
    /// - Returns: Filtered value
    mutating func update(measurement: Double) -> Double {
        if let current = value {
            value = alpha * measurement + (1 - alpha) * current
        } else {
            value = measurement
        }
        return value!
    }
    
    /// Get current filtered value.
    var current: Double? {
        value
    }
    
    /// Reset filter.
    mutating func reset() {
        value = nil
    }
}
