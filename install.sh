#!/bin/bash

set -e

### 🔧 Default Configuration (can be overridden by .env file)
NAS_USER="${NAS_USER:-$USER}"           # Default: current user
NAS_SSH_PORT="${NAS_SSH_PORT:-22}"      # Default: standard SSH port
NAS_IP="${NAS_IP:-192.168.1.100}"       # Default: common local network
NAS_DB_DIR="${NAS_DB_DIR:-/volume1/Darktable/darktable_db}"
NAS_PHOTO_DIR="${NAS_PHOTO_DIR:-/volume1/Darktable/photo_library}"
LOCAL_PHOTO_DIR="${PHOTO_DIR:-$HOME/Pictures/raw}"
LOCAL_DARKTABLE_DB_DIR="${DARKTABLE_DB_DIR:-$HOME/.config/darktable}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
APPLICATIONS_DIR="$HOME/.local/share/applications"
SYNC_SCRIPT="$BIN_DIR/darktable_sync.sh"
WRAPPER_SCRIPT="$BIN_DIR/darktable_wrapper.sh"
DESKTOP_SHORTCUT="$APPLICATIONS_DIR/darktable-with-sync.desktop"
SYNC_ONLY_SHORTCUT="$APPLICATIONS_DIR/darktable-sync-only.desktop"


### 📁 Prepare folders
mkdir -p "$BIN_DIR"
mkdir -p "$HOME/.config/systemd/user"

### 🔄 Load .env if present (overrides defaults)
ENV_FILE=".env"
if [[ -f "$ENV_FILE" ]]; then
    echo "📥 Loading configuration from .env file..."
    set -a  # automatically export all variables
    source "$ENV_FILE"
    set +a
fi

### 📝 Show effective configuration
echo "Using configuration:"
echo "NAS_USER:        $NAS_USER"
echo "NAS_IP:          $NAS_IP"
echo "NAS_SSH_PORT:    $NAS_SSH_PORT"
echo "NAS_DB_DIR:      $NAS_DB_DIR"
echo "NAS_PHOTO_DIR:   $NAS_PHOTO_DIR"
echo "PHOTO_DIR:       $LOCAL_PHOTO_DIR"
echo "DARKTABLE_DB_DIR:$LOCAL_DARKTABLE_DB_DIR"
echo "BIN_DIR:         $BIN_DIR"

### 🔍 Check dependencies
echo "🔍 Checking requirements..."

REQUIRED_CMDS=("rsync" "notify-send" "ping" "darktable" "systemctl" "xdg-user-dir")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Error: '$cmd' is not installed."
        echo "👉 You can install it with: sudo apt install $cmd"
        exit 1
    fi
done

# Check folder presence
if [ ! -d "$LOCAL_PHOTO_DIR" ]; then
    echo "❌ Local photo folder does not exist: $LOCAL_PHOTO_DIR"
    echo "👉 Please create it using: mkdir -p \"$LOCAL_PHOTO_DIR\""
    exit 1
fi

if [ ! -d "$LOCAL_DARKTABLE_DB_DIR" ]; then
    echo "❌ Darktable database path does not exist: $LOCAL_DARKTABLE_DB_DIR"
    echo "👉 Start Darktable once or create the directory manually."
    exit 1
fi

# Check if NAS is reachable
if ping -c 1 "$NAS_IP" &>/dev/null; then
    echo "✅ NAS is reachable: $NAS_IP"

    if ! ssh -p "$NAS_SSH_PORT" "$NAS_USER@$NAS_IP" "[ -d '$NAS_DB_DIR' ]"; then
        echo "❌ Remote directory missing on NAS: $NAS_DB_DIR"
        echo "👉 Please create it or adjust the path."
        exit 1
    fi

    if ! ssh -p "$NAS_SSH_PORT" "$NAS_USER@$NAS_IP" "[ -d '$NAS_PHOTO_DIR' ]"; then
        echo "❌ Remote directory missing on NAS: $NAS_PHOTO_DIR"
        echo "👉 Please create it or adjust the path."
        exit 1
    fi
else
    echo "⚠️ NAS not reachable: $NAS_IP"
    echo "➡️ Sync will fail until NAS is online."
fi

### ✅ Create sync script
cat > "$SYNC_SCRIPT" <<EOF
#!/bin/bash

log() {
    echo "\$1"
}

count_synced_files() {
    LOG="\$1"
    DIRECTION="\$2"

    case "\$DIRECTION" in
        "up")
            COUNT=\$(grep -E '^(<f|cd)' "\$LOG" | wc -l)
            ;;
        "down")
            COUNT=\$(grep -E '^(>f|cd)' "\$LOG" | wc -l)
            ;;
        *)
            COUNT=0
            ;;
    esac

    echo "\$COUNT"
}

SHOW_NOTIFY_START_STOP=false
if [[ "\$1" == "--with-notify-start-stop" ]]; then
  SHOW_NOTIFY_START_STOP=true
fi

