#!/usr/bin/env bash
# install.sh — Multicast Ring Analyzer installer for Linux
#
# Run directly:
#   bash install.sh
#
# Or one-liner from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/lavabeard/multicast-ring-analyzer/main/install.sh | bash
#
# Flags:
#   --dry-run        show every action without making changes
#   --uninstall      remove the app (keeps user data)
#   --purge          remove the app AND user data
#   --no-deps        skip dependency checks/installs

set -euo pipefail

# ── config ─────────────────────────────────────────────────────────────────────
APP_NAME="Multicast Ring Analyzer"
APP_ID="multicast-ring-analyzer"
REPO="lavabeard/multicast-ring-analyzer"
INSTALL_DIR="$HOME/Applications"
APPIMAGE_PATH="$INSTALL_DIR/$APP_NAME.AppImage"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/$APP_ID.desktop"
USER_DATA="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_NAME"
BACKUP_BASE="$HOME/.local/share/$APP_ID-backups"
STAMP="$(date +%Y%m%d_%H%M%S)"

DRY_RUN=false
UNINSTALL=false
PURGE=false
SKIP_DEPS=false

# ── parse args ─────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --uninstall) UNINSTALL=true ;;
    --purge)     PURGE=true; UNINSTALL=true ;;
    --no-deps)   SKIP_DEPS=true ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--uninstall] [--purge] [--no-deps]"
      echo ""
      echo "  (no flags)   Install or upgrade $APP_NAME"
      echo "  --dry-run    Show what would happen without making changes"
      echo "  --uninstall  Remove the app (keeps your channel names and settings)"
      echo "  --purge      Remove the app and all user data"
      echo "  --no-deps    Skip dependency checks"
      exit 0
      ;;
  esac
done

# ── colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${GREEN}[✔]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
step()    { echo -e "${BOLD}${CYAN}[→]${RESET} $*"; }
error()   { echo -e "${RED}[✘]${RESET} $*" >&2; exit 1; }
dry()     { echo -e "${CYAN}[dry-run]${RESET} $*"; }
run()     { if $DRY_RUN; then dry "$*"; else "$@"; fi; }
run_cmd() { if $DRY_RUN; then dry "$*"; else eval "$*"; fi; }

# ── root check ─────────────────────────────────────────────────────────────────
SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo &>/dev/null; then
    SUDO="sudo"
  fi
fi

# ── detect package manager ─────────────────────────────────────────────────────
detect_pm() {
  if   command -v apt-get &>/dev/null; then echo "apt"
  elif command -v dnf     &>/dev/null; then echo "dnf"
  elif command -v yum     &>/dev/null; then echo "yum"
  elif command -v pacman  &>/dev/null; then echo "pacman"
  elif command -v zypper  &>/dev/null; then echo "zypper"
  else echo "unknown"
  fi
}

pm_install() {
  local pkg="$1"
  local pm
  pm="$(detect_pm)"
  case "$pm" in
    apt)    run $SUDO apt-get install -y "$pkg" ;;
    dnf)    run $SUDO dnf install -y "$pkg" ;;
    yum)    run $SUDO yum install -y "$pkg" ;;
    pacman) run $SUDO pacman -S --noconfirm "$pkg" ;;
    zypper) run $SUDO zypper install -y "$pkg" ;;
    *)      warn "Unknown package manager — install $pkg manually"; return 1 ;;
  esac
}

