# Self-contained Wine.app Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `./build.sh wine-11.22` turns any upstream Wine tag into a self-contained, ad-hoc-signed `dist/Wine-11.22.app` that runs 64-bit and 32-bit Windows programs on Apple Silicon via Rosetta.

**Architecture:** Four bash stages, each its own script that can run alone: fetch+build pinned x86_64 dependencies into `work/deps/prefix` (cached by stamp files), build a Wine tag against only that prefix into `work/stage/<tag>`, assemble and fix up `Wine.app`, and an orchestrator `build.sh`. Shared helpers live in `scripts/lib.sh`. Tests are plain bash scripts with a tiny assert helper (no new tool dependency).

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), Apple clang `-arch x86_64` under `arch -x86_64`, mingw-w64 GCC (i686 + x86_64), autotools/cmake/meson for dependencies, `install_name_tool`, `otool`, `vtool`, `lipo`, `codesign`, shellcheck.

**Spec:** `docs/superpowers/specs/2026-11-16-wine-macos-build-design.md`

## Global Constraints

- Wine source: `$WINE_GIT` (default `~/build/wine`), upstream `https://gitlab.winehq.org/wine/wine.git`, unmodified.
- Unix side and every bundled dylib: x86_64 only. PE side: `--enable-archs=i386,x86_64`.
- `MACOSX_DEPLOYMENT_TARGET=12.0` for everything built.
- `PKG_CONFIG_PATH`/`PKG_CONFIG_LIBDIR` point only at `work/deps/prefix/lib/pkgconfig`; no `/opt/homebrew` or `/usr/local` headers or libs may be used by dependency or Wine builds.
- Required Wine features (build fails without them): FreeType, GnuTLS, Vulkan (MoltenVK), SDL2.
- Dependencies: libpng, gmp, nettle, libtasn1, gnutls, freetype, SDL2 (built from source), MoltenVK (prebuilt Khronos release, thinned to x86_64). zlib and bzip2 come from the macOS SDK. Each pinned in `deps/manifest.sh` with version, URL, sha256.
- No path inside the finished bundle may reference `/opt/homebrew`, `/usr/local`, or the repo's `work/` dir.
- Bundle signing: ad-hoc (`codesign -s -`), identity overridable via `SIGN_IDENTITY` env var (hook for Developer ID later).
- All scripts: `#!/bin/bash`, `set -euo pipefail`, shellcheck-clean, every path quoted.
- `work/` and `dist/` are gitignored.

## Review Focus

- **Typo'd or nonexistent tag** (`./build.sh wine-11.99`): fail in seconds with "unknown Wine tag", before any dependency or Wine compile. Test in Task 4.
- **Interrupted or failed dependency build, then rerun:** a half-built dependency must never be treated as done. The stamp is written only after a successful install. Test in Task 3.
- **Repo or app path containing spaces** (`~/My Builds/wine-macos`, `/Applications/Wine Devel.app`): everything still works. Tests in Tasks 2 and 5.
- **App moved or renamed after building:** the launcher resolves its own location at run time, not the build-time path. Test in Task 5.
- **Run from a normal arm64 Terminal:** the scripts force x86_64 themselves, and the output is x86_64 no matter which shell started them. Tests in Tasks 3 and 4 assert the arch of the outputs.

---

### Task 1: Scaffold, shared helpers, prerequisite check

**Files:**
- Create: `.gitignore`, `scripts/lib.sh`, `tests/assert.sh`, `tests/run.sh`, `tests/test_lib.sh`

