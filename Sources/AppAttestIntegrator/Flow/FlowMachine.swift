import Foundation

/// Pure functions for flow state transitions.
/// 
/// Deterministic sequencing with explicit errors for violations.
/// See README "Explicit Non-Goals" section.
enum FlowMachine {
    
    /// Transition from start to registered state.
    static func transitionToRegistered(_ flow: FlowState) -> FlowState {
        var updated = flow
        updated.state = .registered
        updated.lastBackendStatus = "registered"
        updated.terminal = false
        return updated
    }
    
    /// Transition to hash_issued state.
    static func transitionToHashIssued(_ flow: FlowState, expiresAt: Date) throws -> FlowState {
        guard flow.state == .registered else {
            throw FlowError.sequenceViolation(
                current: flow.state.rawValue,
                required: FlowStateEnum.registered.rawValue
            )
        }
        guard !flow.terminal else {
            throw FlowError.terminalState(flow.state.rawValue)
        }
        guard flow.expiresAt == nil || Date() < flow.expiresAt! else {
            throw FlowError.expired
        }
        
        var updated = flow
        updated.state = .hashIssued
        updated.expiresAt = expiresAt
        updated.lastBackendStatus = "hash_issued"
        return updated
    }
    
    /// Transition to verified state (terminal).
    static func transitionToVerified(_ flow: FlowState) throws -> FlowState {
        guard flow.state == .hashIssued else {
            throw FlowError.sequenceViolation(
                current: flow.state.rawValue,
                required: FlowStateEnum.hashIssued.rawValue
            )
        }
        guard !flow.terminal else {
            throw FlowError.terminalState(flow.state.rawValue)
        }
        guard flow.expiresAt == nil || Date() < flow.expiresAt! else {
            throw FlowError.expired
        }
        
        var updated = flow
        updated.state = .verified
        updated.terminal = true
        updated.lastBackendStatus = "verified"
        return updated
    }
    
    /// Transition to rejected state (terminal).
    static func transitionToRejected(_ flow: FlowState, reason: String?) throws -> FlowState {
        guard flow.state == .hashIssued else {
            throw FlowError.sequenceViolation(
                current: flow.state.rawValue,
                required: FlowStateEnum.hashIssued.rawValue
            )
        }
        guard !flow.terminal else {
            throw FlowError.terminalState(flow.state.rawValue)
        }
        
        var updated = flow
        updated.state = .rejected
        updated.terminal = true
        updated.lastBackendStatus = "rejected"
        updated.lastBackendReason = reason
        return updated
    }
    
    /// Mark flow as expired (terminal).
    static func markExpired(_ flow: FlowState) -> FlowState {
        var updated = flow
        if !updated.terminal {
            updated.state = .expired
            updated.terminal = true
            updated.lastBackendStatus = "expired"
        }
        return updated
    }
    
    /// Transition to error state (terminal).
    static func transitionToError(_ flow: FlowState, reason: String?) -> FlowState {
        var updated = flow
        updated.state = .error
        updated.terminal = true
        updated.lastBackendStatus = "error"
        updated.lastBackendReason = reason
        return updated
    }
}

/// Flow transition errors.
enum FlowError: Error, CustomStringConvertible {
    case sequenceViolation(current: String, required: String)
    case terminalState(String)
    case expired
    case notFound
    
    var description: String {
        switch self {
        case .sequenceViolation(let current, let required):
            return "Sequence violation: current state '\(current)', required '\(required)'"
        case .terminalState(let state):
            return "Flow is in terminal state: \(state)"
        case .expired:
            return "Flow has expired"
        case .notFound:
            return "Flow not found"
        }
    }
}
