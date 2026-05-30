defmodule AnsibleRelay.Web.ReputationControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.DidAccountCache
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  @issuer_did "did:web:issuer.trisaura.io"
  @holder_did "did:plc:abcdefghijklmnop"
  @nostr_binding_kind 27_235
  @nostr_binding_marker "io.trisaura.vc.nostr-binding.v1"
  @nostr_private_key "0000000000000000000000000000000000000000000000000000000000000003"
  @nostr_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp holder_keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp sign(private_key, message) when is_binary(message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  # Recursively sort map keys alphabetically — mirrors Dart's _canonicalValue.
  defp deep_sort(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new(fn {k, v} -> {k, deep_sort(v)} end)
  end

  defp deep_sort(value) when is_list(value), do: Enum.map(value, &deep_sort/1)
  defp deep_sort(value), do: value

  defp canonical(value), do: value |> deep_sort() |> Jason.encode!()

  # Build a signed VC.
  defp build_vc(holder_did, issuer_priv, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    valid_until = DateTime.add(DateTime.utc_now(), 90 * 86_400, :second) |> DateTime.to_iso8601()
    credential_type = Keyword.get(opts, :credential_type, "TrisAuraHumanityCredential")

    vc_without_proof = %{
      "@context" => [
        "https://www.w3.org/ns/credentials/v2",
        "https://trisaura.io/contexts/humanity/v1"
      ],
      "id" => "https://issuer.trisaura.io/vc/test001",
      "type" => ["VerifiableCredential", credential_type],
      "issuer" => @issuer_did,
      "validFrom" => now,
      "validUntil" => valid_until,
      "credentialSubject" => %{
        "id" => holder_did,
        "humanVerified" => true,
        "assuranceLevel" => "tw_natural_person_certificate",
        "assuranceMethod" => "tw_fido_or_moica",
        "jurisdiction" => "TW"
      }
    }

    proof_value = sign(issuer_priv, canonical(vc_without_proof))

    Map.put(vc_without_proof, "proof", %{
      "type" => "Ed25519Signature2020",
      "created" => now,
      "verificationMethod" => "#{@issuer_did}#key-1",
      "proofPurpose" => "assertionMethod",
      "proofValue" => proof_value
    })
  end

  # Build a signed VP using the canonical form:
  # sign(canonical(vp_with_proof_options_but_no_proof_value)).
  defp build_vp(holder_did, holder_priv_key, vcs, opts \\ []) do
    proof_options =
      %{
        "type" => "DataIntegrityProof",
        "cryptosuite" => "eddsa-jcs-2022",
        "verificationMethod" => "#{holder_did}#key-1",
        "created" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "proofPurpose" => "authentication"
      }
      |> then(fn proof ->
        if nonce = Keyword.get(opts, :nonce), do: Map.put(proof, "challenge", nonce), else: proof
      end)
      |> then(fn proof ->
        if audience = Keyword.get(opts, :audience),
          do: Map.put(proof, "domain", audience),
          else: proof
      end)

    vp_with_options = %{
      "@context" => ["https://www.w3.org/ns/credentials/v2"],
      "type" => ["VerifiablePresentation"],
      "holder" => holder_did,
      "verifiableCredential" => vcs,
      "proof" => proof_options
    }

    proof_value = sign(holder_priv_key, canonical(vp_with_options))
    put_in(vp_with_options, ["proof", "proofValue"], proof_value)
  end

  defp build_nostr_binding_event(holder_did, vp, opts \\ []) do
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now() |> DateTime.to_unix())
    proof = Map.fetch!(vp, "proof")
    vp_hash = :crypto.hash(:sha256, canonical(vp)) |> Base.encode16(case: :lower)

    tags = [
      ["d", @nostr_binding_marker],
      ["holder", holder_did],
      ["challenge", Map.fetch!(proof, "challenge")],
      ["domain", Map.fetch!(proof, "domain")],
      ["vp_sha256", vp_hash]
    ]

    id =
      Jason.encode!([0, @nostr_pubkey, created_at, @nostr_binding_kind, tags, ""])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{
      "event" => %{
        "id" => id,
        "pubkey" => @nostr_pubkey,
        "created_at" => created_at,
        "kind" => @nostr_binding_kind,
        "tags" => tags,
        "content" => "",
        "sig" => sign_schnorr(@nostr_private_key, id)
      }
    }
  end

  @secp256k1_p 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @secp256k1_g {
    0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
    0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
  }

  defp sign_schnorr(private_key_hex, message_hash_hex) do
    d0 = hex_to_int(private_key_hex)
    message = Base.decode16!(message_hash_hex, case: :lower)
    aux = <<0::unsigned-big-256>>
    p = point_mul(d0, @secp256k1_g)
    d = if even?(elem(p, 1)), do: d0, else: @secp256k1_n - d0
    px = int_to_32(elem(p, 0))
    t = xor_bytes(int_to_32(d), tagged_hash("BIP0340/aux", aux))
    k0 = tagged_hash("BIP0340/nonce", t <> px <> message) |> binary_to_int() |> rem(@secp256k1_n)
    r = point_mul(k0, @secp256k1_g)
    k = if even?(elem(r, 1)), do: k0, else: @secp256k1_n - k0
    rx = int_to_32(elem(r, 0))

    e =
      tagged_hash("BIP0340/challenge", rx <> px <> message)
      |> binary_to_int()
      |> rem(@secp256k1_n)

    (rx <> int_to_32(rem(k + e * d, @secp256k1_n))) |> Base.encode16(case: :lower)
  end

  defp tagged_hash(tag, message) do
    tag_hash = :crypto.hash(:sha256, tag)
    :crypto.hash(:sha256, tag_hash <> tag_hash <> message)
  end

  defp point_mul(scalar, point), do: do_point_mul(scalar, point, nil)
  defp do_point_mul(0, _point, result), do: result

  defp do_point_mul(scalar, point, result) do
    next_result = if rem(scalar, 2) == 1, do: point_add(result, point), else: result
    do_point_mul(div(scalar, 2), point_add(point, point), next_result)
  end

  defp point_add(nil, point), do: point
  defp point_add(point, nil), do: point

  defp point_add({x1, y1}, {x2, y2}) do
    cond do
      x1 == x2 and mod(y1 + y2, @secp256k1_p) == 0 ->
        nil

      x1 == x2 and y1 == y2 ->
        lambda = mod(3 * x1 * x1 * mod_inverse(2 * y1, @secp256k1_p), @secp256k1_p)
        point_from_lambda(lambda, x1, y1, x2)

      true ->
        lambda = mod((y2 - y1) * mod_inverse(x2 - x1, @secp256k1_p), @secp256k1_p)
        point_from_lambda(lambda, x1, y1, x2)
    end
  end

  defp point_from_lambda(lambda, x1, y1, x2) do
    x3 = mod(lambda * lambda - x1 - x2, @secp256k1_p)
    y3 = mod(lambda * (x1 - x3) - y1, @secp256k1_p)
    {x3, y3}
  end

  defp mod_inverse(value, modulus) do
    {1, inverse, _} = egcd(mod(value, modulus), modulus)
    mod(inverse, modulus)
  end

  defp egcd(0, b), do: {b, 0, 1}

  defp egcd(a, b) do
    {g, x, y} = egcd(rem(b, a), a)
    {g, y - div(b, a) * x, x}
  end

  defp mod(value, modulus) do
    result = rem(value, modulus)
    if result < 0, do: result + modulus, else: result
  end

  defp even?(value), do: rem(value, 2) == 0
  defp hex_to_int(hex), do: Base.decode16!(hex, case: :lower) |> binary_to_int()
  defp binary_to_int(binary), do: :binary.decode_unsigned(binary, :big)
  defp int_to_32(value), do: <<value::unsigned-big-256>>

  defp xor_bytes(left, right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.map(fn {a, b} -> Bitwise.bxor(a, b) end)
    |> :binary.list_to_bin()
  end

  setup do
    case DidAccountCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    DidAccountCache.reset()

    # Generate issuer keypair using OTP so sign/verify use the same key format.
    {issuer_pub, issuer_priv} = :crypto.generate_key(:eddsa, :ed25519)
    issuer_pub_hex = Base.encode16(issuer_pub, case: :lower)

    Application.put_env(:ansible_relay, :trusted_vc_issuers, [
      %{did: @issuer_did, public_key_hex: issuer_pub_hex}
    ])

    {:ok, issuer_priv: issuer_priv}
  end

  test "present upgrades holder to verified_human with valid humanity credential VP",
       %{issuer_priv: issuer_priv} do
    {pub_hex, priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["reputation_tier"] == "verified_human"
    assert {:ok, %{reputation_tier: "verified_human"}} = DidAccountCache.get(@holder_did)
  end

  test "present binds a Nostr pubkey to the verified holder for local relay trust",
       %{issuer_priv: issuer_priv} do
    {pub_hex, priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc(@holder_did, issuer_priv)

    vp =
      build_vp(@holder_did, priv_key, [vc],
        nonce: "post-nonce",
        audience: "https://relay.trisaura.io"
      )

    nostr_binding = build_nostr_binding_event(@holder_did, vp)

    response =
      post_json("/api/v2/reputation/present", %{
        "holder_did" => @holder_did,
        "vp" => vp,
        "nostr_binding" => nostr_binding
      })

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["reputation_tier"] == "verified_human"
    assert body["nostr_pubkey"] == @nostr_pubkey

    assert {:ok, %{holder_did: @holder_did, reputation_tier: "verified_human"}} =
             DidAccountCache.get_nostr_binding(@nostr_pubkey)
  end

  test "present does not treat email credential as verified human",
       %{issuer_priv: issuer_priv} do
    {pub_hex, priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc(@holder_did, issuer_priv, credential_type: "EmailCredential")
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["reputation_tier"] == "basic"
    assert {:ok, %{reputation_tier: "basic"}} = DidAccountCache.get(@holder_did)
  end

  test "present rejects VP with invalid holder proof", %{issuer_priv: issuer_priv} do
    {pub_hex, _priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc(@holder_did, issuer_priv)
    {_other_pub, other_priv} = holder_keypair()
    vp = build_vp(@holder_did, other_priv, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_vp"
  end

  test "present rejects VP when VC subject does not match holder", %{issuer_priv: issuer_priv} do
    {pub_hex, priv_key} = holder_keypair()
    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io")

    vc = build_vc("did:plc:someoneelse0001", issuer_priv)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status in [401, 422]
  end

  test "present does not downgrade a higher tier", %{issuer_priv: issuer_priv} do
    {pub_hex, priv_key} = holder_keypair()

    DidAccountCache.put(@holder_did, pub_hex, "alice.trisaura.io",
      reputation_tier: "verified_human"
    )

    vc = build_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 200
    assert {:ok, %{reputation_tier: "verified_human"}} = DidAccountCache.get(@holder_did)
  end

  test "present returns 404 for unknown holder", %{issuer_priv: issuer_priv} do
    {_pub, priv_key} = holder_keypair()
    vc = build_vc(@holder_did, issuer_priv)
    vp = build_vp(@holder_did, priv_key, [vc])

    response =
      post_json("/api/v2/reputation/present", %{"holder_did" => @holder_did, "vp" => vp})

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["error"] == "holder_not_found"
  end
end
