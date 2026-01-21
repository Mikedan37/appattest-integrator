import Foundation
import NIOCore

/// Thread-safe token bucket for rate limiting.
///
/// Implements a token bucket algorithm where tokens are added at a configurable rate
/// and consumed by requests. Thread-safe using actor isolation.
actor TokenBucket {
    /// Current number of tokens
    private var tokens: Double
    
    /// Maximum number of tokens (burst capacity)
    private let maxTokens: Double
    
    /// Token fill rate (tokens per second)
    private var fillRate: Double
    
    /// Last update timestamp
    private var lastUpdate: Date
    
    init(maxTokens: Double, initialFillRate: Double) {
        self.tokens = maxTokens
        self.maxTokens = maxTokens
        self.fillRate = initialFillRate
        self.lastUpdate = Date()
    }
    
    /// Update fill rate (called periodically by controller).
    func updateFillRate(_ rate: Double) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdate)
        
        // Add tokens based on elapsed time
        tokens = min(maxTokens, tokens + fillRate * elapsed)
        
        fillRate = rate
        lastUpdate = now
    }
    
    /// Try to consume tokens.
    ///
    /// - Parameter count: Number of tokens to consume (default: 1)
    /// - Returns: True if tokens were consumed, false if insufficient tokens
    func tryConsume(count: Double = 1.0) -> Bool {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdate)
        
        // Add tokens based on elapsed time
        tokens = min(maxTokens, tokens + fillRate * elapsed)
        lastUpdate = now
        
        if tokens >= count {
            tokens -= count
            return true
        }
        
        return false
    }
    
    /// Get current token count (for metrics).
    func getTokenCount() -> Double {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdate)
        
        // Update tokens before reading
        tokens = min(maxTokens, tokens + fillRate * elapsed)
        lastUpdate = now
        
        return tokens
    }
    
    /// Get current fill rate (for metrics).
    func getFillRate() -> Double {
        return fillRate
    }
}
