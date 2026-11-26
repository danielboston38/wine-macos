# wine-macos

Build scripts that turn an upstream [Wine](https://www.winehq.org) release into a
self-contained `Wine.app` for macOS on Apple Silicon. Wine itself is not patched.

The app holds Wine and every library it needs, so it does not need Homebrew at run time.
It runs 64-bit and 32-bit Windows programs. Wine is built for Intel (x86_64), so it runs
through Rosetta 2.

## Prerequisites

- An Apple Silicon Mac with macOS 12 or later.
- Rosetta 2: `softwareupdate --install-rosetta`
- Xcode Command Line Tools: `xcode-select --install`
- Homebrew build tools: `brew install mingw-w64 bison ninja cmake pkg-config`
- A clone of upstream Wine with its tags at `~/build/wine` (or set `WINE_GIT`):

  ```sh
  git clone https://gitlab.winehq.org/wine/wine.git ~/build/wine
  ```

`./build.sh` checks all of these and lists everything that is missing.

## Build

```sh
./build.sh wine-11.22
```

The result is `dist/Wine-11.22.app`. The first build downloads and compiles the
dependencies (pinned in `deps/manifest.sh`, with checksums), then compiles Wine. That takes
a while. Later builds reuse the dependencies and the configured Wine build tree, so they
compile only what changed. `./build.sh wine-11.22 --clean` configures and compiles Wine
again from scratch, but keeps the dependencies.

Any Wine tag works. To list them in version order, newest last:

```sh
git -C ~/build/wine tag -l 'wine-[0-9]*.*' --sort=v:refname | tail
```

Run `git -C ~/build/wine fetch --tags` to get new releases.

## Install

Drag `dist/Wine-11.22.app` into `/Applications`. The app is signed ad hoc, not by a
registered Apple developer. A copy that you built yourself opens without warnings.

## Use

Double-click `Wine.app` to open a Terminal window where `wine` is ready to use:

```sh
wine winecfg
wine ~/Downloads/setup.exe
```

From any other shell, call the launcher inside the app:

```sh
/Applications/Wine-11.22.app/Contents/MacOS/wine notepad
```

To type plain `wine` in any shell, link the launcher onto your PATH:

```sh
ln -s /Applications/Wine-11.22.app/Contents/MacOS/wine /usr/local/bin/wine
```

Always start Wine through this launcher, never through `Contents/Resources/wine/bin/wine`.
Wine loads FreeType (fonts), GnuTLS (secure connections) and MoltenVK (Vulkan) by file name
only. The launcher tells macOS to look for those files inside the app. Without it, text,
HTTPS and Vulkan can quietly fail.

When Wine sets up a new prefix (`~/.wine` by default), it asks whether to download
Wine Mono (.NET) and Wine Gecko (HTML). Programs that need them will not work without them.

## Tests

```sh
tests/run.sh                        # fast unit tests
DEPS_IT=1   tests/run.sh deps       # build the dependencies and check them
WINE_IT=1   tests/run.sh wine       # build Wine and check it
BUNDLE_IT=1 tests/run.sh bundle     # assemble the app and check it
E2E=1       tests/run.sh e2e        # full build, then run 64- and 32-bit programs
```

## Not yet

- Prebuilt downloads on GitHub Releases.
- A Homebrew cask in `danielboston38/homebrew-tap`.
- Developer ID signing and notarization. `SIGN_IDENTITY` is ready for that; the default is
  ad hoc. Until then, a downloaded copy is quarantined by macOS, and the user must clear the
  quarantine flag before it opens.
