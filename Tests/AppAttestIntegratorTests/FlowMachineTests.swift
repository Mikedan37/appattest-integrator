import XCTest
@testable import AppAttestIntegrator

final class FlowMachineTests: XCTestCase {
    
    func testTransitionToRegistered() {
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .created,
            correlationID: UUID().uuidString
        )
        
        let registered = FlowMachine.transitionToRegistered(flow)
        
        XCTAssertEqual(registered.state, .registered)
        XCTAssertEqual(registered.lastBackendStatus, "registered")
        XCTAssertFalse(registered.terminal)
    }
    
    func testTransitionToHashIssued_Success() throws {
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .registered,
            correlationID: UUID().uuidString
        )
        
        let expiresAt = Date().addingTimeInterval(300)
        let hashIssued = try FlowMachine.transitionToHashIssued(flow, expiresAt: expiresAt)
        
        XCTAssertEqual(hashIssued.state, .hashIssued)
        XCTAssertEqual(hashIssued.expiresAt, expiresAt)
        XCTAssertEqual(hashIssued.lastBackendStatus, "hash_issued")
    }
    
    func testTransitionToHashIssued_SequenceViolation() {
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .created,
            correlationID: UUID().uuidString
        )
        
        XCTAssertThrowsError(try FlowMachine.transitionToHashIssued(flow, expiresAt: Date())) { error in
            if case FlowError.sequenceViolation = error {
                // Expected
            } else {
                XCTFail("Expected sequenceViolation error")
            }
        }
    }
    
    func testTransitionToHashIssued_TerminalState() {
        var flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .registered,
            terminal: true,
            correlationID: UUID().uuidString
        )
        
        XCTAssertThrowsError(try FlowMachine.transitionToHashIssued(flow, expiresAt: Date())) { error in
            if case FlowError.terminalState = error {
                // Expected
            } else {
                XCTFail("Expected terminalState error")
            }
        }
    }
    
    func testTransitionToHashIssued_Expired() {
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            expiresAt: Date().addingTimeInterval(-100),
            state: .registered,
            correlationID: UUID().uuidString
        )
        
        XCTAssertThrowsError(try FlowMachine.transitionToHashIssued(flow, expiresAt: Date())) { error in
            if case FlowError.expired = error {
                // Expected
            } else {
                XCTFail("Expected expired error")
            }
        }
    }
    
    func testTransitionToVerified_Success() throws {
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            expiresAt: Date().addingTimeInterval(300),
            state: .hashIssued,
            correlationID: UUID().uuidString
        )
        
        let verified = try FlowMachine.transitionToVerified(flow)
        
        XCTAssertEqual(verified.state, .verified)
        XCTAssertTrue(verified.terminal)
        XCTAssertEqual(verified.lastBackendStatus, "verified")
    }
    
    func testTransitionToVerified_SequenceViolation() {
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .registered,
            correlationID: UUID().uuidString
        )
        
        XCTAssertThrowsError(try FlowMachine.transitionToVerified(flow)) { error in
            if case FlowError.sequenceViolation = error {
                // Expected
            } else {
                XCTFail("Expected sequenceViolation error")
            }
        }
    }
    
    func testTransitionToRejected_Success() throws {
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .hashIssued,
            correlationID: UUID().uuidString
        )
        
        let rejected = try FlowMachine.transitionToRejected(flow, reason: "test reason")
        
        XCTAssertEqual(rejected.state, .rejected)
        XCTAssertTrue(rejected.terminal)
        XCTAssertEqual(rejected.lastBackendStatus, "rejected")
        XCTAssertEqual(rejected.lastBackendReason, "test reason")
    }
    
    func testMarkExpired() {
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .hashIssued,
            correlationID: UUID().uuidString
        )
        
        let expired = FlowMachine.markExpired(flow)
        
        XCTAssertEqual(expired.state, .expired)
        XCTAssertTrue(expired.terminal)
        XCTAssertEqual(expired.lastBackendStatus, "expired")
    }
    
    func testMarkExpired_AlreadyTerminal() {
        var flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .verified,
            terminal: true,
            correlationID: UUID().uuidString
        )
        
        let expired = FlowMachine.markExpired(flow)
        
        // Should remain verified, not expired
        XCTAssertEqual(expired.state, .expired)
        XCTAssertTrue(expired.terminal)
    }
}
