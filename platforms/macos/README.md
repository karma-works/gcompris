# GCompris macOS Build & Distribution

## Local build

Pre-requisites:
- Xcode Command Line Tools (`xcode-select --install`)
- Qt 6.8+ for macOS from the Qt online installer
- `brew install p7zip gettext openssl@3`
- CMake 3.16+

```sh
git submodule update --init --recursive

mkdir build-macos && cd build-macos

cmake -DCMAKE_BUILD_TYPE=Release \
      -DQt6_DIR=~/Qt/6.8.3/macos/lib/cmake/Qt6 \
      -DBUILD_STANDALONE=ON \
      -DCOMPRESSED_AUDIO=aac \
      -DQML_BOX2D_MODULE=submodule \
      -DPACKAGE_GCOMPRIS=ON \
      ..

# Download pre-converted AAC audio bundles (avoids needing ffmpeg)
make DlAndInstallBundledConvertedOggs

make -j$(sysctl -n hw.logicalcpu)
make package
```

The DMG is at `build-macos/gcompris-qt-X.Y-Darwin.dmg`.

## Unofficial Homebrew distribution

KDE does not currently publish a macOS build for recent versions.
This directory contains an unofficial distribution setup using:
- GitHub Actions to build and ad-hoc sign the DMG (no Apple Developer account needed)
- A personal Homebrew tap for easy installation

### How it works

1. CI (`.github/workflows/macos-release.yml`) triggers on a version tag push.
2. It builds arm64 and x86_64 DMGs, ad-hoc signs them, and publishes them
   as a GitHub Release on this fork.
3. The Homebrew cask (`platforms/macos/gcompris.rb`) points at those releases
   and strips the quarantine flag on install so macOS Gatekeeper doesn't block
   the un-notarized app.

### One-time setup

**Step 1 — Fork GCompris to your GitHub account**

Fork this repo to `github.com/karma-works/gcompris`.
The CI workflow is already present at `.github/workflows/macos-release.yml`.
No secrets are required.

**Step 2 — Create your Homebrew tap**

```sh
# Create a new repo named homebrew-gcompris on GitHub, then:
mkdir homebrew-gcompris && cd homebrew-gcompris
git init
mkdir Casks
cp /path/to/gcompris/platforms/macos/gcompris.rb Casks/gcompris.rb
# Replace karma-works in the url field with your actual GitHub username
```

**Step 3 — Build the first release**

Push a version tag to your fork to trigger the CI:

```sh
git tag v26.1
git push origin v26.1
```

Wait ~60 minutes for both jobs to finish. The GitHub Release will appear at
`github.com/karma-works/gcompris/releases/tag/v26.1` with two DMG files.

**Step 4 — Fill in the SHA256 hashes**

```sh
# Download the DMGs from the release, then:
shasum -a 256 gcompris-qt-26.1-macOS-arm64.dmg
shasum -a 256 gcompris-qt-26.1-macOS-x86_64.dmg
```

Update the `sha256` values in `Casks/gcompris.rb`, commit, and push the tap:

```sh
cd homebrew-gcompris
git add Casks/gcompris.rb
git commit -m "Add gcompris 26.1"
git remote add origin git@github.com:karma-works/homebrew-gcompris.git
git push -u origin main
```

**Step 5 — Test the cask**

```sh
brew install --cask karma-works/gcompris/gcompris
```

GCompris should open without any Gatekeeper warning.

### Updating to a new version

1. Push a new tag to your GCompris fork → CI builds and uploads the DMGs.
2. Compute the new SHA256 hashes.
3. Update `version` and `sha256` in `Casks/gcompris.rb` in your tap repo.
4. Push the tap change — users get the update on their next `brew upgrade`.

### Note on Gatekeeper

The DMGs are ad-hoc signed but not notarized (no Apple Developer account
required). The cask's `preflight` block removes the quarantine attribute
automatically during `brew install`, so users should not see any Gatekeeper
warning. If someone installs the DMG manually (without Homebrew), they can go
to System Settings → Privacy & Security → Open Anyway.
