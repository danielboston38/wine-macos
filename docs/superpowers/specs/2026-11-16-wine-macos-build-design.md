# wine-macos: self-contained Wine.app built from upstream

Date: 2026-11-16
Status: draft, awaiting approval

## Intent

Homebrew no longer ships Wine for macOS. Daniel wants his own Wine build for
macOS that he can keep current with upstream releases. Right now it is for
his own use, built on his Mac. Later he may publish it for other people, as
GitHub release downloads, from a Homebrew tap
(`danielboston38/homebrew-tap`), or both, and possibly signed once he joins
the Apple Developer Program.

The work is packaging, not Wine development. Upstream Wine is used
unmodified.

## Goals

- One command builds any upstream Wine release tag into a self-contained
  `Wine.app`: `./build.sh wine-11.22`.
- `Wine.app` runs on Daniel's Mac (Apple Silicon, macOS 27) with no Homebrew
  libraries needed at run time. All non-system libraries are inside the
  bundle.
- Both 64-bit and 32-bit Windows programs run (WoW64 mode).
- Rebuilding for a new release is quick and repeatable: dependencies are
  pinned and cached, so a new Wine tag only rebuilds Wine.
- The layout and script are ready for later CI, release and signing work,
  so going public adds steps on top and nothing gets rewritten.

## Non-goals (for now)

- GitHub Actions CI, GitHub releases, the Homebrew cask.
- Code signing with a Developer ID, and notarization.
- A GUI front-end for prefixes and bottles. Whisky was explored and dropped.
- Patching Wine, wine-staging, DXVK/D3DMetal, or game-specific tweaks.
- Native arm64 Wine (aarch64/arm64ec). Not mature for macOS yet. See Risks.

## Anti-goals

- A build that only works because of something on Daniel's machine, such as
  a Homebrew library path baked into a binary. That would make "later" a
  rewrite.
- A fork of Wine to maintain. The source stays upstream.

## Constraints

- Host: Apple Silicon, macOS 27.2, Xcode SDK 27.2, Apple clang 21.
- Wine's macOS Unix side is x86_64 only, so Wine runs under Rosetta 2. The
  Unix side and every bundled library must be built for x86_64
  (`clang -arch x86_64`, run under `arch -x86_64`).
- The PE (Windows) side is built with MinGW for i386 and x86_64:
  `--enable-archs=i386,x86_64`.
- Upstream source: `https://gitlab.winehq.org/wine/wine.git`, cloned at
  `~/build/wine` with all tags. No fork is needed (winehq GitLab blocks new
  projects for new accounts anyway).
- Packaging repo: `github.com/danielboston38/wine-macos` (public), local
  clone `~/build/wine-macos`.

## Approaches considered

1. **Homebrew source formula.** Users compile Wine themselves. Rejected:
   it needs a cross-compiler and x86_64 libraries on every machine, takes an
   hour or more to build, and fails in different ways on different
   machines.
2. **Self-contained app bundle built by a repo script (chosen).** Build
   x86_64 dependencies from pinned sources, build Wine against them, and
   assemble `Wine.app` with everything inside. It runs locally now. CI,
   releases and the cask later run the same script.
3. **Cask pointing at a third party's builds (Gcenx).** Rejected: it
   depends on someone else and does not give Daniel his own build.

Within approach 2, building against an x86_64 Homebrew in `/usr/local` was
also considered and rejected. It is not installed, it bakes Homebrew paths
into the binaries, and it does not carry over to CI or to other people's
Macs.

## Design

### Repo layout (`wine-macos`)

```
build.sh               entry point: ./build.sh <wine-tag> [--clean]
deps/
  manifest.sh          pinned name, version, URL, sha256 for each dependency
  build-deps.sh        builds every dependency into $DEPS_PREFIX (x86_64)
scripts/
  build-wine.sh        configure, make and install Wine into a staging prefix
  make-bundle.sh       assemble Wine.app, rewrite library paths, ad-hoc sign
  launcher/            Contents/MacOS launcher + Info.plist template
docs/
work/                  (gitignored) sources, build dirs, caches
dist/                  (gitignored) output Wine-<version>.app
```

### Build steps

1. **Prerequisites check.** Rosetta, Xcode CLT, `mingw-w64` (Homebrew,
   gives `i686-` and `x86_64-w64-mingw32-gcc`), bison, flex, meson, ninja,
   cmake, pkg-config. Exit with a clear message naming anything missing.
