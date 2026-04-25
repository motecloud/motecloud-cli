# typed: false
# frozen_string_literal: true

# Homebrew formula for motecloud-cli
# Repository: https://github.com/motecloud/homebrew-motecloud
#
# Install:
#   brew tap motecloud/motecloud
#   brew install motecloud-cli
#
# Or directly:
#   brew install https://raw.githubusercontent.com/motecloud/motecloud-cli/main/packaging/homebrew/motecloud.rb

class MotecloudCli < Formula
  desc "Zero-dependency CLI for Motecloud memory and session APIs"
  homepage "https://github.com/motecloud/motecloud-cli#readme"
  url "https://github.com/motecloud/motecloud-cli/releases/download/v0.2.0/motecloud-cli-v0.2.0.tar.gz"
  sha256 "5b18373c4b49769c099381088d337f9349f80b722026b087da54ba8dd51054bc"
  license "MIT"
  version "0.2.0"

  depends_on "python@3.12"

  def install
    # Install the standalone Python module to libexec
    libexec.install "motecloud.py"

    # Write a launcher to bin/
    (bin/"motecloud").write <<~EOS
      #!/bin/sh
      exec "#{Formula["python@3.12"].opt_bin}/python3" "#{libexec}/motecloud.py" "$@"
    EOS
  end

  test do
    assert_match "motecloud-cli 0.2.0", shell_output("#{bin}/motecloud --version")

    # Smoke test: missing tenant exits non-zero with the right message
    output = shell_output("#{bin}/motecloud prepare --task test 2>&1", 1)
    assert_match "MOTECLOUD_TENANT_ID", output
  end
end
