#!/usr/bin/env bash
# Provision or update the isolated sibling Ubuntu 26.04.1 LTS ("resolute")
# systemd-nspawn sandbox container (`hermes-box`) on the Debian 12 host.
#
# Architecture:
#   - Dedicated partition/mount at /var/lib/machines/hermes-box (auto-detected)
#     OR sparse ext4 raw disk image at /var/lib/machines/hermes-box.raw
#   - Unprivileged user namespace isolation (`PrivateUsers=pick`)
#   - Shared LAN/mDNS segment via `MACVLAN=<iface>` (`hermes-box.local`)
#   - Hard cgroup v2 CPU, memory, and PID limits protecting `junixsrv`
#   - Key-only OpenSSH server for user `hermes` (`cwd=/home/hermes/workspace`)

set -euo pipefail

MACHINE="hermes-box"
SUITE="resolute"
IMAGE_SIZE_GIB="32"
STORAGE_MODE="auto"
MACVLAN_IFACE=""
MIRROR=""
AUTHORIZED_KEY_ARG=""
REBUILD=0

JUNIXSRV_NSPAWN="/etc/systemd/nspawn/junixsrv.nspawn"
DEFAULT_JUNIXSRV_PUBKEY="/var/lib/machines/junixsrv/var/lib/hermes/.ssh/id_hermes_box.pub"

usage() {
  cat <<'EOF'
Usage: sudo bash scripts/provision-hermes-box.sh [options]

Storage:
  If /var/lib/machines/hermes-box is a mounted partition (or --directory is
  passed), bootstraps directly into /var/lib/machines/hermes-box. Otherwise
  creates a sparse ext4 loopback image at /var/lib/machines/hermes-box.raw.

Options:
  --directory               Use /var/lib/machines/hermes-box directory root
  --macvlan <iface>         Host NIC for MACVLAN= (default: read from junixsrv.nspawn)
  --size <GiB>              Sparse raw ext4 image size in GiB (default: 32)
  --suite <codename>        Ubuntu release suite (default: resolute / 26.04.1 LTS)
  --mirror <url>            Ubuntu archive mirror URL (default: auto by arch)
  --authorized-key <value>  SSH public key string or path to .pub file
  --rebuild                 Stop and recreate /var/lib/machines/hermes-box(.raw)
  -h, --help                Show this help text
EOF
}

