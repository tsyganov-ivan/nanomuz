cask "nanomuz" do
  version "1.1.11"
  sha256 "35b9e2752182f72ce40f0577c3bc032dd779a8c0490e282d1fcc2d9de2227d87"

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
