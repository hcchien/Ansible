defmodule AnsibleRelay.ForumHost.BitstringStatusCheckerTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.ForumHost.BitstringStatusChecker

  setup do
    original = Application.get_env(:ansible_relay, :trusted_membership_issuers)
    original_system = Application.get_env(:ansible_relay, :trusted_vc_issuers)

    on_exit(fn ->
      restore(:trusted_membership_issuers, original)
      restore(:trusted_vc_issuers, original_system)
    end)

    :ok
  end

  test "verifies signed status list and leftmost-bit index semantics" do
    now = ~U[2026-07-22 10:00:00Z]
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    issuer = "did:elix:org:ntp"
    url = "https://issuer.elix.cool/tenants/ntp/status/revocation/1"

    Application.put_env(:ansible_relay, :trusted_membership_issuers, [
      %{
        did: issuer,
        key_id: "key-1",
        public_key_multibase: "u" <> Base.url_encode64(public, padding: false),
        status_origin: "https://issuer.elix.cool"
      }
    ])

    bits = :binary.copy(<<0>>, 16_384)
    <<prefix::binary-size(5), byte, suffix::binary>> = bits
    revoked_bits = prefix <> <<Bitwise.bor(byte, 0x20)>> <> suffix
    encoded = "u" <> Base.url_encode64(:zlib.gzip(revoked_bits), padding: false)

    credential = %{
      "iss" => issuer,
      "iat" => DateTime.to_unix(now),
      "vc" => %{
        "id" => url,
        "credentialSubject" => %{
          "statusPurpose" => "revocation",
          "encodedList" => encoded
        }
      }
    }

    compact = jwt(%{"alg" => "EdDSA", "typ" => "JWT", "kid" => "key-1"}, credential, private)
    fetcher = fn ^url -> {:ok, compact} end

    assert :revoked = BitstringStatusChecker.check([entry(url, 42)], now, fetcher: fetcher)
    assert :active = BitstringStatusChecker.check([entry(url, 43)], now, fetcher: fetcher)

    assert :unavailable =
             BitstringStatusChecker.check([entry("http://localhost/status", 42)], now,
               fetcher: fetcher
             )
  end

  test "checks a system VC live status only on its trusted did:web origin" do
    url = "https://issuer-dev.elix.cool/api/v1/vc/status/abc123"

    Application.put_env(:ansible_relay, :trusted_vc_issuers, [
      %{
        did: "did:web:issuer-dev.elix.cool",
        public_key_hex: String.duplicate("01", 32)
      }
    ])

    active_fetcher = fn ^url -> {:ok, %{"status" => "active", "revoked" => false}} end
    revoked_fetcher = fn ^url -> {:ok, %{"status" => "revoked", "revoked" => true}} end

    status = %{"type" => "TrisAuraStatusEndpoint2024", "id" => url}

    assert :active =
             BitstringStatusChecker.check(status, DateTime.utc_now(),
               json_fetcher: active_fetcher
             )

    assert :revoked =
             BitstringStatusChecker.check(status, DateTime.utc_now(),
               json_fetcher: revoked_fetcher
             )

    assert :unavailable =
             BitstringStatusChecker.check(
               %{
                 "type" => "TrisAuraStatusEndpoint2024",
                 "id" => "https://evil.example/api/v1/vc/status/abc123"
               },
               DateTime.utc_now(),
               json_fetcher: active_fetcher
             )
  end

  defp entry(url, index),
    do: %{
      "statusPurpose" => "revocation",
      "statusListCredential" => url,
      "statusListIndex" => Integer.to_string(index)
    }

  defp jwt(header, claims, private) do
    encoded_header = header |> Jason.encode!() |> Base.url_encode64(padding: false)
    encoded_claims = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    signed = encoded_header <> "." <> encoded_claims
    signature = :crypto.sign(:eddsa, :none, signed, [private, :ed25519])
    signed <> "." <> Base.url_encode64(signature, padding: false)
  end

  defp restore(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore(key, value), do: Application.put_env(:ansible_relay, key, value)
end
