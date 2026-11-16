#!/bin/bash
# Checksum-verified downloads. Source this file.

# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# dep_var <name> <FIELD>: echo e.g. GNUTLS_VERSION for "gnutls VERSION".
dep_var() {
    local var
    var="$(echo "$1" | tr '[:lower:]' '[:upper:]')_$2"
    echo "${!var:-}"
}

_sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# fetch_source <url> <sha256> <dest_file>
fetch_source() {
    local url=$1 want=$2 dest=$3 got
    if [ -f "$dest" ] && [ "$(_sha256 "$dest")" = "$want" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    log "downloading $url"
    curl -fL --retry 3 -sS -o "$dest.part" "$url" || { rm -f "$dest.part"; die "download failed: $url"; }
    got=$(_sha256 "$dest.part")
    if [ "$got" != "$want" ]; then
        rm -f "$dest.part"
        die "checksum mismatch for $url: expected $want got $got"
    fi
    mv "$dest.part" "$dest"
}
