import Foundation
import Vapor

/// HTTP API routes for flow orchestration.
/// 
/// Hard non-goals: No cryptographic verification, no trust decisions, no policy logic.
func configureRoutes(
    _ app: Application,
    flowStore: FlowStore,
    backendClient: BackendClient,
    metrics: Metrics,
    logger: AppLogger
) {
    let startTime = Date()
    
    // POST /v1/flows/start
    app.post("v1", "flows", "start") { req async throws -> StartFlowResponse in
        let request = try req.content.decode(StartFlowRequest.self)
        
        // Generate flow identifiers
        let flowID = UUID().uuidString
        let flowHandle = generateFlowHandle()
        let correlationID = UUID().uuidString
        
        logger.logArtifact("keyID", base64: request.keyID_base64, correlationID: correlationID)
        logger.logArtifact("attestationObject", base64: request.attestationObject_base64, correlationID: correlationID)
        
        // Call backend register
        let backendRequest = BackendRegisterRequest(
            keyID_base64: request.keyID_base64,
            attestationObject_base64: request.attestationObject_base64,
            verifyRunID: request.verifyRunID
        )
        
        do {
            await metrics.incrementBackendRequest(route: "/app-attest/register")
            let (backendResponse, _) = try await backendClient.register(
                request: backendRequest,
                correlationID: correlationID,
                flowHandle: flowHandle
            )
            
            logger.logBackendRequest(
                endpoint: "/app-attest/register",
                correlationID: correlationID,
                flowHandle: flowHandle,
                status: 200
            )
            
            // Parse expiresAt from backend
            var expiresAt: Date?
            if let expiresAtStr = backendResponse.expiresAt {
                let formatter = ISO8601DateFormatter()
                expiresAt = formatter.date(from: expiresAtStr)
            }
            
            // Create flow state
            let flow = FlowState(
                flowHandle: flowHandle,
                flowID: flowID,
                keyID_base64: request.keyID_base64,
                verifyRunID: request.verifyRunID,
                expiresAt: expiresAt,
                correlationID: correlationID
            )
            
            let registeredFlow = FlowMachine.transitionToRegistered(flow)
            await flowStore.store(registeredFlow)
            await metrics.incrementFlowStarted()
            
            logger.logStateTransition(
                flowHandle: flowHandle,
                flowID: flowID,
                correlationID: correlationID,
                from: "created",
                to: "registered"
            )
            
            let formatter = ISO8601DateFormatter()
            return StartFlowResponse(
                flowHandle: flowHandle,
                flowID: flowID,
                keyID_base64: request.keyID_base64,
                verifyRunID: request.verifyRunID,
                state: "registered",
                issuedAt: formatter.string(from: registeredFlow.issuedAt),
                expiresAt: registeredFlow.expiresAt.map { formatter.string(from: $0) }
            )
        } catch {
            logger.logBackendError(
                endpoint: "/app-attest/register",
                correlationID: correlationID,
                flowHandle: flowHandle,
                error: "\(error)"
            )
            throw Abort(.badGateway, reason: "Backend error: \(error)")
        }
    }
    
    // POST /v1/flows/{flowHandle}/client-data-hash
    app.post("v1", "flows", ":flowHandle", "client-data-hash") { req async throws -> ClientDataHashResponse in
        guard let flowHandle = req.parameters.get("flowHandle") else {
            throw Abort(.badRequest, reason: "Missing flowHandle")
        }
        
        let request = try req.content.decode(ClientDataHashRequest.self)
        
        guard var flow = await flowStore.get(flowHandle) else {
            await metrics.incrementSequenceViolation()
            throw Abort(.notFound, reason: "Flow not found")
        }
        
        do {
            // Enforce sequencing
            let updatedFlow = try FlowMachine.transitionToHashIssued(flow, expiresAt: Date().addingTimeInterval(300)) // 5 min default
            
            // Call backend for clientDataHash
            await metrics.incrementBackendRequest(route: "/app-attest/client-data-hash")
            let (backendResponse, _) = try await backendClient.requestClientDataHash(
                keyID_base64: flow.keyID_base64,
                verifyRunID: request.verifyRunID ?? flow.verifyRunID,
                correlationID: flow.correlationID,
                flowHandle: flowHandle
            )
            
            logger.logBackendRequest(
                endpoint: "/app-attest/client-data-hash",
                correlationID: flow.correlationID,
                flowHandle: flowHandle,
                status: 200
            )
            
            // Parse expiresAt from backend
            let formatter = ISO8601DateFormatter()
            guard let expiresAt = formatter.date(from: backendResponse.expiresAt) else {
                throw Abort(.internalServerError, reason: "Invalid expiresAt from backend")
            }
            
            var finalFlow = updatedFlow
            finalFlow.expiresAt = expiresAt
            finalFlow.clientDataHash_base64 = backendResponse.clientDataHash_base64
            await flowStore.update(finalFlow)
            
            logger.logStateTransition(
                flowHandle: flowHandle,
                flowID: flow.flowID,
                correlationID: flow.correlationID,
                from: "registered",
                to: "hash_issued"
            )
            
            return ClientDataHashResponse(
                clientDataHash_base64: backendResponse.clientDataHash_base64,
                expiresAt: backendResponse.expiresAt,
                state: "hash_issued"
            )
        } catch let error as FlowError {
            await metrics.incrementSequenceViolation()
            switch error {
            case .sequenceViolation:
                throw Abort(.conflict, reason: error.description)
            case .terminalState:
                throw Abort(.conflict, reason: error.description)
            case .expired:
                throw Abort(.gone, reason: error.description)
            case .notFound:
                throw Abort(.notFound, reason: error.description)
            }
        } catch {
            logger.logBackendError(
                endpoint: "/app-attest/client-data-hash",
                correlationID: flow.correlationID,
                flowHandle: flowHandle,
                error: "\(error)"
            )
            throw Abort(.badGateway, reason: "Backend error: \(error)")
        }
    }
    
    // POST /v1/flows/{flowHandle}/assert
    app.post("v1", "flows", ":flowHandle", "assert") { req async throws -> AssertResponse in
        guard let flowHandle = req.parameters.get("flowHandle") else {
            throw Abort(.badRequest, reason: "Missing flowHandle")
        }
        
        let request = try req.content.decode(AssertRequest.self)
        
        guard var flow = await flowStore.get(flowHandle) else {
            await metrics.incrementSequenceViolation()
            throw Abort(.notFound, reason: "Flow not found")
        }
        
        logger.logArtifact("assertionObject", base64: request.assertionObject_base64, correlationID: flow.correlationID)
        
        do {
            // Enforce sequencing - must be hash_issued
            guard flow.state == .hashIssued, !flow.terminal else {
                await metrics.incrementSequenceViolation()
                if flow.terminal {
                    throw Abort(.conflict, reason: "Flow is in terminal state: \(flow.state.rawValue)")
                }
                throw Abort(.conflict, reason: "Sequence violation: current state '\(flow.state.rawValue)', required 'hash_issued'")
            }
            
            guard flow.expiresAt == nil || Date() < flow.expiresAt! else {
                await metrics.incrementSequenceViolation()
                throw Abort(.gone, reason: "Flow has expired")
            }
            
            // Use stored clientDataHash
            guard let clientDataHash = flow.clientDataHash_base64 else {
                throw Abort(.badRequest, reason: "clientDataHash not available - flow must be in hash_issued state")
            }
            
            let verifyRequest = BackendVerifyRequest(
                keyID_base64: flow.keyID_base64,
                assertionObject_base64: request.assertionObject_base64,
                clientDataHash_base64: clientDataHash,
                verifyRunID: request.verifyRunID ?? flow.verifyRunID
            )
            
            await metrics.incrementBackendRequest(route: "/app-attest/verify")
            let (verifyResponse, rawJSON) = try await backendClient.verify(
                request: verifyRequest,
                correlationID: flow.correlationID,
                flowHandle: flowHandle
            )
            
            logger.logBackendRequest(
                endpoint: "/app-attest/verify",
                correlationID: flow.correlationID,
                flowHandle: flowHandle,
                status: 200
            )
            
            // Update flow state
            let finalFlow: FlowState
            if verifyResponse.verified {
                finalFlow = try FlowMachine.transitionToVerified(flow)
                await metrics.incrementFlowCompleted()
            } else {
                finalFlow = try FlowMachine.transitionToRejected(flow, reason: verifyResponse.reason)
                await metrics.incrementFlowFailed()
            }
            
            await flowStore.update(finalFlow)
            
            logger.logStateTransition(
                flowHandle: flowHandle,
                flowID: flow.flowID,
                correlationID: flow.correlationID,
                from: "hash_issued",
                to: finalFlow.state.rawValue
            )
            
            // IMPORTANT:
            // This service does not interpret backend responses.
            // The response below is returned verbatim.
            // "verified" here means "backend reported verified", not "access allowed".
            return AssertResponse(
                state: finalFlow.state.rawValue,
                backend: rawJSON,
                terminal: true
            )
        } catch let error as FlowError {
            await metrics.incrementSequenceViolation()
            switch error {
            case .sequenceViolation:
                throw Abort(.conflict, reason: error.description)
            case .terminalState:
                throw Abort(.conflict, reason: error.description)
            case .expired:
                throw Abort(.gone, reason: error.description)
            case .notFound:
                throw Abort(.notFound, reason: error.description)
            }
        } catch {
            logger.logBackendError(
                endpoint: "/app-attest/verify",
                correlationID: flow.correlationID,
                flowHandle: flowHandle,
                error: "\(error)"
            )
            throw Abort(.badGateway, reason: "Backend error: \(error)")
        }
    }
    
    // GET /v1/flows/{flowHandle}/status
    app.get("v1", "flows", ":flowHandle", "status") { req async throws -> FlowStatusResponse in
        guard let flowHandle = req.parameters.get("flowHandle") else {
            throw Abort(.badRequest, reason: "Missing flowHandle")
        }
        
        guard let flow = await flowStore.get(flowHandle) else {
            throw Abort(.notFound, reason: "Flow not found")
        }
        
        let formatter = ISO8601DateFormatter()
        return FlowStatusResponse(
            flowHandle: flow.flowHandle,
            flowID: flow.flowID,
            keyID_base64: flow.keyID_base64,
            verifyRunID: flow.verifyRunID,
            state: flow.state.rawValue,
            issuedAt: formatter.string(from: flow.issuedAt),
            expiresAt: flow.expiresAt.map { formatter.string(from: $0) },
            lastBackendStatus: flow.lastBackendStatus,
            terminal: flow.terminal
        )
    }
    
    // GET /health
    app.get("health") { req async throws -> HealthResponse in
        let uptime = Date().timeIntervalSince(startTime)
        let flowCount = await flowStore.flowCount()
        let terminalFlowCount = await flowStore.terminalFlowCount()
        
        return HealthResponse(
            status: "ok",
            uptimeSeconds: uptime,
            flowCount: flowCount,
            terminalFlowCount: terminalFlowCount,
            backendBaseURL: Environment.backendBaseURL,
            buildSha256: Environment.buildSha256
        )
    }
    
    // GET /metrics
    app.get("metrics") { req async throws -> String in
        return await metrics.getPrometheusMetrics()
    }
}

/// Generate opaque flow handle (base64url encoded random bytes).
func generateFlowHandle() -> String {
    // Generate 24 random bytes
    var bytes = [UInt8](repeating: 0, count: 24)
    for i in 0..<bytes.count {
        bytes[i] = UInt8.random(in: 0...255)
    }
    return Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
