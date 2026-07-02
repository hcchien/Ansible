defmodule AnsibleAppview.Ingest.SafeHttpTest do
  use ExUnit.Case, async: true

  alias AnsibleAppview.Ingest.SafeHttp

  describe "global_address?/1" do
    test "blocks loopback / private / link-local / metadata / unique-local" do
      refute SafeHttp.global_address?({127, 0, 0, 1})
      refute SafeHttp.global_address?({10, 1, 2, 3})
      refute SafeHttp.global_address?({172, 16, 0, 1})
      refute SafeHttp.global_address?({172, 31, 255, 255})
      refute SafeHttp.global_address?({192, 168, 1, 1})
      # cloud metadata service
      refute SafeHttp.global_address?({169, 254, 169, 254})
      refute SafeHttp.global_address?({0, 0, 0, 0})
      # IPv6 loopback + unique-local + link-local
      refute SafeHttp.global_address?({0, 0, 0, 0, 0, 0, 0, 1})
      refute SafeHttp.global_address?({0xFD00, 0, 0, 0, 0, 0, 0, 1})
      refute SafeHttp.global_address?({0xFE80, 0, 0, 0, 0, 0, 0, 1})
    end

    test "allows globally-routable unicast" do
      assert SafeHttp.global_address?({1, 1, 1, 1})
      assert SafeHttp.global_address?({93, 184, 216, 34})
      # 172.15/16 and 172.32/16 are OUTSIDE the private 172.16/12 block
      assert SafeHttp.global_address?({172, 15, 0, 1})
      assert SafeHttp.global_address?({172, 32, 0, 1})
      assert SafeHttp.global_address?({0x2606, 0x4700, 0, 0, 0, 0, 0, 1})
    end
  end

  describe "validate_url/1" do
    test "rejects non-http schemes" do
      assert {:error, {:blocked_scheme, "file"}} = SafeHttp.validate_url("file:///etc/passwd")
      assert {:error, {:blocked_scheme, "gopher"}} = SafeHttp.validate_url("gopher://x/")
    end

    test "rejects literal loopback / private / metadata hosts" do
      assert {:error, {:blocked_ip, _}} = SafeHttp.validate_url("http://127.0.0.1/x")
      assert {:error, {:blocked_ip, _}} = SafeHttp.validate_url("http://10.0.0.5/x")
      assert {:error, {:blocked_ip, _}} = SafeHttp.validate_url("http://169.254.169.254/latest/")
      assert {:error, {:blocked_ip, _}} = SafeHttp.validate_url("http://[::1]/x")
    end

    test "rejects a URL with no host" do
      assert {:error, :no_host} = SafeHttp.validate_url("http:///nohost")
    end

    test "accepts a literal public IP" do
      assert :ok = SafeHttp.validate_url("https://1.1.1.1/x")
    end
  end
end
