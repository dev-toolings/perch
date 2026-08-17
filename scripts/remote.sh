#!/usr/bin/env bash
# Monitor and approve agent sessions running on another machine.
#
#   ./scripts/remote.sh add build-box deploy@10.0.0.5
#   ./scripts/remote.sh deploy build-box     # upload the hook, wire the remote's CLIs
#   ./scripts/remote.sh connect build-box    # open the tunnel (stays in the foreground)
#   ./scripts/remote.sh status
#   ./scripts/remote.sh remove build-box     # undo everything on the remote
#
# How it works: the remote's hooks talk to a fixed port on the remote's own loopback, and
# `connect` reverse-forwards that port to whatever port Perch is listening on right now.
# Perch's port and token change on every launch, so `connect` re-pushes the token each
# time — a stale token is the failure you would otherwise spend an evening on.
#
# Needs SSH public-key auth. Nothing here types a password.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOSTS="$PERCH_HOME/remotes.json"
HOOK_SRC="$PERCH_ROOT/scripts/perch-remote-hook.sh"
REMOTE_HOME=".perch-remote"
REMOTE_PORT="${PERCH_REMOTE_PORT:-17890}"

command -v jq >/dev/null 2>&1 || fail "jq is required"

hosts_read() {
  [ -f "$HOSTS" ] || echo '[]' >"$HOSTS"
  cat "$HOSTS"
}

host_target() {
  hosts_read | jq -r --arg a "$1" '.[] | select(.alias == $a) | .target' | head -1
}

host_options() {
  hosts_read | jq -r --arg a "$1" '.[] | select(.alias == $a) | .options // ""' | head -1
}

require_host() {
  local target
  target="$(host_target "$1")"
  [ -n "$target" ] || fail "unknown host: $1 (add it first)"
  echo "$target"
}

cmd_add() {
  local alias="${1:-}" target="${2:-}" options="${3:-}"
  [ -n "$alias" ] && [ -n "$target" ] || fail "usage: remote.sh add <alias> <user@host> [ssh-options]"
  mkdir -p "$PERCH_HOME"
  hosts_read | jq --arg a "$alias" --arg t "$target" --arg o "$options" \
    '[.[] | select(.alias != $a)] + [{alias: $a, target: $t, options: $o}]' >"$HOSTS.tmp"
  mv "$HOSTS.tmp" "$HOSTS"
  ok "added $alias → $target"
  info "next: ./scripts/remote.sh deploy $alias"
}

cmd_list() {
  local count
  count="$(hosts_read | jq 'length')"
  [ "$count" -gt 0 ] || { info "no remote hosts configured"; return 0; }
  hosts_read | jq -r '.[] | "  \(.alias)\t\(.target)\t\(.options)"'
}

# shellcheck disable=SC2029  # the remote command is built here on purpose
cmd_deploy() {
  local alias="${1:-}" target
  target="$(require_host "$alias")"
  local opts; opts="$(host_options "$alias")"

  [ -f "$HOOK_SRC" ] || fail "hook script not found: $HOOK_SRC"

  # shellcheck disable=SC2086
  ssh $opts "$target" "mkdir -p ~/$REMOTE_HOME && chmod 700 ~/$REMOTE_HOME" \
    || fail "could not reach $target over SSH"

  # Stream the managed hook through the SSH channel itself. Reconfiguration must replace
  # an older Perch hook (protocol and metadata evolve), and this avoids the SFTP subsystem
  # that corporate networks commonly disable.
  info "installing the current hook on ${target}…"
  # shellcheck disable=SC2086
  ssh $opts "$target" "umask 077; cat > ~/$REMOTE_HOME/perch-remote-hook.sh.tmp && \
    chmod 700 ~/$REMOTE_HOME/perch-remote-hook.sh.tmp && \
    mv ~/$REMOTE_HOME/perch-remote-hook.sh.tmp ~/$REMOTE_HOME/perch-remote-hook.sh" \
    < "$HOOK_SRC" || fail "could not install the hook over SSH"

  info "wiring the remote's Claude Code hooks…"
  # The remote may not have jq, so the settings file is rewritten with a here-doc-driven
  # python3 fallback when it is missing.
  # shellcheck disable=SC2086
  ssh $opts "$target" "PERCH_REMOTE_HOME=\$HOME/$REMOTE_HOME bash -s" <<'REMOTE'
set -euo pipefail
HOOK="$HOME/.perch-remote/perch-remote-hook.sh"
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"
cp "$SETTINGS" "$SETTINGS.perch-backup"

python3 - "$SETTINGS" "$HOOK" <<'PY'
import json, sys
path, hook = sys.argv[1], sys.argv[2]
with open(path) as f:
    try: root = json.load(f)
    except Exception: root = {}

events = {
    "PermissionRequest": 86400, "PreToolUse": 5, "PostToolUse": 5, "Notification": 5,
    "UserPromptSubmit": 5, "Stop": 5, "StopFailure": 5, "SubagentStart": 5,
    # SessionEnd is 3 because Claude Code clamps that event to 3s and warns about more.
    "SubagentStop": 5, "PreCompact": 5, "SessionStart": 5, "SessionEnd": 3,
}

hooks = root.setdefault("hooks", {})
for event, timeout in events.items():
    entries = [e for e in hooks.get(event, [])
               if not any("perch-remote-hook" in (h.get("command") or "")
                          for h in e.get("hooks", []))]
    entries.append({"hooks": [{"type": "command",
                               "command": f"{hook} {event} --source claude",
                               "timeout": timeout}]})
    hooks[event] = entries

with open(path, "w") as f:
    json.dump(root, f, indent=2)
PY
echo "  hooks written to $SETTINGS"
REMOTE

  ok "deployed to $alias"
  warn "restart any Claude Code session already open on the remote"
  info "next: ./scripts/remote.sh connect $alias"
}

