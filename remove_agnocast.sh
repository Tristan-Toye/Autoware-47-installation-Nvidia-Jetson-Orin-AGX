#!/usr/bin/env bash
set -euo pipefail

echo "[*] Showing current state…"
dkms status | grep -i agnocast || echo "no agnocast dkms entries"
dpkg -l | grep -E '^ii\s+agnocast-' || echo "no agnocast packages"
test ! -f /etc/modules-load.d/agnocast.conf && echo "no autoload file" || true

echo "[*] Disable autoload (if it was enabled)"
sudo rm -f /etc/modules-load.d/agnocast.conf || true

echo "[*] Try to unload if currently loaded (ignore failure)"
if lsmod | grep -q '^agnocast'; then
  sudo modprobe -r agnocast || true
fi

echo "[*] Remove ANY DKMS entries for agnocast (all versions)"
while read -r VER; do
  [[ -n "$VER" ]] || continue
  sudo dkms remove -m agnocast -v "$VER" --all || true
done < <(dkms status 2>/dev/null | awk -F, '/agnocast/ {gsub(/ /,"",$2); print $2}')

sudo rm -rf /var/lib/dkms/agnocast /usr/src/agnocast-* || true

echo "[*] Purge the packages (heaphook + kmod, any version)"
sudo apt-get purge -y 'agnocast-kmod*' 'agnocast-heaphook*' || true

echo "[*] Remove the PPA (so apt can’t even see those packages)"
sudo add-apt-repository -y --remove ppa:t4-system-software/agnocast || true
sudo rm -f /etc/apt/sources.list.d/t4-system-software-ubuntu-agnocast-*.list
sudo apt-get update -y


echo "[*] Final state:"
dkms status | grep -i agnocast || echo "OK: dkms clean"
dpkg -l | grep -E '^ii\s+agnocast-' || echo "OK: packages purged"
lsmod | grep -i agnocast || echo "OK: module not loaded"
test ! -f /etc/modules-load.d/agnocast.conf && echo "OK: no autoload file"
apt-cache policy agnocast-kmod | sed -n '1,10p'

