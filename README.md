# Darktable Sync 🔄

Auto-sync your Darktable database and photos between different computers with a server as intermediate. Keeps local and remote files in sync using rsync over SSH. The wrapper script synchronizes files before launching Darktable and after it closes. The scheduled background synchronization ensures continuous and reliable data exchange — even if the wrapper script is not used.

Since only file synchronization is performed, only one Darktable instance should run at a time.

The installation is currently written and tested on (K)Ubuntu 25.04 only.

## Features ✨
- 🔄 Bidirectional sync between local machines and a server 
- ⏲️ Automatic sync every 5 minutes via systemd timer
- 🖱️ Desktop shortcuts for starting Darktable with sync and sync only
- 📊 Desktop notifications

## Requirements 📋
- Bash 4+
- rsync
- SSH key-based auth to NAS
- systemd (for automatic sync)

## Installation 💻
```bash
git clone https://github.com/MaTr74/darktable-sync.git
cd darktable-sync
cp .env.example .env
nano .env  # Edit with your values
chmod +x install.sh uninstall.sh
./install.sh
```

## Usage 🚀
- Start via desktop shortcut: "Darktable with Sync"
- Manual sync: Start via desktop shortcut: "Darktable Sync Only"

## Uninstall 🧹
```bash
./uninstall.sh
```

## License 📄
MIT License - see [LICENSE](LICENSE)