2. **Dependencies.** For each manifest entry, download, verify the sha256,
   and build for x86_64 into `work/deps/prefix`, with
   `MACOSX_DEPLOYMENT_TARGET` set. Skip anything that is already built at
   the same version.
3. **Wine.** `git -C ~/build/wine` worktree or checkout of the requested
   tag into `work/wine-src`. Configure out of tree, under `arch -x86_64`,
   with `--enable-archs=i386,x86_64`, `--prefix=` the staging dir, and
   `PKG_CONFIG_PATH` pointed only at `work/deps/prefix`. Then
   `make -j$(sysctl -n hw.ncpu)` and `make install`. ccache is used if it is
   present.
4. **Check configure's results.** Fail the build if a required feature is
   missing from the configure summary (FreeType, GnuTLS, Vulkan). Wine would
   otherwise build fine and only break later at run time.
5. **Bundle.** Lay out `Wine.app/Contents/{MacOS,Resources}`. Wine goes
   under `Contents/Resources/wine/` and the dependency dylibs under
   `Contents/Resources/wine/lib/`. Rewrite install names and dependencies
   with `install_name_tool` so no path points outside the bundle. Verify
   with an `otool -L` scan that fails on any `/opt/homebrew`, `/usr/local`
   or `work/` path.
6. **Ad-hoc sign** (`codesign -s - --deep`). Free and needs no account. It
   is the hook where a Developer ID identity goes later.

### Dependencies (initial set)

Required for a usable Wine: FreeType (with libpng, bzip2), GnuTLS (with
nettle, gmp, libtasn1), MoltenVK + Vulkan loader (Vulkan, and Direct3D
through wined3d's Vulkan renderer), SDL2 (game controllers).

Deferred, can be added to the manifest later: GStreamer (media playback,
large), SANE, libpcap. CUPS, OpenCL, CoreAudio and the Mac driver use
system frameworks and need nothing bundled.

### Runtime and launcher

- `Contents/MacOS/wine` is a small launcher. It sets
  `DYLD_FALLBACK_LIBRARY_PATH` to the bundled `lib/`, because Wine
  `dlopen`s some libraries by leaf name, and runs the bundled `wine`.
  `WINEPREFIX` defaults to `~/.wine` as usual.
- Double-clicking the app opens a Terminal session with `wine` and
  `winecfg` on the PATH (exact behavior is the builder's call). Command-line
  use is `/Applications/Wine.app/Contents/MacOS/wine program.exe`, or a
  symlink in `~/bin`.
- wine-mono and wine-gecko are not bundled at first. Wine offers to download
  them when a prefix is created.

## Later (out of scope, designed for)

- **CI:** a GitHub Actions workflow on a macOS runner runs `build.sh` for a
  tag, caching `work/deps`.
- **Releases:** upload `Wine-<version>.tar.xz` to GitHub Releases. If it is
  unsigned, users clear quarantine (`xattr -dr com.apple.quarantine`) or
  right-click and choose Open.
- **Cask:** `danielboston38/homebrew-tap`, `wine-stable` and/or
  `wine-devel`.
- **Signing:** replace the ad-hoc identity with Developer ID, add hardened
  runtime entitlements, notarize, staple.

## Risks

- **Rosetta's future.** Apple has said Rosetta will be reduced after
  macOS 27 to a subset aimed at older games. x86_64 Wine depends on it. Keep
  an eye on upstream native arm64 macOS work; that would be a separate
  project.
- **Toolchain drift.** New Xcode or SDK versions sometimes break Wine or
  dependency builds. Pinned dependency versions limit this to Wine itself.

## Calls made by Claude (please check)

- Ship upstream Wine unmodified, any tag (stable or devel) passed on the
  command line.
- Build dependencies from source rather than from x86_64 Homebrew.
- MinGW from Homebrew `mingw-w64` (gcc) as the PE compiler.
- `MACOSX_DEPLOYMENT_TARGET=12.0`, so the app runs on older Macs if it is
  shared later.
- Initial dependency set as listed, with GStreamer deferred.
- wine-mono/gecko are downloaded on demand, not bundled.
- Ad-hoc signing now, as the hook for real signing later.
- Shell scripts (bash), not a Makefile or Python, to keep them easy to read
  and easy to run in CI.

## Left to the builder

Exact dependency versions and configure flags for each, the launcher's
double-click behavior, how the Wine tag is checked out (worktree or plain
checkout), and the exact configure-summary checks.
