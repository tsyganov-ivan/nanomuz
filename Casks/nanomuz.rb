cask "nanomuz" do
  version "1.4"
  sha256 "320715819b6fb2ecc5d662e89d560b57785ac5b2e748a33ad4e43f46722ca71a"

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
