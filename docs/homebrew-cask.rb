# Template for a cask in a separate tap repository, e.g. dwagwd/homebrew-tap at Casks/codex-usage-widget.rb.
# Use only with a Developer ID signed and notarized universal ZIP (see releasing.md).
# Users then install with: brew install --cask dwagwd/tap/codex-usage-widget
cask "codex-usage-widget" do
  version "0.4.0"
  sha256 "d0abbe31ffa0b73aab94354f40fde2fd8e3cda92065ef50194e0edf1f70bc58a"

  url "https://github.com/dwagwd/codex-plugin/releases/download/v#{version}/CodexUsageWidget-#{version}-macos-universal.zip"
  name "Codex Usage Widget"
  desc "Floating desktop card for Codex plan quota, token usage and reset countdowns"
  homepage "https://github.com/dwagwd/codex-plugin"

  depends_on macos: ">= :ventura"

  app "Codex Usage Widget.app"

  uninstall quit: "local.codex.usage-widget"

  zap trash: [
    "~/Library/Application Support/CodexUsageWidget",
    "~/Library/Caches/CodexUsageWidget",
    "~/Library/Preferences/local.codex.usage-widget.plist",
  ]
end
