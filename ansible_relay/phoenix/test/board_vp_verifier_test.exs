defmodule AnsibleRelay.ForumHost.BoardVpVerifierTest do
  use ExUnit.Case, async: true

  alias AnsibleRelay.ForumHost.BoardVpVerifier

  test "verifies issuer signature, holder binding, nonce, audience, claims and status" do
    now = ~U[2026-07-22 10:00:00Z]
    {issuer_public, issuer_private} = :crypto.generate_key(:eddsa, :ed25519)
    {holder_public, holder_private} = :crypto.generate_key(:ecdh, :secp256r1)
    jwk = jwk(holder_public)
    holder = "did:jwk:" <> Base.url_encode64(Jason.encode!(jwk), padding: false)
    issuer = "did:elix:org:ntp"

    vc = %{
      "iss" => issuer,
      "sub" => holder,
      "iat" => DateTime.to_unix(now),
      "nbf" => DateTime.to_unix(now),
      "exp" => DateTime.to_unix(DateTime.add(now, 3_600, :second)),
      "cnf" => %{"jwk" => jwk},
      "vc" => %{
        "type" => ["VerifiableCredential", "PoliticalPartyMembershipCredential"],
        "credentialSubject" => %{
          "id" => holder,
          "membership" => true,
          "forum_host_id" => "host-local-dev",
          "board_id" => "board-a"
        },
        "credentialStatus" => [%{"statusPurpose" => "revocation"}]
      }
    }

    credential =
      jwt(%{"alg" => "EdDSA", "typ" => "JWT", "kid" => "key-1"}, vc, fn input ->
        :crypto.sign(:eddsa, :none, input, [issuer_private, :ed25519])
      end)

    vp =
      jwt(
        %{"alg" => "ES256", "typ" => "openid4vp+jwt", "jwk" => jwk},
        %{
          "aud" => "https://relay.elix.cool",
          "nonce" => "nonce-1",
          "iat" => DateTime.to_unix(now),
          "sub" => holder,
          "vp" => %{"verifiableCredential" => [credential]}
        },
        fn input ->
          :crypto.sign(:ecdsa, :sha256, input, [holder_private, :secp256r1]) |> der_to_jose()
        end
      )

    [vp_header, vp_claims, vp_signature] = String.split(vp, ".")
    {:ok, jose_signature} = Base.url_decode64(vp_signature, padding: false)

    assert :crypto.verify(
             :ecdsa,
             :sha256,
             vp_header <> "." <> vp_claims,
             BoardVpVerifier.jose_signature_to_der(jose_signature),
             [holder_public, :secp256r1]
           )

    assert {:ok, result} =
             BoardVpVerifier.verify(
               vp,
               policy(issuer),
               "member",
               "nonce-1",
               "https://relay.elix.cool",
               now: now,
               debug: true,
               forum_host_id: "host-local-dev",
               board_id: "board-a",
               issuer_resolver: fn ^issuer, "key-1" -> {:ok, issuer_public} end,
               status_checker: fn _status, ^now -> :active end
             )

    assert result.pairwise_subject == holder
    assert is_binary(result.device_key_thumbprint)

    assert {:error, :wrong_nonce} =
             BoardVpVerifier.verify(
               vp,
               policy(issuer),
               "member",
               "wrong",
               "https://relay.elix.cool",
               now: now,
               forum_host_id: "host-local-dev",
               board_id: "board-a",
               issuer_resolver: fn _, _ -> {:ok, issuer_public} end,
               status_checker: fn _, _ -> :active end
             )

    assert {:error, :wrong_board} =
             BoardVpVerifier.verify(
               vp,
               policy(issuer),
               "member",
               "nonce-1",
               "https://relay.elix.cool",
               now: now,
               forum_host_id: "host-local-dev",
               board_id: "board-b",
               issuer_resolver: fn _, _ -> {:ok, issuer_public} end,
               status_checker: fn _, _ -> :active end
             )

    assert {:error, :wrong_board} =
             BoardVpVerifier.verify(
               vp,
               policy(issuer),
               "member",
               "nonce-1",
               "https://relay.elix.cool",
               now: now,
               forum_host_id: "another-host",
               board_id: "board-a",
               issuer_resolver: fn _, _ -> {:ok, issuer_public} end,
               status_checker: fn _, _ -> :active end
             )
  end

  defp policy(issuer) do
    %{
      "version" => 1,
      "discovery" => "credential_required",
      "read" => %{"requirement" => "member"},
      "post" => %{"requirement" => "member"},
      "moderate" => %{"requirement" => "board_moderator"},
      "requirements" => %{
        "member" => %{
          "credential_type" => "PoliticalPartyMembershipCredential",
          "trusted_issuers" => [issuer],
          "claims" => [%{"path" => "membership", "op" => "equals", "value" => true}],
          "holder_binding" => "required",
          "status" => %{"required" => true, "max_age_seconds" => 300}
        }
      },
      "capability_ttl_seconds" => 300,
      "content_visibility" => "host_visible",
      "federation" => "disabled"
    }
  end

  defp jwk(<<4, x::binary-size(32), y::binary-size(32)>>) do
    %{
      "kty" => "EC",
      "crv" => "P-256",
      "x" => Base.url_encode64(x, padding: false),
      "y" => Base.url_encode64(y, padding: false)
    }
  end

  defp jwt(header, claims, signer) do
    encoded_header = header |> Jason.encode!() |> Base.url_encode64(padding: false)
    encoded_claims = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    signed = encoded_header <> "." <> encoded_claims
    signed <> "." <> (signed |> signer.() |> Base.url_encode64(padding: false))
  end

  defp der_to_jose(<<48, _length, 2, r_length, rest::binary>>) do
    <<r::binary-size(^r_length), 2, s_length, s::binary-size(s_length)>> = rest
    pad32(r) <> pad32(s)
  end

  defp pad32(value) do
    stripped = String.trim_leading(value, <<0>>)
    :binary.copy(<<0>>, 32 - byte_size(stripped)) <> stripped
  end
end
