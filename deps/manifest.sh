#!/bin/bash
# Pinned dependencies, in build order. Source this file.
# To bump one: change VERSION and URL, then put the new `shasum -a 256` in SHA256.
# shellcheck disable=SC2034

DEPS_ORDER="libpng gmp nettle libtasn1 gnutls freetype sdl2 moltenvk"

LIBPNG_VERSION=1.6.59
LIBPNG_URL="https://download.sourceforge.net/libpng/libpng-$LIBPNG_VERSION.tar.xz"
LIBPNG_SHA256=d80dd2a38a37f803cb9b6ac7b14bd6e74ddc3b654780a8380bdf93523fdb4389

GMP_VERSION=6.3.0
GMP_URL="https://gmplib.org/download/gmp/gmp-$GMP_VERSION.tar.xz"
GMP_SHA256=a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898

NETTLE_VERSION=4.0
NETTLE_URL="https://ftp.gnu.org/gnu/nettle/nettle-$NETTLE_VERSION.tar.gz"
NETTLE_SHA256=3addbc00da01846b232fb3bc453538ea5468da43033f21bb345cb1e9073f5094

LIBTASN1_VERSION=4.21.0
LIBTASN1_URL="https://ftp.gnu.org/gnu/libtasn1/libtasn1-$LIBTASN1_VERSION.tar.gz"
LIBTASN1_SHA256=1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87

GNUTLS_VERSION=3.8.13
GNUTLS_URL="https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-$GNUTLS_VERSION.tar.xz"
GNUTLS_SHA256=ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e

FREETYPE_VERSION=2.15.0
FREETYPE_URL="https://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.xz"
FREETYPE_SHA256=93cd47eb719c325107f2d3cf087d06299e944c3b48a40b55537302304dea1dd5

SDL2_VERSION=2.32.10
SDL2_URL="https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/SDL2-$SDL2_VERSION.tar.gz"
SDL2_SHA256=5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165

MOLTENVK_VERSION=1.4.2
MOLTENVK_URL="https://github.com/KhronosGroup/MoltenVK/releases/download/v$MOLTENVK_VERSION/MoltenVK-macos.tar"
MOLTENVK_SHA256=f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e
