cask "hyperedit" do
  version "0.10.4"
  sha256 "eda20110c654609efb6e4a34c8e04cf47c2f140fb98d34d5f4bb76951a70de12"

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