cmd_connect() {
  local alias="${1:-}" target
  target="$(require_host "$alias")"
  local opts; opts="$(host_options "$alias")"

  local runtime="$PERCH_HOME/runtime.json"
  [ -f "$runtime" ] || fail "Perch is not running — start it first"
  local port token alias_b64
  port="$(jq -r '.port' "$runtime")"
  token="$(jq -r '.token' "$runtime")"
  alias_b64="$(printf '%s' "$alias" | base64 | tr -d '\n')"
  [ -n "$port" ] && [ -n "$token" ] || fail "could not read the runtime handshake"

  # Both change on every launch, so they are pushed at connect time rather than at deploy
  # time. Mode 600, because it is a bearer token.
  info "pushing the current token…"
  # shellcheck disable=SC2086,SC2029
  ssh $opts "$target" "umask 077; mkdir -p ~/$REMOTE_HOME; \
    printf 'PERCH_PORT=%s\nPERCH_TOKEN=%s\nPERCH_HOST_ALIAS_B64=%s\n' '$REMOTE_PORT' '$token' '$alias_b64' > ~/$REMOTE_HOME/config"

  ok "tunnel: remote 127.0.0.1:$REMOTE_PORT → this Mac's Perch on $port"
  info "leave this running; Ctrl-C closes the tunnel"
  # ExitOnForwardFailure so a port already taken fails loudly instead of connecting to
  # nothing. Keepalives so a sleeping laptop drops the tunnel rather than wedging it.
  # shellcheck disable=SC2086
  exec ssh $opts -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -R "$REMOTE_PORT:127.0.0.1:$port" "$target"
}

# A container has no SSH tunnel and no way for Perch to reach into it, so the flow is
# inverted: the container reaches the Mac directly through `host.docker.internal`, and the
# one-liner is something you paste inside it.
cmd_docker() {
  local runtime="$PERCH_HOME/runtime.json"
  [ -f "$runtime" ] || fail "Perch is not running — start it first"
  local port token
  port="$(jq -r '.port' "$runtime")"
  token="$(jq -r '.token' "$runtime")"

  info "paste this inside the container:"
  echo
  cat <<ONELINER
mkdir -p ~/.perch-remote && cat > ~/.perch-remote/perch-remote-hook.sh <<'HOOK' && \\
chmod 700 ~/.perch-remote/perch-remote-hook.sh && \\
printf 'PERCH_HOST=host.docker.internal\nPERCH_PORT=$port\nPERCH_TOKEN=$token\n' > ~/.perch-remote/config && \\
chmod 600 ~/.perch-remote/config
$(cat "$HOOK_SRC")
HOOK
ONELINER
  echo
  warn "the token changes every time Perch restarts — re-run this after a restart"
  info "then wire the container's hooks the same way deploy does, or copy ~/.claude/settings.json in"
  info "Podman: use host.containers.internal instead of host.docker.internal"
}

# Corporate networks routinely block scp — the sftp subsystem — while leaving ssh itself
# open, and some machines have neither. The hook is a text file, so it can travel by any
# channel at all; this prints it for copying by hand.
cmd_manual() {
  info "the hook is one text file. Paste it on the remote as ~/.perch-remote/perch-remote-hook.sh:"
  echo
  echo "mkdir -p ~/.perch-remote && chmod 700 ~/.perch-remote && cat > ~/.perch-remote/perch-remote-hook.sh <<'HOOK'"
  cat "$HOOK_SRC"
  echo "HOOK"
  echo "chmod 700 ~/.perch-remote/perch-remote-hook.sh"
  echo
  info "then run: ./scripts/remote.sh deploy <alias> — it detects the file and skips the upload"
}