# ── header ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Multicast Ring Analyzer — Linux Installer${RESET}"
echo    "  ─────────────────────────────────────────────"
$DRY_RUN && warn "Dry-run mode — no changes will be made"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# UNINSTALL
# ══════════════════════════════════════════════════════════════════════════════
if $UNINSTALL; then
  step "Uninstalling $APP_NAME…"

  if [[ -f "$APPIMAGE_PATH" ]]; then
    info "Removing AppImage: $APPIMAGE_PATH"
    run rm -f "$APPIMAGE_PATH"
  else
    warn "AppImage not found at $APPIMAGE_PATH"
  fi

  if [[ -f "$DESKTOP_FILE" ]]; then
    info "Removing desktop entry"
    run rm -f "$DESKTOP_FILE"
    run_cmd "update-desktop-database '$DESKTOP_DIR' 2>/dev/null || true"
  fi

  # deb removal
  if command -v dpkg &>/dev/null && dpkg -l "$APP_ID" 2>/dev/null | grep -q '^ii'; then
    info "Removing deb package"
    run $SUDO apt-get remove -y "$APP_ID" 2>/dev/null || run $SUDO dpkg -r "$APP_ID"
  fi

  if $PURGE && [[ -d "$USER_DATA" ]]; then
    warn "Removing user data: $USER_DATA"
    run rm -rf "$USER_DATA"
  else
    info "User data kept at: $USER_DATA"
  fi

  echo ""
  info "Uninstall complete."
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# DEPENDENCY CHECK
# ══════════════════════════════════════════════════════════════════════════════
if ! $SKIP_DEPS; then
  step "Checking dependencies…"
  echo ""

  # ── curl (needed for download) ──────────────────────────────────────────────
  if command -v curl &>/dev/null; then
    info "curl        $(curl --version | head -1 | awk '{print $2}')"
  else
    warn "curl not found — installing…"
    pm_install curl
  fi

  # ── ffmpeg / ffprobe (required — used to probe streams) ────────────────────
  if command -v ffprobe &>/dev/null; then
    info "ffprobe     $(ffprobe -version 2>&1 | head -1 | awk '{print $3}')"
  else
    warn "ffprobe not found — installing ffmpeg…"
    pm="$(detect_pm)"
    case "$pm" in
      apt)    run $SUDO apt-get update -qq && pm_install ffmpeg ;;
      dnf|yum) pm_install ffmpeg || {
                 warn "ffmpeg not in default repos — trying RPM Fusion"
                 run $SUDO dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" 2>/dev/null || true
                 pm_install ffmpeg
               } ;;
      pacman) pm_install ffmpeg ;;
      *)      warn "Install ffmpeg manually: https://ffmpeg.org/download.html" ;;
    esac
    command -v ffprobe &>/dev/null && info "ffprobe     installed" || warn "ffprobe still not found — stream probing will not work"
  fi

  # ── VLC (required — used for stream playback) ───────────────────────────────
  if command -v vlc &>/dev/null; then
    info "vlc         $(vlc --version 2>/dev/null | head -1 | awk '{print $3}' || echo 'found')"
  else
    warn "VLC not found — installing…"
    pm_install vlc || warn "VLC install failed — install manually from https://www.videolan.org"
    command -v vlc &>/dev/null && info "vlc         installed" || warn "VLC still not found — stream playback will not work"
  fi

  # ── FUSE (required to run AppImage) ────────────────────────────────────────
  if command -v fusermount &>/dev/null || command -v fusermount3 &>/dev/null; then
    info "fuse        found"
  else
    warn "FUSE not found — installing…"
    pm="$(detect_pm)"
    case "$pm" in
      apt)    pm_install fuse || pm_install fuse2 || pm_install libfuse2 ;;
      dnf|yum) pm_install fuse ;;
      pacman) pm_install fuse2 ;;
      *)      warn "Install fuse manually for AppImage support" ;;
    esac
  fi

  echo ""
fi

# ══════════════════════════════════════════════════════════════════════════════
# FETCH LATEST RELEASE
# ══════════════════════════════════════════════════════════════════════════════
step "Fetching latest release from GitHub…"

RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null || echo '{}')"
VERSION="$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
APPIMAGE_URL="$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep '\.AppImage' | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"
DEB_URL="$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep '\.deb' | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"

if [[ -z "$VERSION" ]]; then
  error "Could not fetch release info from GitHub. Check your internet connection or visit: https://github.com/$REPO/releases"
fi

info "Latest version : $VERSION"

# Check currently installed version
CURRENT_VERSION=""
if [[ -f "$APPIMAGE_PATH" ]]; then
  # Try to extract version from filename
  CURRENT_VERSION="$(basename "$APPIMAGE_PATH" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo '')"
