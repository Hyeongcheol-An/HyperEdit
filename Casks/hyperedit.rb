cask "hyperedit" do
  version "0.5.1"
  sha256 "ad6b39df23b9641efb2d3a10803db9e888d605fa58135d94c2c7e2358672fd5c"

  url "https://github.com/Hyeongcheol-An/HyperEdit/releases/download/v#{version}/HyperEdit-#{version}.dmg"
  name "HyperEdit"
  desc "Ribbon-style plain-text editor for one large notes file"
  homepage "https://github.com/Hyeongcheol-An/HyperEdit"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "HyperEdit.app"

  zap trash: [
    "~/Library/Application Support/HyperEdit",
    "~/Library/Caches/io.github.hyeongcheol-an.hyperedit",
    "~/Library/Preferences/io.github.hyeongcheol-an.hyperedit.plist",
    "~/Library/Saved Application State/io.github.hyeongcheol-an.hyperedit.savedState",
  ]
end