**Interfaces:**
- Produces (in `scripts/lib.sh`, sourced by every script):
  - `REPO_ROOT`, `WORK_DIR="$REPO_ROOT/work"`, `DEPS_PREFIX="$WORK_DIR/deps/prefix"`, `DIST_DIR="$REPO_ROOT/dist"`, `WINE_GIT="${WINE_GIT:-$HOME/build/wine}"`, `export MACOSX_DEPLOYMENT_TARGET=12.0`
  - `log <msg...>`: prints `==> msg` to stderr
  - `die <msg...>`: prints `error: msg` to stderr, exits 1
  - `check_prereqs`: dies listing **every** missing item at once (`missing: mingw-w64 (brew install mingw-w64), meson`). It checks Rosetta (`arch -x86_64 /usr/bin/true`), `xcrun`, `i686-w64-mingw32-gcc`, `x86_64-w64-mingw32-gcc`, `bison`, `flex`, `meson`, `ninja`, `cmake`, `pkg-config`, `autoreconf`, `git`, `curl`, `shasum`.
  - `x86_env`: exports `CC="clang -arch x86_64"`, `CXX="clang++ -arch x86_64"`, `CFLAGS/CXXFLAGS="-O2 -mmacosx-version-min=12.0"`, `CPPFLAGS="-I$DEPS_PREFIX/include"`, `LDFLAGS="-L$DEPS_PREFIX/lib -mmacosx-version-min=12.0"`, `PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig"`, unsets `PKG_CONFIG_PATH`, and puts `$DEPS_PREFIX/bin` first on PATH.
  - `run_x86 <cmd...>`: `arch -x86_64 "$@"`
- Produces (in `tests/assert.sh`): `assert_eq <expected> <actual> <msg>`, `assert_contains <haystack> <needle> <msg>`, `assert_fails <msg> <cmd...>`, `assert_file <path>`. Each prints `ok`/`FAIL` and records failure. `tests/run.sh [pattern]` runs every `tests/test_*.sh` matching the pattern and exits non-zero if any fail.

- [ ] **Step 1: Write failing tests** in `tests/test_lib.sh`:
  - `check_prereqs` with `PATH=/usr/bin:/bin` fails and its stderr contains both `mingw-w64` and `meson` (all missing items reported together).
  - `check_prereqs` with the real PATH succeeds.
  - `die "boom"` exits 1 with stderr `error: boom`.
  - After `x86_env`, `$PKG_CONFIG_LIBDIR` == `$DEPS_PREFIX/lib/pkgconfig` and `PKG_CONFIG_PATH` is unset.
- [ ] **Step 2:** `tests/run.sh lib` → FAIL (lib.sh missing).
- [ ] **Step 3:** Implement `scripts/lib.sh`, `tests/assert.sh`, `tests/run.sh`. Write `.gitignore` with `work/` and `dist/`.
- [ ] **Step 4:** `tests/run.sh lib` → all ok. `shellcheck scripts/*.sh tests/*.sh` → no output.
- [ ] **Step 5:** Commit `feat: scaffold, shared helpers, prerequisite check`.

### Task 2: Dependency manifest and verified fetch

**Files:**
- Create: `deps/manifest.sh`, `scripts/fetch.sh`, `tests/test_fetch.sh`

**Interfaces:**
- Consumes: `lib.sh` (`die`, `log`, `WORK_DIR`).
- Produces:
  - `deps/manifest.sh` defines `DEPS_ORDER="libpng gmp nettle libtasn1 gnutls freetype sdl2 moltenvk"`. For each name it defines `<NAME>_VERSION`, `<NAME>_URL`, `<NAME>_SHA256` (uppercase, e.g. `GNUTLS_VERSION`). Use the latest stable release of each at implementation time. Compute each sha256 with `shasum -a 256` from the official download (MoltenVK: the `MoltenVK-macos.tar` asset of the KhronosGroup GitHub release) and write it into the manifest.
  - `fetch_source <url> <sha256> <dest_file>`: downloads to `<dest_file>.part`, verifies the sha256, then renames to `<dest_file>`. On a mismatch it deletes the `.part` file and dies with `checksum mismatch for <url>: expected X got Y`. If `<dest_file>` already exists with the right hash, it skips the download.
  - `dep_var <name> <FIELD>`: echoes e.g. `dep_var gnutls VERSION` → value of `GNUTLS_VERSION`.

- [ ] **Step 1: Write failing tests** using a local fixture (`file://` URL to a temp file), in a temp dir **whose path contains a space**:
  - correct sha → `<dest>` exists, no `.part` left.
  - wrong sha → command fails, stderr contains `checksum mismatch`, neither `<dest>` nor `<dest>.part` exists.
  - second call with existing good file and an unreachable URL still succeeds (cache hit).
  - every name in `DEPS_ORDER` has non-empty `VERSION`, `URL`, and a 64-hex-char `SHA256`.
