import XCTest
@testable import AppAttestIntegrator

/// Complete state machine transition validation.
/// Tests deterministic sequencing without HTTP or backend dependencies.
final class FlowMachineCompleteTests: XCTestCase {
    
    // MARK: - Valid Transitions
    
    func testCreatedToRegistered() {
        let flow = FlowState(
            flowHandle: "handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .created,
            correlationID: UUID().uuidString
        )
        
        let result = FlowMachine.transitionToRegistered(flow)
        
        XCTAssertEqual(result.state, .registered)
        XCTAssertEqual(result.lastBackendStatus, "registered")
        XCTAssertFalse(result.terminal)
        XCTAssertEqual(result.flowHandle, flow.flowHandle)
        XCTAssertEqual(result.flowID, flow.flowID)
    }
    
    func testRegisteredToHashIssued() throws {
        let flow = FlowState(
            flowHandle: "handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .registered,
            correlationID: UUID().uuidString
        )
        
        let expiresAt = Date().addingTimeInterval(300)
        let result = try FlowMachine.transitionToHashIssued(flow, expiresAt: expiresAt)
        
        XCTAssertEqual(result.state, .hashIssued)
        XCTAssertEqual(result.expiresAt, expiresAt)
        XCTAssertEqual(result.lastBackendStatus, "hash_issued")
        XCTAssertFalse(result.terminal)
    }
    
    func testHashIssuedToVerified() throws {
        let flow = FlowState(
            flowHandle: "handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            expiresAt: Date().addingTimeInterval(300),
            state: .hashIssued,
            correlationID: UUID().uuidString
        )
        
        let result = try FlowMachine.transitionToVerified(flow)
        
        XCTAssertEqual(result.state, .verified)
        XCTAssertTrue(result.terminal)
        XCTAssertEqual(result.lastBackendStatus, "verified")
    }
    
    func testHashIssuedToRejected() throws {
        let flow = FlowState(
            flowHandle: "handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .hashIssued,
            correlationID: UUID().uuidString
        )
        
        let result = try FlowMachine.transitionToRejected(flow, reason: "test reason")
        
        XCTAssertEqual(result.state, .rejected)
        XCTAssertTrue(result.terminal)
        XCTAssertEqual(result.lastBackendStatus, "rejected")
        XCTAssertEqual(result.lastBackendReason, "test reason")
    }
    
    // MARK: - Invalid Transitions
    
    func testAssertBeforeRegister() {
        let flow = FlowState(
            flowHandle: "handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .created,
            correlationID: UUID().uuidString
        )
        
        XCTAssertThrowsError(try FlowMachine.transitionToHashIssued(flow, expiresAt: Date())) { error in
            guard case FlowError.sequenceViolation(let current, let required) = error else {
                XCTFail("Expected sequenceViolation")
                return
            }
            XCTAssertEqual(current, "created")
            XCTAssertEqual(required, "registered")
        }
    }
    
    func testRequestClientDataHashTwice() {
        let flow = FlowState(
            flowHandle: "handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .hashIssued,
            correlationID: UUID().uuidString
        )
        
        XCTAssertThrowsError(try FlowMachine.transitionToHashIssued(flow, expiresAt: Date())) { error in
            guard case FlowError.sequenceViolation(let current, let required) = error else {
                XCTFail("Expected sequenceViolation")
                return
            }
            XCTAssertEqual(current, "hash_issued")
            XCTAssertEqual(required, "registered")
        }
    }
    
    func testAssertTwiceAfterTerminal() {
        let flow = FlowState(
            flowHandle: "handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .verified,
            terminal: true,
            correlationID: UUID().uuidString
        )
        
        XCTAssertThrowsError(try FlowMachine.transitionToVerified(flow)) { error in
            guard case FlowError.terminalState(let state) = error else {
                XCTFail("Expected terminalState")
                return
            }
            XCTAssertEqual(state, "verified")
        }
    }
    
    func testAnyMutationAfterTerminal() {
        let terminalStates: [FlowStateEnum] = [.verified, .rejected, .expired, .error]
        
        for terminalState in terminalStates {
            let flow = FlowState(
                flowHandle: "handle",
                flowID: UUID().uuidString,
                keyID_base64: "dGVzdA==",
                verifyRunID: nil,
                state: terminalState,
                terminal: true,
                correlationID: UUID().uuidString
            )
            
            // All mutations should fail
            XCTAssertThrowsError(try FlowMachine.transitionToHashIssued(flow, expiresAt: Date())) { error in
                guard case FlowError.terminalState = error else {
                    XCTFail("Expected terminalState for \(terminalState)")
                    return
                }
            }
            
            if terminalState == .hashIssued {
                XCTAssertThrowsError(try FlowMachine.transitionToVerified(flow)) { error in
                    guard case FlowError.terminalState = error else {
                        XCTFail("Expected terminalState")
                        return
                    }
                }
            }
        }
    }
    
    func testExpiredFlowRejectsMutation() {
        let flow = FlowState(
            flowHandle: "handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            expiresAt: Date().addingTimeInterval(-100),
            state: .registered,
            correlationID: UUID().uuidString
        )
        
        XCTAssertThrowsError(try FlowMachine.transitionToHashIssued(flow, expiresAt: Date())) { error in
            guard case FlowError.expired = error else {
                XCTFail("Expected expired")
                return
            }
        }
    }
    
    // MARK: - State Preservation
    
    func testTransitionPreservesImmutableFields() {
        let originalFlow = FlowState(
            flowHandle: "original-handle",
            flowID: "original-flow-id",
            keyID_base64: "original-key",
            verifyRunID: "original-run-id",
            state: .created,
            correlationID: "original-correlation-id"
        )
        
        let result = FlowMachine.transitionToRegistered(originalFlow)
        
        XCTAssertEqual(result.flowHandle, originalFlow.flowHandle)
        XCTAssertEqual(result.flowID, originalFlow.flowID)
        XCTAssertEqual(result.keyID_base64, originalFlow.keyID_base64)
        XCTAssertEqual(result.verifyRunID, originalFlow.verifyRunID)
        XCTAssertEqual(result.correlationID, originalFlow.correlationID)
        XCTAssertEqual(result.issuedAt, originalFlow.issuedAt)
    }
    
    func testTransitionDoesNotModifyOriginal() {
        let originalFlow = FlowState(
            flowHandle: "handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            state: .created,
            correlationID: UUID().uuidString
        )
        
        let originalState = originalFlow.state
        _ = FlowMachine.transitionToRegistered(originalFlow)
        
        XCTAssertEqual(originalFlow.state, originalState)
    }
}
