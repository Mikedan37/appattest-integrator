#!/bin/bash
set -e

# Development run script for appattest-integrator

# Set default environment variables if not set
export APP_ATTEST_BACKEND_BASE_URL="${APP_ATTEST_BACKEND_BASE_URL:-http://127.0.0.1:8080}"
export APP_ATTEST_INTEGRATOR_PORT="${APP_ATTEST_INTEGRATOR_PORT:-8090}"
export APP_ATTEST_BACKEND_TIMEOUT_MS="${APP_ATTEST_BACKEND_TIMEOUT_MS:-3000}"
export APP_ATTEST_DEBUG_LOG_ARTIFACTS="${APP_ATTEST_DEBUG_LOG_ARTIFACTS:-0}"

echo "Starting appattest-integrator in development mode..."
echo "Backend URL: $APP_ATTEST_BACKEND_BASE_URL"
echo "Port: $APP_ATTEST_INTEGRATOR_PORT"
echo ""

# Build if needed
if [ ! -f ".build/debug/AppAttestIntegrator" ]; then
    echo "Building..."
    swift build
fi

# Run
.build/debug/AppAttestIntegrator