# Relays the *remote's own* plan quota. Useful when Claude is signed in on the server
# rather than on this Mac — the two accounts have different budgets, and showing one in
# place of the other would be worse than showing neither.
cmd_usage() {
  local alias="${1:-}" target
  target="$(require_host "$alias")"
  local opts; opts="$(host_options "$alias")"

  info "wiring the remote's statusline to relay its quota…"
  # shellcheck disable=SC2086
  ssh $opts "$target" "PERCH_ALIAS='$alias' bash -s" <<'REMOTE'
set -euo pipefail
HOOK="$HOME/.perch-remote/perch-remote-hook.sh"
[ -x "$HOOK" ] || { echo "  hook not deployed — run deploy first" >&2; exit 1; }

BRIDGE="$HOME/.perch-remote/statusline"
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"

# Same shape as the Mac's bridge: read stdin once, relay, replay the identical bytes to
# whatever statusline was already there so its visible output is unchanged.
python3 - "$SETTINGS" "$BRIDGE" "${PERCH_ALIAS:-remote}" <<'PY'
import json, os, sys
settings, bridge, alias = sys.argv[1], sys.argv[2], sys.argv[3]
with open(settings) as f:
    try: root = json.load(f)
    except Exception: root = {}

current = (root.get("statusLine") or {}).get("command", "")
if current == bridge:
    print("  already relaying"); raise SystemExit(0)

os.makedirs(os.path.dirname(bridge), exist_ok=True)
with open(os.path.join(os.path.dirname(bridge), "statusline-original"), "w") as f:
    f.write(current)

with open(bridge, "w") as f:
    f.write(f"""#!/bin/sh
STDIN_FILE="${{TMPDIR:-/tmp}}/perch-remote-statusline.$$"
trap 'rm -f "$STDIN_FILE"' EXIT HUP INT TERM
cat > "$STDIN_FILE"
PERCH_RELAY_USAGE=1 PERCH_HOST_ALIAS={alias} \\
  "$HOME/.perch-remote/perch-remote-hook.sh" --usage < "$STDIN_FILE" >/dev/null 2>&1 || true
ORIGINAL=$(cat "$HOME/.perch-remote/statusline-original" 2>/dev/null)
[ -n "$ORIGINAL" ] || exit 0
exec /bin/sh -c "$ORIGINAL" < "$STDIN_FILE"
""")
os.chmod(bridge, 0o700)

root.setdefault("statusLine", {}).update({"type": "command", "command": bridge})
with open(settings, "w") as f:
    json.dump(root, f, indent=2)
print("  statusline now relays quota")
PY
REMOTE

  ok "quota relay wired on $alias"
  warn "restart the remote's Claude Code sessions — statusLine is read at session start"
  info "the quota shows up in Perch once the remote renders a statusline"
}

