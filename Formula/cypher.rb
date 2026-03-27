class Cypher < Formula
  desc "macOS menu bar privacy lock with Matrix rain animation"
  homepage "https://github.com/vaughandauria/cypher"
  url "https://github.com/vaughandauria/cypher/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_OF_SOURCE_TARBALL"
  license "MIT"
  head "https://github.com/vaughandauria/cypher.git", branch: "main"

  depends_on "go" => :build
  depends_on :macos => :big_sur

  def install
    system "make", "build"
    prefix.install "cypher.app"
  end

  def caveats
    <<~EOS
      Cypher is a menu bar app. Launch it from:
        #{prefix}/cypher.app

      Or add it to /Applications:
        cp -r #{prefix}/cypher.app /Applications/

      Two permissions are required on first launch:
        - Input Monitoring  (for the global hotkey)
        - Accessibility     (to block system shortcuts while locked)

      Grant them in System Settings → Privacy & Security, then relaunch.
    EOS
  end

  test do
    assert_predicate prefix/"cypher.app", :directory?
  end
end