- [ ] **Step 2:** `tests/run.sh fetch` → FAIL.
- [ ] **Step 3:** Implement `fetch.sh` (`curl -fL --retry 3`) and fill in `manifest.sh`.
- [ ] **Step 4:** `tests/run.sh fetch` → ok; shellcheck clean.
- [ ] **Step 5:** Commit `feat: pinned dependency manifest and checksum-verified fetch`.

### Task 3: Build x86_64 dependencies

**Files:**
- Create: `deps/build-deps.sh`, `tests/test_deps.sh`

**Interfaces:**
- Consumes: `lib.sh` (`x86_env`, `run_x86`, `DEPS_PREFIX`), `manifest.sh`, `fetch_source`.
- Produces:
  - `deps/build-deps.sh [name...]`: builds the named deps (default: all of `DEPS_ORDER`, in order) into `$DEPS_PREFIX`. Sources go to `work/deps/src/<name>-<version>`, tarballs to `work/deps/dl/`. After a successful install it writes the stamp `work/deps/stamps/<name>-<version>`. If the stamp exists, it logs `<name> <version> up to date` and skips.
  - `build_dep_<name>` functions, one per dependency. Pinned decisions:
    - autotools deps: `./configure --host=x86_64-apple-darwin --prefix="$DEPS_PREFIX" --enable-shared --disable-static`, run via `run_x86`.
    - **gmp:** always pass the explicit `--host=x86_64-apple-darwin`. Never let it detect the CPU, because under Rosetta it would tune for a CPU the user may not have.
    - **nettle:** `--disable-openssl --disable-documentation`.
    - **gnutls:** `--with-included-unistring --without-p11-kit --without-idn --without-zstd --without-brotli --disable-doc --disable-tests --disable-tools --disable-cxx`.
    - **freetype:** `--with-png=yes --with-zlib=yes --with-bzip2=yes --with-harfbuzz=no --with-brotli=no`.
    - **sdl2:** cmake with `-DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" -DSDL_STATIC=OFF`.
    - **moltenvk:** no compile. Extract the release, `lipo -thin x86_64` its `libMoltenVK.dylib` into `$DEPS_PREFIX/lib/`, and set its id with `install_name_tool -id "$DEPS_PREFIX/lib/libMoltenVK.dylib"`. Wine ships its own Vulkan headers, so no headers are needed.

- [ ] **Step 1: Write failing tests:**
  - **Interrupted build is not cached:** with a stub `build_dep_fake` that fails, `build-deps.sh fake` fails and `work/deps/stamps/fake-*` does not exist.
  - Integration (`DEPS_IT=1` gate, since it takes minutes): after `deps/build-deps.sh`:
    - every `*.dylib` in `$DEPS_PREFIX/lib` (not symlinks) → `lipo -archs` == `x86_64`
    - every one → `vtool -show-build` minos ≤ `12.0`
    - `otool -L` of each contains no `/opt/homebrew` or `/usr/local`
    - `pkg-config --exists gnutls freetype2 sdl2` with `PKG_CONFIG_LIBDIR` from `x86_env` succeeds
    - second run completes in under 10 s and prints `up to date` for all 8
- [ ] **Step 2:** `tests/run.sh deps` (and `DEPS_IT=1 tests/run.sh deps`) → FAIL.
- [ ] **Step 3:** Implement `build-deps.sh` with the decisions above. Write the stamp as the last line of each successful build, never before.
- [ ] **Step 4:** Both test runs → ok, started from a normal arm64 Terminal. Shellcheck clean.
- [ ] **Step 5:** Commit `feat: build pinned x86_64 dependencies with caching`.

### Task 4: Build Wine for a tag

**Files:**
- Create: `scripts/build-wine.sh`, `tests/test_wine.sh`, `tests/fixtures/config_ok.h`, `tests/fixtures/config_missing_gnutls.h`

