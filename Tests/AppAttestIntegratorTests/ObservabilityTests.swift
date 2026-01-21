import XCTest
@testable import AppAttestIntegrator

/// Observability validation.
/// Tests logging correlation and metrics accuracy.
final class ObservabilityTests: XCTestCase {
    
    func testMetricsIncrementFlowStarted() async {
        let metrics = Metrics()
        
        await metrics.incrementFlowStarted()
        await metrics.incrementFlowStarted()
        
        let prometheus = await metrics.getPrometheusMetrics()
        XCTAssertTrue(prometheus.contains("flow_started_total 2"))
    }
    
    func testMetricsIncrementFlowCompleted() async {
        let metrics = Metrics()
        
        await metrics.incrementFlowCompleted()
        
        let prometheus = await metrics.getPrometheusMetrics()
        XCTAssertTrue(prometheus.contains("flow_completed_total 1"))
    }
    
    func testMetricsIncrementFlowFailed() async {
        let metrics = Metrics()
        
        await metrics.incrementFlowFailed()
        await metrics.incrementFlowFailed()
        
        let prometheus = await metrics.getPrometheusMetrics()
        XCTAssertTrue(prometheus.contains("flow_failed_total 2"))
    }
    
    func testMetricsBackendRequestsByRoute() async {
        let metrics = Metrics()
        
        await metrics.incrementBackendRequest(route: "/app-attest/register")
        await metrics.incrementBackendRequest(route: "/app-attest/register")
        await metrics.incrementBackendRequest(route: "/app-attest/verify")
        
        let prometheus = await metrics.getPrometheusMetrics()
        XCTAssertTrue(prometheus.contains("backend_requests_total{route=\"/app-attest/register\"} 2"))
        XCTAssertTrue(prometheus.contains("backend_requests_total{route=\"/app-attest/verify\"} 1"))
    }
    
    func testMetricsSequenceViolation() async {
        let metrics = Metrics()
        
        await metrics.incrementSequenceViolation()
        
        let prometheus = await metrics.getPrometheusMetrics()
        XCTAssertTrue(prometheus.contains("sequence_violation_total 1"))
    }
    
    func testCorrelationIDStability() {
        let flow1 = FlowState(
            flowHandle: "handle1",
            flowID: UUID().uuidString,
            keyID_base64: "test",
            verifyRunID: nil,
            correlationID: "correlation-123"
        )
        
        let flow2 = FlowState(
            flowHandle: "handle2",
            flowID: UUID().uuidString,
            keyID_base64: "test",
            verifyRunID: nil,
            correlationID: "correlation-123"
        )
        
        // Same correlation ID can be used across flows
        XCTAssertEqual(flow1.correlationID, flow2.correlationID)
    }
    
    func testFlowHandleUniqueness() {
        let handles = (0..<100).map { _ in
            generateFlowHandle()
        }
        
        let uniqueHandles = Set(handles)
        XCTAssertEqual(handles.count, uniqueHandles.count)
    }
}