log() {
  printf '==> [%s] %s\n' "$MACHINE" "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --directory)
      STORAGE_MODE="directory"
      shift
      ;;
    --macvlan)
      [[ $# -ge 2 ]] || die "--macvlan requires an interface name"
      MACVLAN_IFACE="$2"
      shift 2
      ;;
    --size)
      [[ $# -ge 2 ]] || die "--size requires an integer GiB size"
      IMAGE_SIZE_GIB="$2"
      shift 2
      ;;
    --suite)
      [[ $# -ge 2 ]] || die "--suite requires a suite codename"
      SUITE="$2"
      shift 2
      ;;
    --mirror)
      [[ $# -ge 2 ]] || die "--mirror requires a URL"
      MIRROR="$2"
      shift 2
      ;;
    --authorized-key)
      [[ $# -ge 2 ]] || die "--authorized-key requires a key string or file path"
      AUTHORIZED_KEY_ARG="$2"
      shift 2
      ;;
    --rebuild)
      REBUILD=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (pass --help for usage)"
      ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || die "run as root on the Debian 12 systemd-nspawn host"
[[ "${IMAGE_SIZE_GIB}" =~ ^[1-9][0-9]*$ ]] || die "--size must be a positive integer (>= 1)"

if [[ -z "${MACVLAN_IFACE}" && -f "${JUNIXSRV_NSPAWN}" ]]; then
  MACVLAN_IFACE="$(awk -F= '/^[[:space:]]*MACVLAN[[:space:]]*=/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "${JUNIXSRV_NSPAWN}")"
fi
[[ -n "${MACVLAN_IFACE}" ]] || die "could not auto-detect MACVLAN=; pass --macvlan <iface>"

ARCH="$(dpkg --print-architecture)"
if [[ -z "${MIRROR}" ]]; then
  case "${ARCH}" in
    amd64 | i386)
      MIRROR="http://archive.ubuntu.com/ubuntu"
      ;;
    arm64 | armhf | riscv64 | ppc64el | s390x)
      MIRROR="http://ports.ubuntu.com/ubuntu-ports"
      ;;
    *)
      die "unsupported architecture '${ARCH}'; pass --mirror explicitly"
      ;;
  esac
fi

PUBKEY_LINE=""
if [[ -n "${AUTHORIZED_KEY_ARG}" ]]; then
  if [[ -f "${AUTHORIZED_KEY_ARG}" ]]; then
    PUBKEY_LINE="$(tr -d '\r' < "${AUTHORIZED_KEY_ARG}" | head -n 1)"
  else
    PUBKEY_LINE="${AUTHORIZED_KEY_ARG}"
  fi
elif [[ -f "${DEFAULT_JUNIXSRV_PUBKEY}" ]]; then
  PUBKEY_LINE="$(tr -d '\r' < "${DEFAULT_JUNIXSRV_PUBKEY}" | head -n 1)"
fi

log "Installing host prerequisites on Debian..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  debootstrap \
  e2fsprogs \
  gnupg \
  systemd-container

UBUNTU_KEYRING="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
UBUNTU_ARCHIVE_KEY_FPR="F6ECB3762474EDA9D21B7022871920D1991BC93C"

DIR_PATH="/var/lib/machines/${MACHINE}"
IMAGE_PATH="/var/lib/machines/${MACHINE}.raw"
MNT_DIR=""
TMP_MNT_DIR=""
LOOP_DEV=""
GPG_TMP=""

cleanup() {
  set +e
  if [[ -n "${GPG_TMP}" && -d "${GPG_TMP}" ]]; then
    rm -rf "${GPG_TMP}"
  fi
  if [[ -n "${MNT_DIR}" && -d "${MNT_DIR}" ]]; then
    for sub in dev/pts dev proc sys; do
      if mountpoint -q "${MNT_DIR}/${sub}"; then
        umount -lf "${MNT_DIR}/${sub}"
      fi
    done
  fi
  if [[ -n "${TMP_MNT_DIR}" && -d "${TMP_MNT_DIR}" ]]; then
    if mountpoint -q "${TMP_MNT_DIR}"; then
      umount "${TMP_MNT_DIR}"
    fi
    rmdir "${TMP_MNT_DIR}" 2>/dev/null || true
  fi
  if [[ -n "${LOOP_DEV}" ]]; then
    losetup -d "${LOOP_DEV}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

ensure_ubuntu_keyring() {
  if [[ -s "${UBUNTU_KEYRING}" ]] \
    && gpg --batch --with-colons --show-keys "${UBUNTU_KEYRING}" 2>/dev/null \
      | grep -Eq "^fpr:+${UBUNTU_ARCHIVE_KEY_FPR}:"; then
    return 0
  fi

  log "Fetching and verifying Ubuntu Archive signing key (${UBUNTU_ARCHIVE_KEY_FPR})..."
  GPG_TMP="$(mktemp -d)"
  chmod 0700 "${GPG_TMP}"
  curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${UBUNTU_ARCHIVE_KEY_FPR}" \
    | gpg --homedir "${GPG_TMP}" --batch --quiet --import
  if ! gpg --homedir "${GPG_TMP}" --batch --with-colons --fingerprint "${UBUNTU_ARCHIVE_KEY_FPR}" \
    | grep -Eq "^fpr:+${UBUNTU_ARCHIVE_KEY_FPR}:"; then
    die "fingerprint mismatch while verifying Ubuntu Archive signing key"
  fi
  install -d -m 0755 /usr/share/keyrings
  gpg --homedir "${GPG_TMP}" --batch --export "${UBUNTU_ARCHIVE_KEY_FPR}" > "${UBUNTU_KEYRING}.tmp"
  chmod 0644 "${UBUNTU_KEYRING}.tmp"
  mv -f "${UBUNTU_KEYRING}.tmp" "${UBUNTU_KEYRING}"
  rm -rf "${GPG_TMP}"
  GPG_TMP=""
}

ensure_ubuntu_keyring

install -d -m 0755 /var/lib/machines /etc/systemd/nspawn

USE_DIRECTORY=0
if [[ "${STORAGE_MODE}" == "directory" ]]; then
  USE_DIRECTORY=1
elif [[ -d "${DIR_PATH}" ]] && { mountpoint -q "${DIR_PATH}" || [[ ! -f "${IMAGE_PATH}" && -e "${DIR_PATH}/etc/os-release" ]]; }; then
  USE_DIRECTORY=1
fi

if [[ "${USE_DIRECTORY}" -eq 1 && -f "${IMAGE_PATH}" ]]; then
  die "both ${DIR_PATH} and ${IMAGE_PATH} exist; remove one so systemd-nspawn has an unambiguous root"
fi
if [[ "${USE_DIRECTORY}" -eq 0 && -d "${DIR_PATH}" && ! -f "${IMAGE_PATH}" ]]; then
  die "${DIR_PATH} exists as an unmounted directory; mount your partition there or pass --directory"
fi

if machinectl status "${MACHINE}" >/dev/null 2>&1; then
  log "Stopping running ${MACHINE} container..."
  machinectl poweroff "${MACHINE}" 2>/dev/null || true
  for _ in {1..30}; do
    machinectl status "${MACHINE}" >/dev/null 2>&1 || break
    sleep 1
  done
  machinectl terminate "${MACHINE}" 2>/dev/null || true
fi

NEED_BOOTSTRAP=0
if [[ "${USE_DIRECTORY}" -eq 1 ]]; then
  install -d -m 0755 "${DIR_PATH}"
  MNT_DIR="${DIR_PATH}"
  STORAGE_DESC="${DIR_PATH}"
  if [[ "${REBUILD}" -eq 1 ]]; then
    log "Clearing ${DIR_PATH} for rebuild..."
    find "${DIR_PATH}" -mindepth 1 -maxdepth 1 ! -name 'lost+found' -exec rm -rf {} +
    NEED_BOOTSTRAP=1
  elif [[ ! -e "${DIR_PATH}/etc/os-release" ]]; then
    find "${DIR_PATH}" -mindepth 1 -maxdepth 1 ! -name 'lost+found' -exec rm -rf {} +
    NEED_BOOTSTRAP=1
  fi
else
  STORAGE_DESC="${IMAGE_PATH}"
  if [[ "${REBUILD}" -eq 1 && -f "${IMAGE_PATH}" ]]; then
    rm -f "${IMAGE_PATH}"
  fi
  if [[ ! -f "${IMAGE_PATH}" ]]; then
    NEED_BOOTSTRAP=1
    log "Creating ${IMAGE_SIZE_GIB} GiB sparse ext4 image at ${IMAGE_PATH}..."
    truncate -s "${IMAGE_SIZE_GIB}G" "${IMAGE_PATH}"
    chmod 0600 "${IMAGE_PATH}"
    mkfs.ext4 -q -F -L "${MACHINE}" "${IMAGE_PATH}"
  fi
  TMP_MNT_DIR="$(mktemp -d "/run/${MACHINE}-mnt.XXXXXX")"
  MNT_DIR="${TMP_MNT_DIR}"
  LOOP_DEV="$(losetup --find --show "${IMAGE_PATH}")"
  mount "${LOOP_DEV}" "${TMP_MNT_DIR}"
  if [[ "${NEED_BOOTSTRAP}" -eq 0 && ! -e "${MNT_DIR}/etc/os-release" ]]; then
    log "Existing image is incomplete (missing /etc/os-release); re-bootstrapping..."
    find "${MNT_DIR}" -mindepth 1 -maxdepth 1 ! -name 'lost+found' -exec rm -rf {} +
    NEED_BOOTSTRAP=1
  fi
fi

if [[ "${NEED_BOOTSTRAP}" -eq 0 && "$(stat -c '%u' "${MNT_DIR}/etc")" != "0" ]]; then
  die "${STORAGE_DESC} has UID-shifted ownership (no kernel idmapped mount support); re-run with --rebuild"
fi

if [[ "${NEED_BOOTSTRAP}" -eq 1 ]]; then
  DEBOOTSTRAP_SCRIPT="/usr/share/debootstrap/scripts/${SUITE}"
  if [[ ! -e "${DEBOOTSTRAP_SCRIPT}" ]]; then
    DEBOOTSTRAP_SCRIPT="/usr/share/debootstrap/scripts/gutsy"
  fi

  log "Bootstrapping Ubuntu '${SUITE}' (${ARCH}) from ${MIRROR}..."
  debootstrap \
    --arch="${ARCH}" \
    --keyring="${UBUNTU_KEYRING}" \
    --include=systemd,systemd-sysv,dbus,ca-certificates,ubuntu-keyring \
    "${SUITE}" \
    "${MNT_DIR}" \
    "${MIRROR}" \
    "${DEBOOTSTRAP_SCRIPT}"
fi

mount --bind /dev "${MNT_DIR}/dev"
mount --bind /dev/pts "${MNT_DIR}/dev/pts"
mount -t proc proc "${MNT_DIR}/proc"
mount -t sysfs sysfs "${MNT_DIR}/sys"

printf '%s\n' "${MACHINE}" > "${MNT_DIR}/etc/hostname"
cat > "${MNT_DIR}/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 ${MACHINE} ${MACHINE}.local
::1       localhost ip6-localhost ip6-loopback
EOF

if [[ "${ARCH}" == "amd64" || "${ARCH}" == "i386" ]]; then
  SEC_MIRROR="http://security.ubuntu.com/ubuntu"
else
  SEC_MIRROR="${MIRROR}"
fi

cat > "${MNT_DIR}/etc/apt/sources.list" <<EOF
deb ${MIRROR} ${SUITE} main restricted universe multiverse
deb ${MIRROR} ${SUITE}-updates main restricted universe multiverse
deb ${MIRROR} ${SUITE}-backports main restricted universe multiverse
deb ${SEC_MIRROR} ${SUITE}-security main restricted universe multiverse
EOF

install -d -m 0755 "${MNT_DIR}/etc/systemd/network"
cat > "${MNT_DIR}/etc/systemd/network/80-container-mv.network" <<'EOF'
[Match]
Name=mv-*

[Network]
DHCP=yes
IPv6AcceptRA=yes
# avahi-daemon owns UDP 5353 mDNS; keep systemd-resolved off 5353.
MulticastDNS=no

[DHCPv4]
UseDomains=yes
EOF

install -d -m 0755 "${MNT_DIR}/etc/systemd/resolved.conf.d"
cat > "${MNT_DIR}/etc/systemd/resolved.conf.d/10-no-mdns.conf" <<'EOF'
[Resolve]
MulticastDNS=no
EOF

log "Configuring packages, SSH, Avahi mDNS, and user 'hermes' inside ${MACHINE}..."
rm -f "${MNT_DIR}/etc/resolv.conf"
if [[ -s /run/systemd/resolve/resolv.conf ]] && grep -qE '^nameserver[[:space:]]+127\.0\.0\.53' /etc/resolv.conf 2>/dev/null; then
  cp /run/systemd/resolve/resolv.conf "${MNT_DIR}/etc/resolv.conf"
else
  cp /etc/resolv.conf "${MNT_DIR}/etc/resolv.conf"
fi
if ! awk '/^nameserver[[:space:]]+/ && $2 !~ /^(127\.|::1$)/ { found=1 } END { exit !found }' "${MNT_DIR}/etc/resolv.conf" 2>/dev/null; then
  printf 'nameserver 9.9.9.9\nnameserver 149.112.112.112\n' > "${MNT_DIR}/etc/resolv.conf"
fi

chroot "${MNT_DIR}" /usr/bin/env DEBIAN_FRONTEND=noninteractive /bin/bash -euo pipefail <<'CHROOT_EOF'
apt-get update -qq
apt-get install -y --no-install-recommends \
  avahi-daemon \
  bubblewrap \
  build-essential \
  ca-certificates \
  curl \
  dbus \
  fd-find \
  git \
  jq \
  less \
  libnss-mdns \
  locales \
  nodejs \
  npm \
  openssh-server \
  pkg-config \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  ripgrep \
  sqlite3 \
  sudo \
  systemd-resolved \
  tzdata \
  unzip \
  wget \
  zip \
  zstd

if ! command -v uv >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends uv \
    || python3 -m pip install --break-system-packages --no-cache-dir -q uv
fi

locale-gen en_US.UTF-8 >/dev/null

if ! id -u hermes >/dev/null 2>&1; then
  useradd -m -s /bin/bash -u 1000 -G sudo hermes
fi

install -d -m 0755 -o hermes -g hermes /home/hermes/workspace
install -d -m 0700 -o hermes -g hermes /home/hermes/.ssh
touch /home/hermes/.ssh/authorized_keys
chown hermes:hermes /home/hermes/.ssh/authorized_keys
chmod 0600 /home/hermes/.ssh/authorized_keys

cat > /etc/sudoers.d/hermes <<'SUDO_EOF'
hermes ALL=(ALL) NOPASSWD: ALL
SUDO_EOF
chmod 0440 /etc/sudoers.d/hermes

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-hermes-box.conf <<'SSHD_EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers hermes
UseDNS no
SSHD_EOF

ssh-keygen -A >/dev/null

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
systemctl enable avahi-daemon.service
if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
  systemctl enable ssh.service
elif systemctl list-unit-files sshd.service >/dev/null 2>&1; then
  systemctl enable sshd.service
fi
apt-get clean
CHROOT_EOF

rm -f "${MNT_DIR}/etc/resolv.conf"
ln -sf ../run/systemd/resolve/stub-resolv.conf "${MNT_DIR}/etc/resolv.conf"

if [[ -n "${PUBKEY_LINE}" ]]; then
  AUTH_KEYS="${MNT_DIR}/home/hermes/.ssh/authorized_keys"
  if ! grep -qxF "${PUBKEY_LINE}" "${AUTH_KEYS}"; then
    printf '%s\n' "${PUBKEY_LINE}" >> "${AUTH_KEYS}"
  fi
  chroot "${MNT_DIR}" chown hermes:hermes /home/hermes/.ssh/authorized_keys
  chmod 0600 "${AUTH_KEYS}"
  log "Installed Hermes SSH public key into /home/hermes/.ssh/authorized_keys."
else
  log "Note: id_hermes_box.pub not found yet; re-run with --authorized-key after junixsrv starts hermes-agent."
fi

JUNIXSRV_SSH_DIR="/var/lib/machines/junixsrv/var/lib/hermes/.ssh"
HOST_ED25519_PUB="${MNT_DIR}/etc/ssh/ssh_host_ed25519_key.pub"
if [[ -d "${JUNIXSRV_SSH_DIR}" && -s "${HOST_ED25519_PUB}" ]]; then
  KNOWN_HOSTS="${JUNIXSRV_SSH_DIR}/known_hosts"
  SSH_OWNER="$(stat -c '%u:%g' "${JUNIXSRV_SSH_DIR}")"
  HOST_KEY_FIELDS="$(awk '{print $1, $2}' "${HOST_ED25519_PUB}")"
  if [[ -f "${KNOWN_HOSTS}" ]]; then
    grep -vE "^(${MACHINE}\\.local|${MACHINE})([ ,]|$)" "${KNOWN_HOSTS}" > "${KNOWN_HOSTS}.tmp" || true
    mv -f "${KNOWN_HOSTS}.tmp" "${KNOWN_HOSTS}"
  fi
  printf '%s.local,%s %s\n' "${MACHINE}" "${MACHINE}" "${HOST_KEY_FIELDS}" >> "${KNOWN_HOSTS}"
  chown "${SSH_OWNER}" "${KNOWN_HOSTS}"
  chmod 0600 "${KNOWN_HOSTS}"
  log "Pinned ${MACHINE}.local SSH host key into junixsrv known_hosts."
fi

sync
for sub in dev/pts dev proc sys; do
  umount -lf "${MNT_DIR}/${sub}"
done
MNT_DIR=""
if [[ -n "${TMP_MNT_DIR}" ]]; then
  umount "${TMP_MNT_DIR}"
  rmdir "${TMP_MNT_DIR}"
  TMP_MNT_DIR=""
fi
if [[ -n "${LOOP_DEV}" ]]; then
  losetup -d "${LOOP_DEV}"
  LOOP_DEV=""
fi

cat > "/etc/systemd/nspawn/${MACHINE}.nspawn" <<EOF
[Exec]
Boot=yes
Hostname=${MACHINE}
PrivateUsers=pick
Capability=CAP_NET_BIND_SERVICE

[Files]
PrivateUsersOwnership=auto

[Network]
MACVLAN=${MACVLAN_IFACE}
EOF
chmod 0644 "/etc/systemd/nspawn/${MACHINE}.nspawn"

OVERRIDE_DIR="/etc/systemd/system/systemd-nspawn@${MACHINE}.service.d"
install -d -m 0755 "${OVERRIDE_DIR}"
{
  if [[ "${USE_DIRECTORY}" -eq 1 ]] && mountpoint -q "${DIR_PATH}"; then
    printf '[Unit]\nRequiresMountsFor=%s\n\n' "${DIR_PATH}"
  fi
  cat <<'EOF'
[Service]
CPUQuota=200%
MemoryHigh=4G
MemoryMax=6G
TasksMax=2048
EOF
} > "${OVERRIDE_DIR}/override.conf"

systemctl daemon-reload
systemctl enable --now machines.target
machinectl enable "${MACHINE}"
machinectl start "${MACHINE}"

log "Container '${MACHINE}' started on MACVLAN=${MACVLAN_IFACE} (Ubuntu '${SUITE}')."
log "Verify from junixsrv: sudo -Hu hermes ssh -i /var/lib/hermes/.ssh/id_hermes_box hermes@hermes-box.local uname -a"
