cask "nanomuz" do
  version "1.3"
  sha256 "7e60db705c2ec2f1f12aab22ebf63bec234ca090ae00eb88c116189934a5247b"

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
