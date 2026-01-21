#!/bin/bash
set -e

# Install systemd service for appattest-integrator

SERVICE_NAME="appattest-integrator"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
BINARY_PATH="$(pwd)/.build/release/AppAttestIntegrator"
WORK_DIR="$(pwd)"

# Check if binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    echo "Please build the project first: swift build -c release"
    exit 1
fi

# Create systemd service file
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=App Attest Integrator Daemon
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$WORK_DIR
ExecStart=$BINARY_PATH
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Environment variables
Environment="APP_ATTEST_BACKEND_BASE_URL=http://127.0.0.1:8080"
Environment="APP_ATTEST_INTEGRATOR_PORT=8090"
Environment="APP_ATTEST_BACKEND_TIMEOUT_MS=3000"
Environment="APP_ATTEST_DEBUG_LOG_ARTIFACTS=0"

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

echo "Service installed: $SERVICE_FILE"
echo ""
echo "To start the service:"
echo "  sudo systemctl start $SERVICE_NAME"
echo ""
echo "To enable on boot:"
echo "  sudo systemctl enable $SERVICE_NAME"
echo ""
echo "To check status:"
echo "  sudo systemctl status $SERVICE_NAME"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u $SERVICE_NAME -f"
