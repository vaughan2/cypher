class Cypher < Formula
  desc "macOS menu bar privacy lock with Matrix rain animation"
  homepage "https://github.com/vaughan2/cypher"
  url "https://github.com/vaughan2/cypher/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_OF_SOURCE_TARBALL"
  license "MIT"
  head "https://github.com/vaughan2/cypher.git", branch: "main"

  depends_on "go" => :build
  depends_on :macos => :big_sur

  def install
    system "make", "build"
    prefix.install "cypher.app"
    # CLI wrapper so `cypher` works from any terminal
    (bin/"cypher").write <<~SH
      #!/bin/sh
      open -a "#{prefix}/cypher.app" "$@"
    SH
  end

  def caveats
    <<~EOS
      Cypher runs as a menu bar app. Start it with:
        cypher

      Two permissions are required on first launch:
        - Input Monitoring  (for the global hotkey Cmd+Shift+L)
        - Accessibility     (to block system shortcuts while locked)

      Grant them in System Settings → Privacy & Security, then relaunch.
    EOS
  end

  test do
    assert_predicate prefix/"cypher.app", :directory?
    assert_predicate bin/"cypher", :executable?
  end
end
