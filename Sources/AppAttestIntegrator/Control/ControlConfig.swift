import Foundation

/// Configuration for admission control subsystem.
///
/// All settings are read from environment variables with safe defaults.
/// Admission control is opt-in via APP_ATTEST_ADMISSION_CONTROL_ENABLED.
struct ControlConfig {
    /// Whether admission control is enabled
    let enabled: Bool
    
    /// Target latency in milliseconds
    let targetLatencyMS: Double
    
    /// EWMA smoothing factor (0 < alpha <= 1)
    let ewmaAlpha: Double
    
    /// PID proportional gain
    let pidKp: Double
    
    /// PID integral gain
    let pidKi: Double
    
    /// PID derivative gain
    let pidKd: Double
    
    /// Control update period in milliseconds
    let controlDTMS: Int
    
    /// Minimum admission rate (tokens per second)
    let rateMinTPS: Double
    
    /// Maximum admission rate (tokens per second)
    let rateMaxTPS: Double
    
    /// Maximum burst tokens
    let burstMaxTokens: Int
    
    init() {
        self.enabled = Self.parseBool(
            ProcessInfo.processInfo.environment["APP_ATTEST_ADMISSION_CONTROL_ENABLED"],
            default: false
        )
        
        self.targetLatencyMS = Self.parseDouble(
            ProcessInfo.processInfo.environment["APP_ATTEST_TARGET_LATENCY_MS"],
            default: 200.0,
            min: 1.0,
            max: 10000.0
        )
        
        self.ewmaAlpha = Self.parseDouble(
            ProcessInfo.processInfo.environment["APP_ATTEST_EWMA_ALPHA"],
            default: 0.2,
            min: 0.01,
            max: 1.0
        )
        
        self.pidKp = Self.parseDouble(
            ProcessInfo.processInfo.environment["APP_ATTEST_PID_KP"],
            default: 0.5,
            min: 0.0,
            max: 100.0
        )
        
        self.pidKi = Self.parseDouble(
            ProcessInfo.processInfo.environment["APP_ATTEST_PID_KI"],
            default: 0.05,
            min: 0.0,
            max: 10.0
        )
        
        self.pidKd = Self.parseDouble(
            ProcessInfo.processInfo.environment["APP_ATTEST_PID_KD"],
            default: 0.1,
            min: 0.0,
            max: 10.0
        )
        
        self.controlDTMS = Self.parseInt(
            ProcessInfo.processInfo.environment["APP_ATTEST_CONTROL_DT_MS"],
            default: 500,
            min: 100,
            max: 10000
        )
        
        self.rateMinTPS = Self.parseDouble(
            ProcessInfo.processInfo.environment["APP_ATTEST_RATE_MIN_TPS"],
            default: 1.0,
            min: 0.1,
            max: 1000.0
        )
        
        self.rateMaxTPS = Self.parseDouble(
            ProcessInfo.processInfo.environment["APP_ATTEST_RATE_MAX_TPS"],
            default: 200.0,
            min: 1.0,
            max: 10000.0
        )
        
        self.burstMaxTokens = Self.parseInt(
            ProcessInfo.processInfo.environment["APP_ATTEST_BURST_MAX_TOKENS"],
            default: 50,
            min: 1,
            max: 10000
        )
    }
    
    /// Log configuration at startup (no secrets).
    func log() {
        print("[ControlConfig] Admission control enabled: \(enabled)")
        if enabled {
            print("[ControlConfig] Target latency: \(targetLatencyMS) ms")
            print("[ControlConfig] EWMA alpha: \(ewmaAlpha)")
            print("[ControlConfig] PID gains: Kp=\(pidKp), Ki=\(pidKi), Kd=\(pidKd)")
            print("[ControlConfig] Control period: \(controlDTMS) ms")
            print("[ControlConfig] Rate limits: \(rateMinTPS)-\(rateMaxTPS) TPS")
            print("[ControlConfig] Burst tokens: \(burstMaxTokens)")
        }
    }
    
    private static func parseBool(_ value: String?, default: Bool) -> Bool {
        guard let value = value?.lowercased() else { return `default` }
        return value == "true" || value == "1" || value == "yes"
    }
    
    private static func parseDouble(_ value: String?, default: Double, min: Double, max: Double) -> Double {
        guard let value = value, let parsed = Double(value) else { return `default` }
        return max(min, min(max, parsed))
    }
    
    private static func parseInt(_ value: String?, default: Int, min: Int, max: Int) -> Int {
        guard let value = value, let parsed = Int(value) else { return `default` }
        return max(min, min(max, parsed))
    }
}
