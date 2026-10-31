cask "hyperedit" do
  version "0.4.0"
  sha256 "804854c928db5fc1e2f2097da02047eb46ba6b3229cbcfef49614e709e997a20"

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