fi

if [[ -n "$CURRENT_VERSION" && "$CURRENT_VERSION" == "${VERSION#v}" ]]; then
  info "Already on latest version ($VERSION)"
  echo ""
  read -rp "  Reinstall anyway? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "  Nothing to do."; exit 0; }
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# BACKUP EXISTING INSTALL
# ══════════════════════════════════════════════════════════════════════════════
BACKUP_DIR=""
if [[ -f "$APPIMAGE_PATH" || -d "$USER_DATA" ]]; then
  step "Backing up existing installation…"
  BACKUP_DIR="$BACKUP_BASE/$STAMP"

  if [[ -f "$APPIMAGE_PATH" ]]; then
    info "  App   → $BACKUP_DIR/app/"
    run mkdir -p "$BACKUP_DIR/app"
    run cp "$APPIMAGE_PATH" "$BACKUP_DIR/app/"
  fi

  if [[ -d "$USER_DATA" ]]; then
    info "  Data  → $BACKUP_DIR/userdata/"
    run cp -a "$USER_DATA" "$BACKUP_DIR/userdata/"
  fi

  echo ""
fi

# ══════════════════════════════════════════════════════════════════════════════
# DOWNLOAD + INSTALL
# ══════════════════════════════════════════════════════════════════════════════
step "Installing $APP_NAME $VERSION…"
echo ""

if [[ -n "$APPIMAGE_URL" ]]; then
  FILENAME="$(basename "$APPIMAGE_URL")"
  TMP_FILE="/tmp/$FILENAME"

  info "Downloading AppImage…"
  run curl -fL --progress-bar "$APPIMAGE_URL" -o "$TMP_FILE"

  run mkdir -p "$INSTALL_DIR"

  # Remove old AppImage
  if [[ -f "$APPIMAGE_PATH" ]]; then
    run rm -f "$APPIMAGE_PATH"
  fi

  run cp "$TMP_FILE" "$APPIMAGE_PATH"
  run chmod +x "$APPIMAGE_PATH"
  run rm -f "$TMP_FILE"
  info "AppImage installed → $APPIMAGE_PATH"

elif [[ -n "$DEB_URL" ]] && command -v dpkg &>/dev/null; then
  FILENAME="$(basename "$DEB_URL")"
  TMP_FILE="/tmp/$FILENAME"

  info "Downloading .deb package…"
  run curl -fL --progress-bar "$DEB_URL" -o "$TMP_FILE"

  # Remove old deb install
  dpkg -l "$APP_ID" 2>/dev/null | grep -q '^ii' && run $SUDO dpkg -r "$APP_ID" 2>/dev/null || true

  run $SUDO dpkg -i "$TMP_FILE"
  run $SUDO apt-get install -f -y 2>/dev/null || true
  run rm -f "$TMP_FILE"
  info ".deb installed"

else
  error "No AppImage or .deb found in release $VERSION. Visit: https://github.com/$REPO/releases"
fi

# ── desktop entry ──────────────────────────────────────────────────────────────
if [[ -f "$APPIMAGE_PATH" ]]; then
  run mkdir -p "$DESKTOP_DIR"
  if ! $DRY_RUN; then
    cat > "$DESKTOP_FILE" << DESKTOP
[Desktop Entry]
Name=$APP_NAME
Exec=$APPIMAGE_PATH %U
Icon=$APP_ID
Type=Application
Categories=Network;AudioVideo;
Comment=Discover and probe UDP multicast streams
StartupNotify=true
DESKTOP
  else
    dry "Write $DESKTOP_FILE"
  fi
  run_cmd "update-desktop-database '$DESKTOP_DIR' 2>/dev/null || true"
  info "Desktop entry created"
fi

# ══════════════════════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}  ✔ $APP_NAME $VERSION installed successfully${RESET}"
echo ""
echo "  Launch:  $APPIMAGE_PATH"
echo "  Or find it in your applications menu"
[[ -n "$BACKUP_DIR" ]] && echo "  Backup:  $BACKUP_DIR"
echo ""
