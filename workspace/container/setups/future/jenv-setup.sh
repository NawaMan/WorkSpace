#!/bin/bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--no-autodetect] [--no-global] [--plugins "<p1 p2 ...>"]

Examples:
  $0                             # install jenv, autodetect JDKs, set newest as global
  $0 --no-autodetect             # install jenv only; don't scan for JDKs
  $0 --no-global                 # don't change global, leave 'system'
  $0 --plugins "export maven"    # also enable extra plugins

Notes:
- Installs jenv at /opt/jenv (JENV_ROOT), world-writable (dev/CI friendly)
- Adds /opt/jenv/bin and /opt/jenv/shims to PATH
- Enables 'export' plugin by default so JAVA_HOME follows the selected JDK
- Autodetects JDKs from /opt/jdk*, /usr/lib/jvm/*, /opt/jbang-cache/jdks/*
USAGE
}

# ---- root check ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

# ---- args / defaults ----
AUTODETECT=1
SET_GLOBAL=1
EXTRA_PLUGINS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-autodetect) AUTODETECT=0; shift ;;
    --no-global)     SET_GLOBAL=0; shift ;;
    --plugins)       shift; EXTRA_PLUGINS="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git ca-certificates curl coreutils
rm -rf /var/lib/apt/lists/*

# ---- locations ----
export JENV_ROOT=/opt/jenv
BIN_DIR=/usr/local/bin

# Fresh install / upgrade
rm -rf "$JENV_ROOT"
git clone --depth=1 https://github.com/jenv/jenv.git "$JENV_ROOT"

# Make dev-friendly (any user can add/remove versions)
chmod -R 0777 "$JENV_ROOT" || true

# Ensure jenv is usable in THIS shell
export PATH="$JENV_ROOT/bin:$JENV_ROOT/shims:$PATH"
# Initialize for current shell (bash/zsh will just eval harmlessly)
eval "$("$JENV_ROOT/bin/jenv" init -)" || true

# Enable core plugin(s)
"$JENV_ROOT/bin/jenv" plugins | grep -q '\<export\>' || true
"$JENV_ROOT/bin/jenv" enable-plugin export || true

# Optional extra plugins (space-separated)
if [[ -n "$EXTRA_PLUGINS" ]]; then
  for p in $EXTRA_PLUGINS; do
    "$JENV_ROOT/bin/jenv" enable-plugin "$p" || true
  done
fi

# ---- autodetect JDKs ----
if [[ $AUTODETECT -eq 1 ]]; then
  echo "[jenv] Scanning for JDKs to add..."
  found=0
  # Common roots you use
  CANDIDATES=(
    /opt/jdk*
    /usr/lib/jvm/*
    /opt/jbang-cache/jdks/*
  )
  for d in "${CANDIDATES[@]}"; do
    for home in $d; do
      if [[ -d "$home" && -x "$home/bin/java" ]]; then
        "$JENV_ROOT/bin/jenv" add "$home" || true
        found=1
      fi
    done
  done

  # jenv rehash to populate shims
  "$JENV_ROOT/bin/jenv" rehash || true

  # If we added any, optionally set the newest as global
  if [[ $found -eq 1 && $SET_GLOBAL -eq 1 ]]; then
    # Heuristic: pick the highest semver-ish version label from `jenv versions --bare`
    newest="$("$JENV_ROOT/bin/jenv" versions --bare 2>/dev/null | grep -v '^system$' | sort -V | tail -n1 || true)"
    if [[ -n "$newest" ]]; then
      "$JENV_ROOT/bin/jenv" global "$newest" || true
      echo "[jenv] Global set to: $newest"
    fi
  fi
fi

# ---- login-shell env ----
cat >/etc/profile.d/50-jenv.sh <<'EOF'
# jenv system install
export JENV_ROOT=/opt/jenv
export PATH="$JENV_ROOT/bin:$JENV_ROOT/shims:$PATH"
# Initialize jenv (safe to run multiple times)
eval "$("$JENV_ROOT/bin/jenv" init -)" 2>/dev/null || true
EOF
chmod 0644 /etc/profile.d/50-jenv.sh

# Fish
install -d /etc/fish/conf.d
cat >/etc/fish/conf.d/jenv.fish <<'EOF'
set -gx JENV_ROOT /opt/jenv
if test -d $JENV_ROOT/bin
  fish_add_path -g $JENV_ROOT/bin
end
if test -d $JENV_ROOT/shims
  fish_add_path -g $JENV_ROOT/shims
end
# initialize jenv
status --is-interactive; and $JENV_ROOT/bin/jenv init - fish | source
EOF
chmod 0644 /etc/fish/conf.d/jenv.fish

# Nushell
install -d /etc/nu
cat >/etc/nu/jenv.nu <<'EOF'
$env.JENV_ROOT = "/opt/jenv"
let bin = ($env.JENV_ROOT | path join "bin")
let shims = ($env.JENV_ROOT | path join "shims")
if ($bin | path exists) { $env.PATH = ($bin | path add $env.PATH) }
if ($shims | path exists) { $env.PATH = ($shims | path add $env.PATH) }
# jenv doesn't have a native nu init; bash init isn't needed for basic PATH/shims use
EOF
chmod 0644 /etc/nu/jenv.nu

# ---- non-login convenience wrapper ----
# Lets you run `jenv ...` reliably in Docker RUN or plain `sh -c` steps
cat >"$BIN_DIR/jenvwrap" <<'EOF'
#!/bin/sh
export JENV_ROOT=/opt/jenv
export PATH="$JENV_ROOT/bin:$JENV_ROOT/shims:$PATH"
# Initialize (silently ignore if shell not supported)
init="$("$JENV_ROOT/bin/jenv" init - 2>/dev/null)" || true
# Only eval if it contains 'export' (basic safety)
printf '%s' "$init" | grep -q 'export ' && eval "$init"
exec "$JENV_ROOT/bin/jenv" "$@"
EOF
chmod +x "$BIN_DIR/jenvwrap"

# Also expose `jenv` itself for convenience
ln -sfn "$BIN_DIR/jenvwrap" "$BIN_DIR/jenv"

# ---- friendly summary ----
echo "✅ jenv installed to $JENV_ROOT"
echo -n "   jenv version → "; "$BIN_DIR/jenv" --version 2>/dev/null || true
echo "   PATH shims at: $JENV_ROOT/shims"
echo "   Plugins: export${EXTRA_PLUGINS:+ $EXTRA_PLUGINS}"
if "$BIN_DIR/jenv" versions >/dev/null 2>&1; then
  echo "   Detected JDKs:"
  "$BIN_DIR/jenv" versions || true
fi

cat <<'EON'
ℹ️ Ready to use:
- New shells: jenv is auto-initialized via /etc/profile.d/50-jenv.sh
- Non-login shells/CI: use 'jenv' directly (wrapper primes PATH)
- Change global JDK: jenv global <version>
- Per-project JDK:   jenv local  <version>
- See versions:      jenv versions

Tips:
- The 'export' plugin keeps JAVA_HOME in sync with your jenv selection.
- If you add JDKs later, run: jenv add /path/to/jdk && jenv rehash
EON
