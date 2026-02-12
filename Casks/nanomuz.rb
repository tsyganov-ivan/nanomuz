cask "nanomuz" do
  version "1.5.0"
  sha256 "6571211ede901c6ae3fa625af65960e6d40d945ca5ddb5d4fd04e7739766235a"

  url "https://github.com/tsyganov-ivan/nanomuz/releases/download/v#{version}/Nanomuz-#{version}.dmg"
  name "Nanomuz"
  desc "Tiny floating music widget for macOS"
  homepage "https://github.com/tsyganov-ivan/nanomuz"

  depends_on macos: ">= :monterey"

  app "Nanomuz.app"

  zap trash: [
    "~/Library/Application Support/Nanomuz",
    "~/Library/LaunchAgents/com.nanomuz.plist",
  ]

  caveats <<~EOS
    Nanomuz is not notarized. On first run:
    Right-click the app and select Open, or run:
      xattr -d com.apple.quarantine /Applications/Nanomuz.app
  EOS
end
