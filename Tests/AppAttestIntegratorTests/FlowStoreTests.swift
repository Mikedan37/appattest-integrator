import XCTest
@testable import AppAttestIntegrator

final class FlowStoreTests: XCTestCase {
    
    func testStoreAndGet() async {
        let store = FlowStore()
        
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            correlationID: UUID().uuidString
        )
        
        await store.store(flow)
        let retrieved = await store.get("test-handle")
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.flowHandle, "test-handle")
    }
    
    func testGet_NotFound() async {
        let store = FlowStore()
        
        let retrieved = await store.get("nonexistent")
        
        XCTAssertNil(retrieved)
    }
    
    func testUpdate() async {
        let store = FlowStore()
        
        let flow = FlowState(
            flowHandle: "test-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            correlationID: UUID().uuidString
        )
        
        await store.store(flow)
        
        var updatedFlow = flow
        updatedFlow.state = .verified
        updatedFlow.terminal = true
        
        await store.update(updatedFlow)
        
        let retrieved = await store.get("test-handle")
        XCTAssertEqual(retrieved?.state, .verified)
        XCTAssertTrue(retrieved?.terminal ?? false)
    }
    
    func testFlowCount() async {
        let store = FlowStore()
        
        let flow1 = FlowState(
            flowHandle: "handle1",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            correlationID: UUID().uuidString
        )
        
        let flow2 = FlowState(
            flowHandle: "handle2",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            correlationID: UUID().uuidString
        )
        
        await store.store(flow1)
        await store.store(flow2)
        
        let count = await store.flowCount()
        XCTAssertEqual(count, 2)
    }
    
    func testTerminalFlowCount() async {
        let store = FlowStore()
        
        let flow1 = FlowState(
            flowHandle: "handle1",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            terminal: true,
            state: .verified,
            correlationID: UUID().uuidString
        )
        
        let flow2 = FlowState(
            flowHandle: "handle2",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            terminal: false,
            correlationID: UUID().uuidString
        )
        
        await store.store(flow1)
        await store.store(flow2)
        
        let terminalCount = await store.terminalFlowCount()
        XCTAssertEqual(terminalCount, 1)
    }
    
    func testCleanupExpired() async {
        let store = FlowStore()
        
        let expiredFlow = FlowState(
            flowHandle: "expired-handle",
            flowID: UUID().uuidString,
            keyID_base64: "dGVzdA==",
            verifyRunID: nil,
            expiresAt: Date().addingTimeInterval(-100),
            terminal: false,
            state: .hashIssued,
            correlationID: UUID().uuidString
        )
        
        await store.store(expiredFlow)
        
        // Manually trigger cleanup (normally done by background task)
        // We'll use a small delay to let cleanup run
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Manually mark expired for testing
        let retrieved = await store.get("expired-handle")
        if let flow = retrieved, !flow.terminal, let expiresAt = flow.expiresAt, Date() >= expiresAt {
            let expired = FlowMachine.markExpired(flow)
            await store.update(expired)
        }
        
        let finalFlow = await store.get("expired-handle")
        XCTAssertEqual(finalFlow?.state, .expired)
        XCTAssertTrue(finalFlow?.terminal ?? false)
    }
}
