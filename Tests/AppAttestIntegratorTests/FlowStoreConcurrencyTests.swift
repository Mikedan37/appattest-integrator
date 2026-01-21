import XCTest
@testable import AppAttestIntegrator

/// FlowStore concurrency and expiration validation.
final class FlowStoreConcurrencyTests: XCTestCase {
    
    func testConcurrentUpdates() async {
        let store = FlowStore()
        let flowHandle = "concurrent-handle"
        
        let flow = FlowState(
            flowHandle: flowHandle,
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            correlationID: UUID().uuidString
        )
        
        await store.store(flow)
        
        // Concurrent updates
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    var updated = flow
                    updated.lastBackendStatus = "update-\(i)"
                    await store.update(updated)
                }
            }
        }
        
        let final = await store.get(flowHandle)
        XCTAssertNotNil(final)
        XCTAssertNotNil(final?.lastBackendStatus)
    }
    
    func testConcurrentReads() async {
        let store = FlowStore()
        let flowHandle = "read-handle"
        
        let flow = FlowState(
            flowHandle: flowHandle,
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            correlationID: UUID().uuidString
        )
        
        await store.store(flow)
        
        // Concurrent reads
        await withTaskGroup(of: FlowState?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await store.get(flowHandle)
                }
            }
            
            var results: [FlowState?] = []
            for await result in group {
                results.append(result)
            }
            
            XCTAssertEqual(results.count, 20)
            XCTAssertTrue(results.allSatisfy { $0?.flowHandle == flowHandle })
        }
    }
    
    func testExpiredFlowMarkedTerminal() async {
        let store = FlowStore()
        let flowHandle = "expired-handle"
        
        let expiredFlow = FlowState(
            flowHandle: flowHandle,
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            expiresAt: Date().addingTimeInterval(-100),
            terminal: false,
            state: .hashIssued,
            correlationID: UUID().uuidString
        )
        
        await store.store(expiredFlow)
        
        // Manually trigger expiration
        let retrieved = await store.get(flowHandle)
        if let flow = retrieved, !flow.terminal, let expiresAt = flow.expiresAt, Date() >= expiresAt {
            let expired = FlowMachine.markExpired(flow)
            await store.update(expired)
        }
        
        let final = await store.get(flowHandle)
        XCTAssertEqual(final?.state, .expired)
        XCTAssertTrue(final?.terminal ?? false)
    }
    
    func testExpiredFlowRejectsMutation() async {
        let store = FlowStore()
        let flowHandle = "expired-mutation-handle"
        
        let expiredFlow = FlowState(
            flowHandle: flowHandle,
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            expiresAt: Date().addingTimeInterval(-100),
            terminal: false,
            state: .hashIssued,
            correlationID: UUID().uuidString
        )
        
        await store.store(expiredFlow)
        
        // Mark expired
        let retrieved = await store.get(flowHandle)
        if let flow = retrieved, !flow.terminal, let expiresAt = flow.expiresAt, Date() >= expiresAt {
            let expired = FlowMachine.markExpired(flow)
            await store.update(expired)
        }
        
        // Attempt mutation should fail
        let final = await store.get(flowHandle)
        XCTAssertNotNil(final)
        XCTAssertTrue(final?.terminal ?? false)
        
        if let flow = final {
            XCTAssertThrowsError(try FlowMachine.transitionToVerified(flow)) { error in
                guard case FlowError.terminalState = error else {
                    XCTFail("Expected terminalState")
                    return
                }
            }
        }
    }
    
    func testMultipleFlowsExpiration() async {
        let store = FlowStore()
        
        let flows = (0..<5).map { i in
            FlowState(
                flowHandle: "expired-\(i)",
                flowID: UUID().uuidString,
                keyID_base64: "dGVzdA==",
                verifyRunID: nil,
                expiresAt: Date().addingTimeInterval(-100),
                terminal: false,
                state: .hashIssued,
                correlationID: UUID().uuidString
            )
        }
        
        for flow in flows {
            await store.store(flow)
        }
        
        // Mark all expired
        for flow in flows {
            let retrieved = await store.get(flow.flowHandle)
            if let f = retrieved, !f.terminal, let expiresAt = f.expiresAt, Date() >= expiresAt {
                let expired = FlowMachine.markExpired(f)
                await store.update(expired)
            }
        }
        
        let terminalCount = await store.terminalFlowCount()
        XCTAssertEqual(terminalCount, 5)
    }
}
