cask "hyperedit" do
  version "0.3.0"
  sha256 "2defd6af69c6ceb3767e10d6e2fcf3b4c83bff3d2084571b4b56c4e0f06d2903"

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