**Interfaces:**
- Consumes: `lib.sh`, a built `$DEPS_PREFIX`.
- Produces:
  - `scripts/build-wine.sh <tag>` creates the `$WINE_GIT` worktree at `work/wine-src/<tag>` (`git worktree add --detach`; reused if present). It builds out of tree in `work/wine-build/<tag>` and installs to `work/stage/<tag>`. It prints the stage path on stdout as its last line.
  - `validate_tag <tag>`: dies `unknown Wine tag: <tag> (try: git -C "$WINE_GIT" tag -l 'wine-*')` unless `git -C "$WINE_GIT" rev-parse -q --verify "refs/tags/<tag>"` succeeds. This is called first, before anything slow.
  - `check_wine_config <config.h>`: dies listing every missing item if any of `SONAME_LIBFREETYPE`, `SONAME_LIBGNUTLS`, `SONAME_LIBVULKAN`, `SONAME_LIBSDL2` is not `#define`d. Message: `Wine configured without: GnuTLS, ...`.
  - configure call (via `run_x86`, after `x86_env`): `--prefix="$WORK_DIR/stage/<tag>" --enable-archs=i386,x86_64 --without-x --disable-tests`. If ccache is on PATH, CC is `ccache clang -arch x86_64`. Then `make -j"$(sysctl -n hw.ncpu)"` and `make install`.

- [ ] **Step 1: Write failing tests:**
  - `validate_tag wine-11.99` fails within 5 s, stderr contains `unknown Wine tag`. `validate_tag wine-11.22` succeeds.
  - `check_wine_config tests/fixtures/config_ok.h` succeeds. `config_missing_gnutls.h` fails with `GnuTLS` in stderr.
  - Integration (`WINE_IT=1`): `build-wine.sh wine-11.22` →
    - `lipo -archs work/stage/wine-11.22/bin/wine` == `x86_64`
    - `work/stage/wine-11.22/lib/wine/i386-windows/kernel32.dll` and `.../x86_64-windows/kernel32.dll` exist
    - `DYLD_FALLBACK_LIBRARY_PATH="$DEPS_PREFIX/lib" work/stage/wine-11.22/bin/wine --version` prints `wine-11.22`
- [ ] **Step 2:** `tests/run.sh wine` → FAIL.
- [ ] **Step 3:** Implement `build-wine.sh` and the two fixtures (minimal `config.h` excerpts).
- [ ] **Step 4:** `tests/run.sh wine` and `WINE_IT=1 tests/run.sh wine` → ok. Shellcheck clean.
- [ ] **Step 5:** Commit `feat: build a Wine tag against bundled deps`.

### Task 5: Assemble, fix up and sign Wine.app

**Files:**
- Create: `scripts/make-bundle.sh`, `scripts/launcher/wine`, `scripts/launcher/wine-shell.command`, `scripts/launcher/Info.plist.in`, `tests/test_bundle.sh`

