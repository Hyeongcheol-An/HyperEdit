cask "hyperedit" do
  version "0.11.1"
  sha256 "de3647cb1097678869f5d79c2aff4b18207a06024f3d74b76b4154adfb86fc95"

  url "https://github.com/Hyeongcheol-An/HyperEdit/releases/download/v#{version}/HyperEdit-#{version}-universal.dmg"
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
