import XCTest
@testable import AppAttestIntegrator

final class StepResponseTests: XCTestCase {
    
    func testStepResponse_Overshoot() async {
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
        
        // Baseline: low latency
        for _ in 0..<10 {
            await controller.recordLatency(50.0, route: "/app-attest/register")
        }
        
        // Step: high latency
        var maxLatency = 0.0
        for _ in 0..<20 {
            await controller.recordLatency(200.0, route: "/app-attest/register")
            let rate = await controller.getAdmissionRate()
            maxLatency = max(maxLatency, rate)
        }
        
        // Overshoot should be bounded
        let setpoint = await controller.targetLatency
        let initialRate = 200.0  // Started at max
        let overshoot = (maxLatency - initialRate) / initialRate
        XCTAssertLessThan(abs(overshoot), 0.5, "Overshoot should be < 50%")
    }
    
    func testStepResponse_SettlingTime() async {
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
        
        // Step input: high latency
        var settled = false
        var settlingTime = 0
        let tolerance = 0.05  // 5% tolerance
        
        for step in 0..<100 {
            await controller.recordLatency(200.0, route: "/app-attest/register")
            let rate = await controller.getAdmissionRate()
            let targetRate = await controller.targetLatency
            let error = abs(rate - targetRate) / targetRate
            
            if error < tolerance && !settled {
                settled = true
                settlingTime = step
            }
        }
        
        XCTAssertTrue(settled, "System should settle within tolerance")
        XCTAssertLessThan(settlingTime, 50, "Settling time should be < 50 steps")
    }
    
    func testStepResponse_BoundedOutput() async {
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
        
        let setpoint = await controller.targetLatency
        let maxBound = 2.0 * setpoint
        
        // Apply step and measure
        for _ in 0..<100 {
            await controller.recordLatency(500.0, route: "/app-attest/register")  // Large disturbance
            let rate = await controller.getAdmissionRate()
            XCTAssertLessThan(rate, maxBound, "Output should remain bounded")
            XCTAssertGreaterThan(rate, 1.0, "Output should not go below minimum")
        }
    }
    
    func testStepResponse_NoIntegralWindup() async {
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
        
        // Apply sustained high latency (should saturate at max)
        var rates: [Double] = []
        for _ in 0..<50 {
            await controller.recordLatency(500.0, route: "/app-attest/register")
            let rate = await controller.getAdmissionRate()
            rates.append(rate)
        }
        
        // Rate should saturate at max, not grow unbounded
        let finalRate = rates.last!
        XCTAssertLessThanOrEqual(finalRate, 200.0, "Rate should saturate at max")
        
        // Rate should stabilize, not oscillate wildly
        let variance = rates.map { pow($0 - rates.first!, 2) }.reduce(0, +) / Double(rates.count)
        XCTAssertLessThan(variance, 10000.0, "Rate should stabilize, not oscillate")
    }
}
