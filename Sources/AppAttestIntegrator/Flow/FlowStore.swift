import Foundation

/// Thread-safe in-memory flow store with TTL cleanup.
/// 
/// Extension point: Can be replaced with Redis/SQLite/BlazeDB for persistence.
actor FlowStore {
    private var flows: [String: FlowState] = [:]
    private var cleanupTask: Task<Void, Never>?
    private let cleanupInterval: TimeInterval = 60.0 // Check every 60 seconds
    
    init() {
        startCleanupTask()
    }
    
    /// Store a flow by flowHandle.
    func store(_ flow: FlowState) {
        flows[flow.flowHandle] = flow
    }
    
    /// Retrieve a flow by flowHandle.
    func get(_ flowHandle: String) -> FlowState? {
        return flows[flowHandle]
    }
    
    /// Update an existing flow.
    func update(_ flow: FlowState) {
        flows[flow.flowHandle] = flow
    }
    
    /// Get all flows (for metrics).
    func getAllFlows() -> [FlowState] {
        return Array(flows.values)
    }
    
    /// Get count of flows.
    func flowCount() -> Int {
        return flows.count
    }
    
    /// Get count of terminal flows.
    func terminalFlowCount() -> Int {
        return flows.values.filter { $0.terminal }.count
    }
    
    /// Start background cleanup task that marks expired flows.
    private func startCleanupTask() {
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(cleanupInterval * 1_000_000_000))
                await cleanupExpired()
            }
        }
    }
    
    /// Mark expired flows as terminal.
    private func cleanupExpired() {
        let now = Date()
        for (handle, flow) in flows {
            if !flow.terminal, let expiresAt = flow.expiresAt, now >= expiresAt {
                flows[handle] = FlowMachine.markExpired(flow)
            }
        }
    }
    
    /// Cancel cleanup task (for testing/shutdown).
    func cancelCleanup() {
        cleanupTask?.cancel()
    }
}