# Vibe discovers Paperclip-managed Codex homes before asking which ones to wire. The
# remote prints only base64 paths in a small tagged protocol: no remote jq dependency,
# no word-splitting of paths, and a hard result cap before Swift sees the response.
cmd_codex_roots() {
  local alias="${1:-}" target output count line encoded decoded
  target="$(require_host "$alias")"
  local opts; opts="$(host_options "$alias")"

  # shellcheck disable=SC2086
  output="$(ssh $opts "$target" /bin/sh -s <<'REMOTE'
count=0
paperclip_root=$(CDPATH= cd "$HOME/.paperclip/instances" 2>/dev/null && pwd -P) || exit 0
for path in \
  "$HOME"/.paperclip/instances/*/companies/*/codex-home \
  "$HOME"/.paperclip/instances/*/companies/*/agents/*/codex-home
do
  test -d "$path" || continue
  canonical=$(CDPATH= cd "$path" 2>/dev/null && pwd -P) || continue
  case "$canonical" in "$paperclip_root"/*) ;; *) continue ;; esac
  encoded=$(printf '%s' "$canonical" | base64 | tr -d '\r\n')
  printf 'PAPERCLIP\t%s\n' "$encoded"
  count=$((count + 1))
  test "$count" -ge 129 && break
done
REMOTE
  )" || fail "Could not scan remote Codex directories."

  count=0
  printf '[]' >"$PERCH_HOME/codex-roots.$$.json"
  while IFS=$'\t' read -r line encoded; do
    [ -n "$line$encoded" ] || continue
    [ "$line" = "PAPERCLIP" ] && [ -n "$encoded" ] \
      || fail "The remote Codex directory scan returned invalid data."
    count=$((count + 1))
    [ "$count" -le 128 ] \
      || fail "The remote Codex directory scan returned too many results."
    decoded="$(printf '%s' "$encoded" | base64 -D 2>/dev/null)" \
      || fail "The remote Codex directory scan returned invalid data."
    case "$decoded" in /*) ;; *) fail "The remote Codex directory scan returned invalid data." ;; esac
    jq --arg p "$decoded" '. + [{path: $p, source: "paperclip"}]' \
      "$PERCH_HOME/codex-roots.$$.json" >"$PERCH_HOME/codex-roots.$$.tmp"
    mv "$PERCH_HOME/codex-roots.$$.tmp" "$PERCH_HOME/codex-roots.$$.json"
  done <<<"$output"
  cat "$PERCH_HOME/codex-roots.$$.json"
  rm -f "$PERCH_HOME/codex-roots.$$.json" "$PERCH_HOME/codex-roots.$$.tmp"
}

# Installs the remote forwarding hook into every Codex home selected in the app. Roots are
# base64 arguments so spaces and shell metacharacters never become part of the SSH command.
# The remote already needs Python for the Claude setup above; use the same dependency to
# preserve foreign JSON and replace only Perch-owned entries.
cmd_codex_setup() {
  local alias="${1:-}" target
  shift || true
  target="$(require_host "$alias")"
  local opts; opts="$(host_options "$alias")"
  [ "$#" -gt 0 ] || fail "No Codex directories were selected."

  # shellcheck disable=SC2086
  ssh $opts "$target" /bin/bash -s -- "$@" <<'REMOTE'
set -euo pipefail
HOOK="$HOME/.perch-remote/perch-remote-hook.sh"
[ -x "$HOOK" ] || { echo "Remote hook is missing — run Configure first." >&2; exit 1; }

python3 - "$HOOK" "$@" <<'PY'
import base64, json, os, sys, tempfile

hook = sys.argv[1]
encoded_roots = sys.argv[2:]
events = {
    "PermissionRequest": 86400,
    "PreToolUse": 5,
    "PostToolUse": 5,
    "UserPromptSubmit": 5,
    "Stop": 5,
    "SubagentStart": 5,
    "SubagentStop": 5,
    "PreCompact": 5,
    "SessionStart": 5,
    "SessionEnd": 3,
}

def decode_root(encoded):
    try:
        value = base64.b64decode(encoded, validate=True).decode("utf-8")
    except Exception as error:
        raise ValueError("invalid encoded Codex directory") from error
    if value == "~/.codex":
        return os.path.join(os.path.expanduser("~"), ".codex")
    if not os.path.isabs(value):
        raise ValueError(f"Codex directory is not absolute: {value}")
    return os.path.normpath(value)

failed = []
configured = []
for encoded in encoded_roots:
    try:
        root = decode_root(encoded)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
    if not os.path.isdir(root):
        failed.append(root)
        continue

    path = os.path.join(root, "hooks.json")
    try:
        with open(path, encoding="utf-8") as source:
            document = json.load(source)
    except FileNotFoundError:
        document = {}
    except Exception as error:
        print(f"Could not read {path}: {error}", file=sys.stderr)
        raise SystemExit(1)
    if not isinstance(document, dict):
        print(f"Codex hooks file is not an object: {path}", file=sys.stderr)
        raise SystemExit(1)

    hooks = document.get("hooks")
    if not isinstance(hooks, dict):
        hooks = {}
    for event, matchers in list(hooks.items()):
        if not isinstance(matchers, list):
            continue
        kept_matchers = []
        for matcher in matchers:
            if not isinstance(matcher, dict):
                kept_matchers.append(matcher)
                continue
            entries = matcher.get("hooks")
            if not isinstance(entries, list):
                kept_matchers.append(matcher)
                continue
            kept_entries = [
                entry for entry in entries
                if not isinstance(entry, dict)
                or "perch-remote-hook" not in str(entry.get("command", ""))
            ]
            if kept_entries:
                copy = dict(matcher)
                copy["hooks"] = kept_entries
                kept_matchers.append(copy)
        if kept_matchers:
            hooks[event] = kept_matchers
        else:
            hooks.pop(event, None)

    for event, timeout in events.items():
        entry = {
            "hooks": [{
                "type": "command",
                "command": f"{hook} {event} --source codex",
                "timeout": timeout,
            }]
        }
        hooks.setdefault(event, []).append(entry)
    document["hooks"] = hooks

    os.makedirs(root, mode=0o700, exist_ok=True)
    if os.path.exists(path) and not os.path.exists(path + ".perch-backup"):
        with open(path, "rb") as source, open(path + ".perch-backup", "wb") as backup:
            backup.write(source.read())
    descriptor, temporary = tempfile.mkstemp(prefix=".perch-hooks.", dir=root)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(document, output, indent=2)
            output.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    configured.append(root)

if failed:
    print("Some Codex directories were not connected: " + ", ".join(failed), file=sys.stderr)
    print("Re-run Configure after those directories exist.", file=sys.stderr)
    raise SystemExit(1)

for root in configured:
    print(f"  Codex hooks written to {root}/hooks.json")
PY
REMOTE
}

# Internal stdio bridge used by the app's read-only trust probe. The root is base64 and
# the command itself is fixed; no selected path is evaluated by a shell. Keeping stdin and
# stdout attached lets Swift speak Codex app-server's JSON-RPC protocol through SSH.
cmd_codex_app_server() {
  local alias="${1:-}" encoded_root="${2:-}" target remote_command
  [ -n "$encoded_root" ] || fail "Missing encoded Codex directory."
  target="$(require_host "$alias")"
  local opts; opts="$(host_options "$alias")"

  remote_command="codex_root=\$(printf '%s' '$encoded_root' | base64 -d 2>/dev/null || printf '%s' '$encoded_root' | base64 -D 2>/dev/null); test \"\$codex_root\" = '~/.codex' && codex_root=\"\$HOME/.codex\"; test -d \"\$codex_root\" || exit 126; export CODEX_HOME=\"\$codex_root\"; exec \"\${SHELL:-/bin/sh}\" -lc 'command -v codex >/dev/null 2>&1 || exit 127; exec codex app-server --listen stdio://'"
  # shellcheck disable=SC2086
  exec ssh $opts "$target" "$remote_command"
}

cmd_status() {
  local count
  count="$(hosts_read | jq 'length')"
  info "hosts          $count"
  cmd_list
  if [ -f "$PERCH_HOME/runtime.json" ]; then
    ok "Perch          listening on $(jq -r '.port' "$PERCH_HOME/runtime.json")"
  else
    warn "Perch          not running — connect would have nothing to forward to"
  fi
  if pgrep -f "ssh .*-R $REMOTE_PORT:127.0.0.1" >/dev/null 2>&1; then
    ok "tunnel         up"
  else
    info "tunnel         down"
  fi
}

cmd_remove() {
  local alias="${1:-}" target
  target="$(require_host "$alias")"
  local opts; opts="$(host_options "$alias")"

  info "removing Perch from ${target}…"
  # shellcheck disable=SC2086
  ssh $opts "$target" bash -s <<'REMOTE' || warn "remote cleanup failed — the host may be unreachable"
set -uo pipefail
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.perch-backup"
  python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    try: root = json.load(f)
    except Exception: sys.exit(0)
hooks = root.get("hooks", {})
for event in list(hooks):
    kept = [e for e in hooks[event]
            if not any("perch-remote-hook" in (h.get("command") or "")
                       for h in e.get("hooks", []))]
    if kept: hooks[event] = kept
    else: del hooks[event]
if not hooks: root.pop("hooks", None)
with open(path, "w") as f:
    json.dump(root, f, indent=2)
PY
fi
rm -rf "$HOME/.perch-remote"
echo "  removed"
REMOTE

  hosts_read | jq --arg a "$alias" '[.[] | select(.alias != $a)]' >"$HOSTS.tmp"
  mv "$HOSTS.tmp" "$HOSTS"
  ok "removed $alias"
}

case "${1:-status}" in
  add) shift; cmd_add "$@" ;;
  list) cmd_list ;;
  deploy) shift; cmd_deploy "$@" ;;
  connect) shift; cmd_connect "$@" ;;
  docker) cmd_docker ;;
  manual) cmd_manual ;;
  usage) shift; cmd_usage "$@" ;;
  codex-roots) shift; cmd_codex_roots "$@" ;;
  codex-setup) shift; cmd_codex_setup "$@" ;;
  codex-app-server) shift; cmd_codex_app_server "$@" ;;
  status) cmd_status ;;
  remove) shift; cmd_remove "$@" ;;
  *) fail "usage: remote.sh [add|list|deploy|connect|usage|codex-roots|codex-setup|codex-app-server|docker|manual|status|remove]" ;;
esac
