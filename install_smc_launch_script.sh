#!/bin/bash
set -e

PLIST_PATH="/Library/LaunchDaemons/com.smc_fan_util.plist"
MAX_RPM="${1:-2500}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXECUTABLE="${SCRIPT_DIR}/build/smc_fan_util"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo ./install_smc_launch_script.sh"
    exit 1
fi

# Check if executable exists
if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: $EXECUTABLE not found. Run 'make' first."
    exit 1
fi

# Unload existing daemon if present
if launchctl list | grep -q "com.smc_fan_util"; then
    echo "Unloading existing daemon..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

# Create plist file
echo "Creating $PLIST_PATH..."
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.smc_fan_util</string>
    <key>ProgramArguments</key>
    <array>
        <string>${EXECUTABLE}</string>
        <string>--capped-auto</string>
        <string>${MAX_RPM}</string>
        <string>--no-daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardErrorPath</key>
    <string>/var/log/smc_fan_util.log</string>
</dict>
</plist>
EOF

# Set permissions
echo "Setting permissions..."
chown root:wheel "$PLIST_PATH"
chmod 644 "$PLIST_PATH"

# Load daemon
echo "Loading daemon..."
launchctl load "$PLIST_PATH"

echo "Done! smc_fan_util will now run at startup (capped at ${MAX_RPM} rpm)."
echo ""
echo "Management commands:"
echo "  Start now:  sudo launchctl start com.smc_fan_util"
echo "  Stop:       sudo launchctl stop com.smc_fan_util"
echo "  Uninstall:  sudo launchctl unload $PLIST_PATH && sudo rm $PLIST_PATH && sudo ${EXECUTABLE} -a"
echo "  Log:        /var/log/smc_fan_util.log  (also: log show --predicate 'process == \"smc_fan_util\"')"
