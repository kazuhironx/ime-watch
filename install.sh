#!/usr/bin/env bash
# ime-watch を ~/.local/bin と systemd --user にリンクして有効化する。
# 再実行しても同じ状態になる。--uninstall で停止してリンクを外す。
set -euo pipefail

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/.local/bin/ime-watch"
UNIT="$HOME/.config/systemd/user/ime-watch.service"

if [ "${1:-}" = "--uninstall" ]; then
  systemctl --user disable --now ime-watch.service 2>/dev/null || true
  rm -f "$BIN" "$UNIT"
  systemctl --user daemon-reload
  echo "uninstalled"
  exit 0
fi

mkdir -p "$(dirname "$BIN")" "$(dirname "$UNIT")"
ln -sfn "$SRC_DIR/ime-watch" "$BIN"
ln -sfn "$SRC_DIR/ime-watch.service" "$UNIT"
systemctl --user daemon-reload
systemctl --user enable ime-watch.service
# 実行中でもスクリプト更新を反映させたいので start ではなく restart
systemctl --user restart ime-watch.service
systemctl --user --no-pager status ime-watch.service | head -3
