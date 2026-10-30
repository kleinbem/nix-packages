#!/usr/bin/env bash
# Behaviour test for nixpkgs' berd: starts the packaged app (under Xvfb on
# Linux, in the runner's GUI session on macOS) with its bundled goosed pointed
# at a local llama-server, creates a chat through berdctl and waits for the
# model's reply in goose's session store.
#
#   NIXPKGS=~/nixpkgs canary/berd/behaviour.sh
#
# NIXPKGS: a nixpkgs checkout with berd (kleinbem/nixpkgs@berd).
set -euo pipefail

nixpkgs="$(realpath "${NIXPKGS:?set NIXPKGS to a nixpkgs checkout}")"
here="$(dirname "$(realpath "$0")")"
build() { nix-build "$here" --arg nixpkgs "$nixpkgs" -A "$1" --no-out-link; }
berd="$(build berd)"
tools="$(build tools)"
model="$(build model)"
export PATH="$tools/bin:$PATH"
echo "berd: $berd"

work="$(mktemp -d)"
logs="${LOGS:-$work/logs}"
mkdir -p "$logs"
port=18085

pids=()
cleanup() {
  # Catch's goose isn't our child; stop it first.
  if [[ -n ${catch_pid:-} ]]; then pkill -P "$catch_pid" 2>/dev/null || true; fi
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup EXIT

# goose's first prompt is about 4k tokens.
llama-server -m "$model" --host 127.0.0.1 --port "$port" --alias tiny -c 16384 \
  >"$logs/llama-server.log" 2>&1 &
pids+=($!)
for _ in $(seq 120); do
  curl -sf "http://127.0.0.1:$port/health" >/dev/null && break
  sleep 1
done
curl -sf "http://127.0.0.1:$port/health" >/dev/null

# A fresh home on Linux; macOS apps keep their state under the user's Library,
# and the runner's home is fresh anyway.
if [[ $(uname) == Linux ]]; then
  export HOME="$work/home" XDG_RUNTIME_DIR="$work/run"
  # GitHub's Ubuntu runners set XDG_CONFIG_HOME to the runner's ~/.config;
  # goose would read its config there instead of the one written below.
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
fi
mkdir -p "$HOME/.config/goose"
# llama-server's Responses API lacks created_at; use chat completions.
cat >"$HOME/.config/goose/config.yaml" <<YAML
GOOSE_PROVIDER: openai
GOOSE_MODEL: tiny
OPENAI_HOST: http://127.0.0.1:$port
OPENAI_BASE_PATH: chat/completions
YAML
export GOOSE_DISABLE_KEYRING=1 OPENAI_API_KEY=local

if [[ $(uname) == Linux ]]; then
  # Outside NixOS, Nix-built WebKit finds no EGL driver ("Could not create default EGL
  # display"); use nixpkgs' Mesa (software rendering under Xvfb).
  if [[ ! -e /run/opengl-driver ]]; then
    export __EGL_VENDOR_LIBRARY_DIRS="$tools/share/glvnd/egl_vendor.d"
    export LIBGL_DRIVERS_PATH="$tools/lib/dri" GBM_BACKENDS_PATH="$tools/lib/gbm"
    export LIBGL_ALWAYS_SOFTWARE=1
  fi
  # No accessibility bus under Xvfb.
  NO_AT_BRIDGE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1 GDK_BACKEND=x11 \
    xvfb-run -a -s '-screen 0 1440x900x24' "$berd/bin/berd" >"$logs/berd.log" 2>&1 &
else
  "$berd/bin/berd" >"$logs/berd.log" 2>&1 &
fi
pids+=($!)

lock=""
for _ in $(seq 90); do
  lock="$(find "$HOME" -path '*xyz.block.berd*/berdctl/control-*.json' 2>/dev/null | head -n 1)"
  [[ -n $lock ]] && BERDCTL_LOCK="$lock" "$berd/bin/berdctl" --json info harnesses >/dev/null 2>&1 && break
  sleep 2
done
if [[ -z $lock ]]; then
  echo "berdctl found no running Berd" >&2
  tail -n 50 "$logs/berd.log" >&2
  exit 1
fi
ctl() { BERDCTL_LOCK="$lock" "$berd/bin/berdctl" --json "$@"; }

# goose reports ready once goosed has answered; slower runners need a while.
harnesses=""
for _ in $(seq 90); do
  harnesses="$(ctl info harnesses 2>/dev/null || true)"
  jq -e '.harnesses[] | select(.harness_id == "goose" and .status == "ready")' <<<"$harnesses" >/dev/null 2>&1 && break
  sleep 2
done
echo "== harnesses"
echo "$harnesses"
echo "== session create"
created="$(ctl session create --harness-id goose --prompt "Reply with exactly the word PONG.")"
echo "$created"
sid="$(jq -er '.session_id' <<<"$created")"

reply=""
for _ in $(seq 120); do
  sleep 5
  db="$(find "$HOME" -path '*goose/sessions/sessions.db' 2>/dev/null | head -n 1)"
  [[ -n $db ]] || continue
  reply="$(sqlite3 "$db" "select content_json from messages where session_id='$sid' and role='assistant' order by id limit 1" 2>/dev/null || true)"
  [[ -n $reply ]] && break
done
echo "== assistant"
echo "$reply"
text="$(jq -r '[.[] | select(.type == "text") | .text] | join("")' <<<"${reply:-[]}")"
if [[ -z $text ]]; then
  echo "no reply from the model through Berd and goosed" >&2
  tail -n 50 "$logs/berd.log" >&2
  exit 1
fi
echo "reply: $text"

# macOS: Catch, Berd's global-shortcut sidecar, standalone. It starts `goose serve`
# itself through GOOSE_BINARY; a stand-in records what it was started with, then
# runs the real goose.
if [[ "$(uname)" == Darwin ]]; then
  catch="$(build catch)"
  goose="$(build goose-cli)"
  probe="$work/goose-probe"
  capture="$work/catch-goose.txt"
  # Written whole, then renamed, so the wait never sees a partial file.
  cat >"$probe" <<SH
#!/bin/sh
{ echo "arg1: \$1"; echo "args: \$*"; echo "PATH=\$PATH"; } >"$capture.tmp" && /bin/mv "$capture.tmp" "$capture"
exec "$goose/bin/goose" "\$@"
SH
  chmod +x "$probe"
  GOOSE_BINARY="$probe" "$catch/bin/catch" >"$logs/catch.log" 2>&1 &
  catch_pid=$!
  pids+=("$catch_pid")
  for ((i = 0; i < 60; i++)); do
    [[ -s $capture ]] && break
    sleep 1
  done
  echo "== catch"
  if ! kill -0 "$catch_pid" 2>/dev/null || [[ ! -s $capture ]]; then
    echo "Catch didn't start goose serve" >&2
    tail -n 30 "$logs/catch.log" >&2
    exit 1
  fi
  if ! grep -qx 'arg1: serve' "$capture"; then
    echo "Catch started goose without serve:" >&2
    cat "$capture" >&2
    exit 1
  fi
  cp "$capture" "$logs/"
  cat "$capture"
  echo "caller PATH=$PATH"
fi
