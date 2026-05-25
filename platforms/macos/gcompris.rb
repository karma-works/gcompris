# Reference copy — canonical lives in your tap repo at:
#   github.com/karma-works/homebrew-gcompris/Casks/gcompris.rb
#
# Update this file and the tap after each new GitHub Release is published.
cask "gcompris" do
  arch arm: "arm64", intel: "x86_64"

  version "26.1"
  sha256 arm:   "REPLACE_WITH_ARM64_SHA256",
         intel: "REPLACE_WITH_X86_64_SHA256"

  url "https://github.com/karma-works/gcompris/releases/download/v#{version}/gcompris-qt-#{version}-macOS-#{arch}.dmg"
  name "GCompris"
  desc "Educational software suite for children aged 2 to 10"
  homepage "https://gcompris.net"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Ad-hoc signed builds are not notarized. Strip the quarantine attribute
  # so macOS Gatekeeper does not block the app on first launch.
  preflight do
    system_command "/usr/bin/xattr",
      args: ["-d", "-r", "com.apple.quarantine",
             "#{staged_path}/gcompris-qt.app"],
      sudo: false
  end

  app "gcompris-qt.app"

  zap trash: [
    "~/Library/Application Support/GCompris-Qt",
    "~/Library/Preferences/net.gcompris.plist",
    "~/Library/Caches/net.gcompris",
    "~/Library/Saved Application State/net.gcompris.savedState",
  ]
end