**Interfaces:**
- Consumes: `lib.sh`, `work/stage/<tag>`, `$DEPS_PREFIX/lib`.
- Produces:
  - `scripts/make-bundle.sh <tag> <stage_dir>` writes `dist/Wine-<version>.app`, where `<version>` is the tag minus `wine-`. An existing app at that path is replaced. The script prints the app path last.
  - Layout: `Contents/Info.plist` (from the template, with `@VERSION@` substituted, `CFBundleIdentifier=io.github.danielboston38.wine`, `CFBundleExecutable=wine`, `LSMinimumSystemVersion=12.0`), `Contents/MacOS/wine` (launcher), `Contents/Resources/wine/` (copy of stage), `Contents/Resources/wine/lib/` (deps' dylibs and their versioned symlinks, copied with `cp -a`), `Contents/Resources/wine-shell.command`.
  - Fix-up: for each copied dylib, set the id to `@rpath/<leaf>`. In every Mach-O under `Contents/` (dylibs, `.so` files in `lib/wine/x86_64-unix/`, `bin/*`), rewrite each dependency under `$DEPS_PREFIX/lib` to `@rpath/<leaf>`, and add an rpath pointing at `Resources/wine/lib` relative to `@loader_path`.
  - `find_foreign_paths <app>`: prints each `file: path` where `otool -L` or `otool -l` (LC_RPATH) shows `/opt/homebrew`, `/usr/local`, or `$WORK_DIR`. Exits 1 if it found any. `make-bundle.sh` calls it and dies on a hit.
  - Sign last: `codesign --force --deep -s "${SIGN_IDENTITY:--}" <app>`.
  - Launcher `Contents/MacOS/wine`: resolves its own directory at run time (`cd "$(dirname "$0")" && pwd -P`) and sets `WINE_ROOT=<app>/Contents/Resources/wine`, `DYLD_FALLBACK_LIBRARY_PATH="$WINE_ROOT/lib:/usr/lib"`, and `PATH="$WINE_ROOT/bin:$PATH"`. With arguments it runs `exec "$WINE_ROOT/bin/wine" "$@"`. With no arguments (double-click) it runs `open -a Terminal "<app>/Contents/Resources/wine-shell.command"`. That script sets the same env vars from its own location, prints `Wine <version> ready: try 'wine winecfg'`, then `exec "$SHELL" -l`.

- [ ] **Step 1: Write failing tests:**
  - `find_foreign_paths`: compile a fixture dylib with `clang -arch x86_64 -dynamiclib -Wl,-rpath,/opt/homebrew/lib` into a fake app dir. The function exits 1 and prints its path. A clean fixture exits 0.
  - Integration (`BUNDLE_IT=1`, needs Task 4's stage):
    - `make-bundle.sh wine-11.22 work/stage/wine-11.22` → `find_foreign_paths` exits 0. `codesign --verify --deep --strict dist/Wine-11.22.app` succeeds.
    - **Moved and renamed with spaces:** `cp -R dist/Wine-11.22.app "$TMP/My Apps/Wine Devel.app"`, then `"$TMP/My Apps/Wine Devel.app/Contents/MacOS/wine" --version` prints `wine-11.22`, run with `env -i HOME="$HOME" PATH=/usr/bin:/bin`, so no Homebrew is on PATH and no DYLD vars are inherited.
    - `plutil -extract CFBundleShortVersionString raw` → `11.22`.
- [ ] **Step 2:** `tests/run.sh bundle` → FAIL.
- [ ] **Step 3:** Implement `make-bundle.sh` and the launcher files.
- [ ] **Step 4:** `tests/run.sh bundle` and `BUNDLE_IT=1 tests/run.sh bundle` → ok. Shellcheck clean.
- [ ] **Step 5:** Commit `feat: assemble self-contained, ad-hoc signed Wine.app`.

### Task 6: Orchestrator, end-to-end smoke test, README

**Files:**
- Create: `build.sh`, `tests/test_e2e.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: `check_prereqs`, `validate_tag`, `deps/build-deps.sh`, `scripts/build-wine.sh`, `scripts/make-bundle.sh`.
- Produces: `./build.sh <tag> [--clean]`. With no tag it prints usage and exits 2. It runs, in order: `check_prereqs` → `validate_tag` → build-deps → build-wine → make-bundle, then prints `Built: <app path>`. `--clean` removes `work/wine-build/<tag>` and `work/stage/<tag>` first (never `work/deps`).

- [ ] **Step 1: Write failing tests:**
  - `./build.sh` (no args) exits 2 with `usage:` in its output.
  - `./build.sh wine-11.99` fails within 5 s with `unknown Wine tag`.
  - E2E (`E2E=1`): `./build.sh wine-11.22`. Then, with a fresh `WINEPREFIX="$TMP/prefix"` and `WINEDEBUG=-all`, through the app's launcher under `env -i`:
    - `wine wineboot -i` exits 0
    - `wine cmd /c echo hello64` output contains `hello64`
    - `wine 'C:\windows\syswow64\cmd.exe' /c echo hello32` output contains `hello32` (32-bit via WoW64)
    - `wineserver -k` at the end
- [ ] **Step 2:** `tests/run.sh e2e` → FAIL.
- [ ] **Step 3:** Implement `build.sh`. Rewrite `README.md`: what this is, prerequisites (`brew install mingw-w64 meson ninja cmake` plus Rosetta), `./build.sh wine-11.22`, how to install (drag to Applications), command-line use, running the tests, and a "Not yet" section covering releases, cask and signing.
- [ ] **Step 4:** `tests/run.sh` (all unit tests) and `E2E=1 tests/run.sh e2e` → ok. Shellcheck clean.
- [ ] **Step 5:** Commit `feat: build.sh orchestrator, e2e smoke test, README`.
