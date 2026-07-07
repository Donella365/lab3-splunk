#!/bin/bash
# ==============================================================================
# Lab 3 — Splunk SIEM: Splunk Enterprise Install + Config
# ==============================================================================
# Run this ON the Splunk VM itself (SSH in first, then run this script there).
# Installs Splunk Enterprise, starts it, and configures receiving + the
# windows_logs index via the Splunk CLI (instead of clicking through the web UI).
#
# Prerequisite: you've already downloaded the Splunk .deb via the browser-based
# temp-mail registration flow (this part can't be scripted — Splunk requires
# account registration through their site) and uploaded/wget'd it onto this VM.
#
# Usage: sudo bash 02-install-splunk.sh /path/to/splunk-*.deb
# ==============================================================================
set -euo pipefail

DEB_FILE="${1:?Usage: sudo bash 02-install-splunk.sh /path/to/splunk-*.deb}"

if [ ! -f "$DEB_FILE" ]; then
  echo "ERROR: $DEB_FILE not found. Download the current .deb from splunk.com first."
  exit 1
fi

echo "==> Installing Splunk Enterprise from $DEB_FILE..."
dpkg -i "$DEB_FILE"

echo "==> Starting Splunk (accepting license, running as root)..."
# --run-as-root is required on Splunk 9.x+ when starting via sudo — without it,
# Splunk silently fails to start and reports 'splunkd is not running' even
# though the command appears to complete successfully.
/opt/splunk/bin/splunk start --accept-license --answer-yes --run-as-root --no-prompt \
  --seed-passwd 'ChangeMeImmediately123!'

echo "==> Enabling boot-start (Splunk starts automatically on VM reboot)..."
/opt/splunk/bin/splunk enable boot-start --accept-license --answer-yes --no-prompt

echo "==> Configuring Splunk to receive forwarded data on port 9997..."
/opt/splunk/bin/splunk enable listen 9997 -auth admin:'ChangeMeImmediately123!'

echo "==> Creating the windows_logs index..."
/opt/splunk/bin/splunk add index windows_logs -auth admin:'ChangeMeImmediately123!'

echo "==> Verifying Splunk is running..."
/opt/splunk/bin/splunk status

echo ""
echo "==> IMPORTANT: change the seed password immediately —"
echo "    /opt/splunk/bin/splunk edit user admin -password 'YourRealPassword!' -auth admin:'ChangeMeImmediately123!'"
echo ""
echo "==> Splunk Web UI available at: http://<this-VM-public-IP>:8000"
echo "==> Next step: configure the Universal Forwarder on vm-actived (03-configure-forwarder.ps1)"