if ping -c 1 $NAS_IP &>/dev/null; then
    export DISPLAY=:0
    SYNC_LOG=\$(mktemp)
    log "🔃 NAS is reachable – starting sync..."
    log "Log file: \$SYNC_LOG"

    if [ "\$SHOW_NOTIFY_START_STOP" = true ]; then
        notify-send "Darktable Sync" "🔄 Sync started..." -t 3000
    fi

    log "⬆️ Uploading Darktable DB to NAS..."
    UPLOAD_LOG1=\$(mktemp)
    rsync -avh --itemize-changes -e "ssh -p $NAS_SSH_PORT" "$LOCAL_DARKTABLE_DB_DIR/" "$NAS_USER@$NAS_IP:$NAS_DB_DIR/" 2>&1 | tee -a "\$SYNC_LOG" "\$UPLOAD_LOG1"
    SENT1=\$(count_synced_files "\$UPLOAD_LOG1" "up")
    rm "\$UPLOAD_LOG1"

    log "⬆️ Uploading photos to NAS..."
    UPLOAD_LOG2=\$(mktemp)
    rsync -avh --itemize-changes -e "ssh -p $NAS_SSH_PORT" "$LOCAL_PHOTO_DIR/" "$NAS_USER@$NAS_IP:$NAS_PHOTO_DIR/" 2>&1 | tee -a "\$SYNC_LOG" "\$UPLOAD_LOG2"
    SENT2=\$(count_synced_files "\$UPLOAD_LOG2" "up")
    rm "\$UPLOAD_LOG2"

    log "⬇️ Downloading DB back from NAS..."
    DOWNLOAD_LOG1=\$(mktemp)
    rsync -avh --itemize-changes -e "ssh -p $NAS_SSH_PORT" "$NAS_USER@$NAS_IP:$NAS_DB_DIR/" "$LOCAL_DARKTABLE_DB_DIR/" 2>&1 | tee -a "\$SYNC_LOG" "\$DOWNLOAD_LOG1"
    RECEIVED1=\$(count_synced_files "\$DOWNLOAD_LOG1" "down")
    rm "\$DOWNLOAD_LOG1"

    log "⬇️ Downloading photos from NAS..."
    DOWNLOAD_LOG2=\$(mktemp)
    rsync -avh --itemize-changes -e "ssh -p $NAS_SSH_PORT" "$NAS_USER@$NAS_IP:$NAS_PHOTO_DIR/" "$LOCAL_PHOTO_DIR/" 2>&1 | tee -a "\$SYNC_LOG" "\$DOWNLOAD_LOG2"
    RECEIVED2=\$(count_synced_files "\$DOWNLOAD_LOG2" "down")
    rm "\$DOWNLOAD_LOG2"

    if [ "\$SHOW_NOTIFY_START_STOP" = true ]; then
        notify-send "Darktable Sync" "✅ Sync finished." -t 3000
    fi

    TOTAL_SENT=\$((SENT1 + SENT2))
    TOTAL_RECEIVED=\$((RECEIVED1 + RECEIVED2))

    if [ "\$TOTAL_SENT" -gt 0 ] || [ "\$TOTAL_RECEIVED" -gt 0 ]; then
        log "✅ Uploaded:    \$TOTAL_SENT files"
        log "✅ Downloaded:  \$TOTAL_RECEIVED files"
        notify-send "Darktable Sync" "⬆️ \$TOTAL_SENT uploaded | ⬇️ \$TOTAL_RECEIVED downloaded" -t 10000
    else
        log "ℹ️ No changes detected."
    fi

    rm -f "\$SYNC_LOG"
else
    log "❌ NAS not reachable – skipping sync."
fi
EOF

chmod +x "$SYNC_SCRIPT"

### ✅ Create wrapper script with sync + notify
cat > "$WRAPPER_SCRIPT" <<EOF
#!/bin/bash

log() {
    echo "\$1"
}

log "🔄 Sync starting before Darktable..."
"$SYNC_SCRIPT" --with-notify-start-stop

log "🚀 Launching Darktable..."
darktable
log "🛑 Darktable closed."

log "🔄 Sync starting after Darktable..."
"$SYNC_SCRIPT" --with-notify-start-stop
log "Darktable Sync" "✅ Final sync completed." -t 3000
EOF

chmod +x "$WRAPPER_SCRIPT"


### ✅ Create systemd service and timer
cat > "$HOME/.config/systemd/user/darktable-sync.service" <<EOF
[Unit]
Description=Darktable Sync

[Service]
Type=oneshot
ExecStart=$SYNC_SCRIPT
EOF

cat > "$HOME/.config/systemd/user/darktable-sync.timer" <<EOF
[Unit]
Description=Run Darktable sync every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=darktable-sync.service

[Install]
WantedBy=default.target
EOF

### ✅ Create desktop shortcut
cat > "$DESKTOP_SHORTCUT" <<EOF
[Desktop Entry]
Name=Darktable with Sync
Exec=$WRAPPER_SCRIPT 
Icon=darktable
Type=Application
Terminal=false
Categories=Graphics;
StartupNotify=true
Keywords=Darktable;Photo;Sync;NAS;Rsync;
EOF

chmod +x "$DESKTOP_SHORTCUT"

### ✅ Create additional desktop shortcut (sync only)
cat > "$SYNC_ONLY_SHORTCUT" <<EOF
[Desktop Entry]
Name=Darktable Sync Only
Exec=$SYNC_SCRIPT --with-notify-start-stop
Icon=darktable
Type=Application
Terminal=false
Categories=Utility;
StartupNotify=true
Keywords=Darktable;Photo;Sync;NAS;Schedule;
EOF

chmod +x "$SYNC_ONLY_SHORTCUT"


### ▶️ Enable systemd timer
systemctl --user daemon-reexec
systemctl --user enable --now darktable-sync.timer

### ✅ Summary
echo ""
echo "✅ Setup complete."
echo ""
echo "🖱 You can start Darktable via 'Darktable with Sync' in your application menu."
echo "🕒 Sync will run every 5 minutes automatically when the NAS is online."
