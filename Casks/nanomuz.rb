cask "nanomuz" do
  version "1.4.1"
  sha256 "79fbd98ab10b33dc4906bf96bd1fd3fe57a16f6185fb9935aca62a560cda27e7"

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
