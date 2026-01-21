import XCTest
@testable import AppAttestIntegrator

final class DisturbanceRejectionTests: XCTestCase {
    
    func testDisturbanceRejection_Recovery() async {
        let metrics = ControlMetrics()
        var controller = AdmissionController(
            targetLatency: 100.0,
            kp: 0.5,
            ki: 0.05,
            kd: 0.1,
            ewmaAlpha: 0.2,
            minAdmissionRate: 1.0,
            maxAdmissionRate: 200.0,
            controlDT: 0.5,
            burstMaxTokens: 50,
            metrics: metrics
        )
        
        // Establish steady state
        for _ in 0..<20 {
            await controller.recordLatency(100.0, route: "/app-attest/register")
        }
        
        let steadyStateRate = await controller.getAdmissionRate()
        
        // Inject disturbance (latency spike)
        await controller.recordLatency(300.0, route: "/app-attest/register")
        
        // Measure recovery
        var recovered = false
        let tolerance = 0.1  // 10% tolerance
        
        for _ in 0..<50 {
            await controller.recordLatency(100.0, route: "/app-attest/register")
            let rate = await controller.getAdmissionRate()
            let error = abs(rate - steadyStateRate) / steadyStateRate
            
            if error < tolerance {
                recovered = true
                break
            }
        }
        
        XCTAssertTrue(recovered, "System should recover from disturbance")
    }
    
    func testDisturbanceRejection_BoundedDeviation() async {
        let metrics = ControlMetrics()
        var controller = AdmissionController(
            targetLatency: 100.0,
            kp: 0.5,
            ki: 0.05,
            kd: 0.1,
            ewmaAlpha: 0.2,
            minAdmissionRate: 1.0,
            maxAdmissionRate: 200.0,
            controlDT: 0.5,
            burstMaxTokens: 50,
            metrics: metrics
        )
        
        // Establish steady state
        for _ in 0..<20 {
            await controller.recordLatency(100.0, route: "/app-attest/register")
        }
        
        let steadyStateRate = await controller.getAdmissionRate()
        
        // Inject bounded disturbance
        let disturbance = 50.0  // 50ms spike
        await controller.recordLatency(100.0 + disturbance, route: "/app-attest/register")
        
        let disturbedRate = await controller.getAdmissionRate()
        let deviation = abs(disturbedRate - steadyStateRate)
        
        // Deviation should be bounded
        XCTAssertLessThan(deviation, 100.0, "Deviation should be bounded under disturbance")
    }
    
    func testPlantModel_ConcurrencyLatencyRelationship() async {
        // Simulate plant: latency = a + b * concurrency + disturbance
        let baseLatency = 50.0
        let latencyPerConcurrency = 2.0
        let maxConcurrency = 100.0
        
        let metrics = ControlMetrics()
        var controller = AdmissionController(
            targetLatency: 100.0,
            kp: 0.5,
            ki: 0.05,
            kd: 0.1,
            ewmaAlpha: 0.2,
            minAdmissionRate: 1.0,
            maxAdmissionRate: 200.0,
            controlDT: 0.5,
            burstMaxTokens: 50,
            metrics: metrics
        )
        
        // Simulate concurrency affecting latency
        var concurrency = 10.0
        for _ in 0..<50 {
            // Plant: latency rises with concurrency
            let latency = baseLatency + latencyPerConcurrency * concurrency
            await controller.recordLatency(latency, route: "/app-attest/register")
            
            // Controller adjusts admission rate
            let admissionRate = await controller.getAdmissionRate()
            
            // Simplified: admission rate affects concurrency (with delay)
            concurrency = min(maxConcurrency, admissionRate * 0.5)
            
            // Verify boundedness
            XCTAssertLessThan(latency, 500.0, "Latency should remain bounded")
            XCTAssertGreaterThan(admissionRate, 1.0, "Admission rate should not go below minimum")
            XCTAssertLessThan(admissionRate, 200.0, "Admission rate should not exceed maximum")
        }
    }
}
