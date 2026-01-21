import XCTest
@testable import AppAttestIntegrator

final class ControlLoopTests: XCTestCase {
    
    func testStepResponse_Overshoot() {
        var controller = AdmissionController(
            targetLatency: 100.0,
            kp: 10.0,
            ki: 1.0,
            kd: 0.1
        )
        
        // Baseline: low latency
        for _ in 0..<10 {
            _ = controller.update(latency: 50.0)
        }
        
        // Step: high latency
        var maxLatency = 0.0
        for _ in 0..<20 {
            let latency = controller.update(latency: 200.0)
            maxLatency = max(maxLatency, latency)
        }
        
        // Overshoot should be bounded
        let setpoint = controller.targetLatency
        let overshoot = (maxLatency - setpoint) / setpoint
        XCTAssertLessThan(overshoot, 0.5, "Overshoot should be < 50%")
    }
    
    func testStepResponse_SettlingTime() {
        var controller = AdmissionController(
            targetLatency: 100.0,
            kp: 10.0,
            ki: 1.0,
            kd: 0.1
        )
        
        // Step input: high latency
        var settled = false
        var settlingTime = 0
        let tolerance = 0.05  // 5% tolerance
        
        for step in 0..<100 {
            let latency = controller.update(latency: 200.0)
            let error = abs(latency - controller.targetLatency) / controller.targetLatency
            
            if error < tolerance && !settled {
                settled = true
                settlingTime = step
            }
        }
        
        XCTAssertTrue(settled, "System should settle within tolerance")
        XCTAssertLessThan(settlingTime, 50, "Settling time should be < 50 steps")
    }
    
    func testStepResponse_BoundedOutput() {
        var controller = AdmissionController(
            targetLatency: 100.0,
            kp: 10.0,
            ki: 1.0,
            kd: 0.1
        )
        
        let setpoint = controller.targetLatency
        let maxBound = 2.0 * setpoint
        
        // Apply step and measure
        for _ in 0..<100 {
            let latency = controller.update(latency: 500.0)  // Large disturbance
            XCTAssertLessThan(latency, maxBound, "Output should remain bounded")
        }
    }
    
    func testDisturbanceRejection() {
        var controller = AdmissionController(
            targetLatency: 100.0,
            kp: 10.0,
            ki: 1.0,
            kd: 0.1
        )
        
        // Establish steady state
        for _ in 0..<20 {
            _ = controller.update(latency: 100.0)
        }
        
        // Inject disturbance
        _ = controller.update(latency: 300.0)
        
        // Measure recovery
        var recovered = false
        let tolerance = 0.1  // 10% tolerance
        
        for _ in 0..<50 {
            let latency = controller.update(latency: 100.0)
            let error = abs(latency - controller.targetLatency) / controller.targetLatency
            
            if error < tolerance {
                recovered = true
                break
            }
        }
        
        XCTAssertTrue(recovered, "System should recover from disturbance")
    }
    
    func testPIDController_ProportionalTerm() {
        var pid = PIDController(
            kp: 10.0,
            ki: 0.0,  // Disable integral
            kd: 0.0,  // Disable derivative
            setpoint: 100.0
        )
        
        // Error = 100 - 50 = 50
        let output1 = pid.compute(measured: 50.0)
        XCTAssertGreaterThan(output1, pid.minOutput, "Output should increase for negative error")
        
        // Error = 100 - 150 = -50
        let output2 = pid.compute(measured: 150.0)
        XCTAssertLessThan(output2, output1, "Output should decrease for positive error")
    }
    
    func testPIDController_IntegralTerm() {
        var pid = PIDController(
            kp: 0.0,  // Disable proportional
            ki: 1.0,
            kd: 0.0,  // Disable derivative
            setpoint: 100.0
        )
        
        // Apply constant error
        var outputs: [Double] = []
        for _ in 0..<10 {
            let output = pid.compute(measured: 150.0)  // Constant error = -50
            outputs.append(output)
        }
        
        // Integral term should accumulate
        XCTAssertGreaterThan(outputs.last!, outputs.first!, "Integral term should accumulate")
    }
    
    func testPIDController_DerivativeTerm() {
        var pid = PIDController(
            kp: 0.0,  // Disable proportional
            ki: 0.0,  // Disable integral
            kd: 1.0,
            setpoint: 100.0
        )
        
        // Slow change
        let output1 = pid.compute(measured: 100.0)
        let output2 = pid.compute(measured: 110.0)
        
        // Fast change
        let output3 = pid.compute(measured: 100.0)
        let output4 = pid.compute(measured: 150.0)
        
        // Derivative should respond to rate of change
        let slowChange = abs(output2 - output1)
        let fastChange = abs(output4 - output3)
        
        XCTAssertGreaterThan(fastChange, slowChange, "Derivative should respond to rate of change")
    }
    
    func testPIDController_Saturation() {
        var pid = PIDController(
            kp: 1000.0,  // Large gain to force saturation
            ki: 0.0,
            kd: 0.0,
            setpoint: 100.0,
            minOutput: 1.0,
            maxOutput: 100.0
        )
        
        let output = pid.compute(measured: 0.0)
        
        XCTAssertLessThanOrEqual(output, pid.maxOutput, "Output should be clipped to max")
        XCTAssertGreaterThanOrEqual(output, pid.minOutput, "Output should be clipped to min")
    }
    
    func testEWMAFilter_Smoothing() {
        var filter = EWMAFilter(alpha: 0.1)
        
        // Apply step input
        let value1 = filter.update(measurement: 100.0)
        let value2 = filter.update(measurement: 200.0)
        let value3 = filter.update(measurement: 200.0)
        
        // Filtered value should smooth step
        XCTAssertLessThan(value2, 200.0, "Filter should smooth step")
        XCTAssertGreaterThan(value3, value2, "Filter should converge toward measurement")
    }
    
    func testAdmissionController_Convergence() {
        var controller = AdmissionController(
            targetLatency: 100.0,
            kp: 10.0,
            ki: 1.0,
            kd: 0.1
        )
        
        // Apply constant high latency
        var latencies: [Double] = []
        for _ in 0..<50 {
            let latency = controller.update(latency: 200.0)
            latencies.append(latency)
        }
        
        // System should converge (admission rate should decrease)
        let initialRate = latencies.first!
        let finalRate = latencies.last!
        
        // Admission rate should decrease to reduce latency
        XCTAssertLessThan(finalRate, initialRate, "Admission rate should decrease to reduce latency")
    }
}
