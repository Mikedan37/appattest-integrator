import Foundation
import Vapor

/// Structured logging with correlation support.
/// 
/// Never logs full base64 artifacts by default.
/// Debug levels: 0=none, 1=lengths+SHA256, 2=full dumps DEV-ONLY
struct AppLogger {
    let logger: Logger
    let debugLevel: Int
    
    init(_ logger: Logger, debugLevel: Int = 0) {
        self.logger = logger
        self.debugLevel = debugLevel
    }
    
    /// Log artifact metadata (length + SHA256 if debug enabled).
    func logArtifact(_ name: String, base64: String, correlationID: String? = nil) {
        let length = base64.count
        var metadata: [String: String] = ["name": name, "length": "\(length)"]
        
        if let correlationID = correlationID {
            metadata["correlationID"] = correlationID
        }
        
        if debugLevel >= 1 {
            // Calculate SHA256
            if let data = Data(base64Encoded: base64),
               let sha256 = sha256Hash(data) {
                metadata["sha256"] = sha256
            }
        }
        
        if debugLevel >= 2 {
            metadata["full_base64"] = base64 // DEV-ONLY
        }
        
        logger.info("Artifact", metadata: metadata)
    }
    
    /// Log flow state transition.
    func logStateTransition(
        flowHandle: String,
        flowID: String,
        correlationID: String,
        from: String,
        to: String
    ) {
        logger.info("State transition", metadata: [
            "flowHandle": flowHandle,
            "flowID": flowID,
            "correlationID": correlationID,
            "from": from,
            "to": to
        ])
    }
    
    /// Log backend request.
    func logBackendRequest(
        endpoint: String,
        correlationID: String,
        flowHandle: String,
        status: UInt
    ) {
        logger.info("Backend request", metadata: [
            "endpoint": endpoint,
            "correlationID": correlationID,
            "flowHandle": flowHandle,
            "status": "\(status)"
        ])
    }
    
    /// Log backend error.
    func logBackendError(
        endpoint: String,
        correlationID: String,
        flowHandle: String,
        error: String
    ) {
        logger.error("Backend error", metadata: [
            "endpoint": endpoint,
            "correlationID": correlationID,
            "flowHandle": flowHandle,
            "error": error
        ])
    }
    
    /// Calculate SHA256 hash of data.
    private func sha256Hash(_ data: Data) -> String? {
        #if canImport(CryptoKit)
        import CryptoKit
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
        #elseif canImport(CommonCrypto)
        import CommonCrypto
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
        #else
        // Fallback: return nil if crypto not available
        return nil
        #endif
    }
}
