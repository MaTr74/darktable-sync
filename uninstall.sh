#!/bin/bash

# Load possible custom paths from install-time .env if exists
if [[ -f ".env" ]]; then
    export $(grep -v '^#' .env | xargs)
fi

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
APPLICATIONS_DIR="${APPLICATIONS_DIR:-$HOME/.local/share/applications}"
SYSTEMD_USER_DIR="${SYSTEMD_USER_DIR:-$HOME/.config/systemd/user}"

# Stop and disable systemd service
echo "🛑 Removing systemd services..."
systemctl --user disable --now darktable-sync.timer >/dev/null 2>&1 || true
systemctl --user daemon-reload

# Remove files
echo "🧹 Cleaning up installed files..."
rm -fv \
  "$BIN_DIR/darktable_sync.sh" \
  "$BIN_DIR/darktable_wrapper.sh" \
  "$APPLICATIONS_DIR/darktable-with-sync.desktop" \
  "$APPLICATIONS_DIR/darktable-sync-only.desktop" \
  "$SYSTEMD_USER_DIR/darktable-sync.service" \
  "$SYSTEMD_USER_DIR/darktable-sync.timer"

echo "✅ Uninstall complete. Config files in ~/.config/darktable remain untouched."
