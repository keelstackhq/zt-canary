#!/usr/bin/env bash
# Setup script for this repo's Claude Code cloud environment (spec D23). Written by the bosun
# splice channel. Paste it into the environment's setup script; it runs as root before a session.
set -euo pipefail

# Pinned tool versions; the bosun channel moves them with its own versions.
NODE_MAJOR=24
PNPM_VERSION=12.15.0
SPLICE_VERSION=0.3.1
# npm's dist.integrity (sha512) of each tool's launcher and linux binary packages, from
# `npm view @keelstackhq/<package>@<version> dist.integrity`; move them with the version.
SPLICE_SHA512=FyJMvUQ4SxjaLtECPp1YmRpMMzYwRaGsdCJ/den/PRZBkkecMyWRLq3v7UECIpJfWuIGWlDmWz48l6X9cNsxeA==
SPLICE_LINUX_X64_SHA512=OtpywXIof4d/eP7dhvt8q3hh5k65qCpE7YtTh9EmA9RqtPtFxksBaxWT3FjWHkqJ7RQm7JCKme2xIBVnBpAhHA==
SPLICE_LINUX_ARM64_SHA512=gJ4y/6sOgGooEkf1flpUUIt9u77T4oe7CBKzCEWXSeGwHyRH7jE3/v/lHFKtaGRF5OhW7sq+wbN3z7uCBQIkxQ==
HOIST_VERSION=0.3.0
HOIST_SHA512=0OO9wf3zQgSmZzGLUkLvjrdhQsUq1zGtyJ4CDi/EprxDmOFxvyxJfPpEDIez0xvwN9UNqhjwDw9x77GrFXeMVQ==
HOIST_LINUX_X64_SHA512=dfsuZovno5ZMtepOLDhYiLQLu9K0hTdAgVVsO4VhwKw6fWnH4PGE3Ks/sqnShT+ajSzN25pETEVV9euIZvxcag==
HOIST_LINUX_ARM64_SHA512=dFY+6R78093CTKpipt3I7c037oz2SDZ8cUgJjH00OXkbrdzTWgHqh7wytOs9/JF56aHW38K1ATS0L0jc21AmVg==
BERTH_VERSION=0.1.0
BERTH_SHA512=4V71F1YqcduupUm/yqc3HaK5/VMH6bD1PZa6xskA+84UiSs1UZRnkX7W+zoLPNizoT2CM1bVGmEtk2cjjYg3Eg==
BERTH_LINUX_X64_SHA512=3eaIWInNsevz8vPlkSN+QsPnf82ULEZJz2X4KFOsP3aQR9EanDBDxmm2+J+jEvUBHKxS3xfQMT7HqCO35TUysw==
BERTH_LINUX_ARM64_SHA512=sG6PA8qfOmThoXxL/3P+DSTnr8OL+5MieaTWBv9QfjzcC/ocITUHqi5xptPh2u+71ZY8SqpEcgE6dPmvmi5YXw==
# The bosun release this repo pins in .bosun/version.
BOSUN_VERSION=0.5.0

# Node 24 from NodeSource, unless it is already there (the keelstackhq tools ship through npm).
if ! node --version 2>/dev/null | grep -q "^v${NODE_MAJOR}\."; then
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi

# The image may put an older Node (/opt/node22/bin) before NodeSource's /usr/bin in PATH. Make Node 24 the
# `node` that resolves first, whatever the PATH order: link it into a directory that later shells put
# first (/etc/profile.d), and replace the older `node` that resolves today. Never fails: it warns.
NODE_BIN_DIR="${SETUP_NODE_BIN_DIR:-/usr/bin}"
NODE_LINK_DIR="${SETUP_NODE_LINK_DIR:-/usr/local/lib/bosun-node}"
NODE_PROFILE="${SETUP_NODE_PROFILE:-/etc/profile.d/bosun-node.sh}"
node_major_ok() { "$1" --version 2>/dev/null | grep -q "^v${NODE_MAJOR}\."; }
if ! node_major_ok "$(command -v node || echo node)"; then
  if node_major_ok "$NODE_BIN_DIR/node"; then
    first="$(command -v node || true)"
    {
      mkdir -p "$NODE_LINK_DIR"
      for b in node npm npx; do [ -e "$NODE_BIN_DIR/$b" ] && ln -sf "$NODE_BIN_DIR/$b" "$NODE_LINK_DIR/$b"; done
      printf 'export PATH=%q:"$PATH"\n' "$NODE_LINK_DIR" >"$NODE_PROFILE"
    } 2>/dev/null || echo "setup-script: could not link Node ${NODE_MAJOR} into $NODE_LINK_DIR or write $NODE_PROFILE" >&2
    if [ -n "$first" ] && [ "$first" != "$NODE_BIN_DIR/node" ]; then
      ln -sf "$NODE_BIN_DIR/node" "$first" 2>/dev/null ||
        echo "setup-script: could not replace $first with $NODE_BIN_DIR/node" >&2
    fi
  fi
  if ! node_major_ok "$(command -v node || echo node)"; then
    echo "setup-script: node resolves to $(command -v node || echo none) ($(node --version 2>/dev/null || echo unknown)), not Node ${NODE_MAJOR} at $NODE_BIN_DIR/node" >&2
  fi
fi

# pnpm 12 ships a native binary; its install.js puts it in place.
npm install -g "pnpm@${PNPM_VERSION}"
(cd "$(npm root -g)/pnpm" && node install.js) || true

# The keelstackhq tools, pinned, install only from npm tarballs that match the pinned sha512:
# each launcher and this machine's binary package, side by side. A mismatch or a failed install
# skips that tool with a warning (a failing setup script blocks every session).
tool_pack() {
  f="$(cd "$2" && npm pack --silent "$1")"
  got="$(node -e 'process.stdout.write(require("crypto").createHash("sha512").update(require("fs").readFileSync(process.argv[1])).digest("base64"))' "$2/$f")"
  if [ "$got" != "$3" ]; then echo "setup-script: $1 does not match its pinned sha512; skipping it" >&2; return 1; fi
  echo "$2/$f"
}
# install_tool <name> <version> <launcher sha512> <linux-x64 sha512> <linux-arm64 sha512>
install_tool() {
  case "$(uname -m)" in aarch64 | arm64) a=arm64 s="$5" ;; *) a=x64 s="$4" ;; esac
  t="$(mktemp -d)"
  if l="$(tool_pack "@keelstackhq/$1@$2" "$t" "$3")" && b="$(tool_pack "@keelstackhq/$1-linux-$a@$2" "$t" "$s")"; then
    # npm still reads the optional packages' metadata: a registry error must not stop the script.
    npm install -g --ignore-scripts --omit=optional "$l" "$b" ||
      echo "setup-script: $1 install failed; skipping $1" >&2
  fi
}
install_tool splice "$SPLICE_VERSION" "$SPLICE_SHA512" "$SPLICE_LINUX_X64_SHA512" "$SPLICE_LINUX_ARM64_SHA512"
install_tool hoist "$HOIST_VERSION" "$HOIST_SHA512" "$HOIST_LINUX_X64_SHA512" "$HOIST_LINUX_ARM64_SHA512"
install_tool berth "$BERTH_VERSION" "$BERTH_SHA512" "$BERTH_LINUX_X64_SHA512" "$BERTH_LINUX_ARM64_SHA512"
# bosun's integrity is not known when the channel is written (the pin is the channel's release
# or bosun_version), so bosun installs by version and npm checks the registry's integrity.
npm install -g --ignore-scripts "@keelstackhq/bosun@${BOSUN_VERSION}"

bosun --version
