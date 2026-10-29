#!/bin/bash
# Remove everything install.sh created.
#   sudo bash client-linux/scripts/uninstall.sh
# Body is a function so bash has parsed the whole file before it deletes
# the installed copy of this script.
set -eu
. "$(dirname "$0")/common.sh"
main() {
  need_root
  systemctl disable --now --quiet "$UNIT" "$DNS_UNIT" 2>/dev/null || true
  systemctl disable --now --quiet anthropic-tunnel-xhttp.service 2>/dev/null || true
  if dns_layer_up; then resolvectl revert "$DNS_LINK" 2>/dev/null || true; ip link del "$DNS_LINK" || true; fi
  rm -f "${UNIT_DIR:?}/${UNIT:?}" "${UNIT_DIR:?}/${DNS_UNIT:?}" "${SUDOERS:?}" "${NM_CONF:?}"
  rm -f "$UNIT_DIR/anthropic-tunnel-xhttp.service" "$UNIT_DIR/$UNIT.d/xhttp.conf"
  rmdir "$UNIT_DIR/$UNIT.d" 2>/dev/null || true
  systemctl daemon-reload
  resolvectl flush-caches 2>/dev/null || true
  rm -rf "${BASE:?}"
  echo "uninstalled: units, sudoers, NetworkManager snippet, dns link, $BASE removed"
  printf 'tun interface : '
  if ip link show "$TUN_IF" >/dev/null 2>&1; then echo "STILL UP (check manually)"; else echo down; fi
}
main "$@"
