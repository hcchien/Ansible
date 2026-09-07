defmodule AnsibleRelay.WebAuthorProofTest do
  use ExUnit.Case, async: false
  alias AnsibleRelay.{Repo, IdentityCache, DidElix, WebauthnSync, WebPublication}
  alias AnsibleRelay.Identity.AnchorStore
  alias AnsibleRelay.Db.WebauthnCredential

  defp hex(x), do: Base.encode16(x, case: :lower)
  defp hash(x), do: :crypto.hash(:sha256, x) |> hex()
  defp b64(x), do: Base.url_encode64(x, padding: false)
  defp bytes(x), do: %CBOR.Tag{tag: :bytes, value: x}
  defp sign(private, data), do: :crypto.sign(:eddsa, :none, data, [private, :ed25519]) |> hex()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    {pub, private} = :crypto.generate_key(:eddsa, :ed25519)
    did = DidElix.derive(hex(pub), "proof.elix.cool")
    IdentityCache.put(did, hex(pub), "test-author-proof")

    anchor = %{
      "type" => "io.trisaura.identity.anchor",
      "schema_version" => 3,
      "did" => did,
      "identity_key" => hex(pub),
      "identity_key_algorithm" => "ed25519",
      "handle" => "proof.elix.cool",
      "custody_class" => "software",
      "also_known_as" => [],
      "devices" => [],
      "prev_anchor_cid" => nil,
      "reason" => "initial",
      "created_at" => "2026-01-01T00:00:00Z"
    }

    anchor = Map.put(anchor, "sig", sign(private, AnchorStore.canonical_body(anchor)))
    %{did: did, private: private, pub: pub, anchor: anchor}
  end

  defp enroll(ctx) do
    {:ok, options} = WebauthnSync.registration_options(ctx.did)
    {<<4, x::binary-size(32), y::binary-size(32)>>, key} = :crypto.generate_key(:ecdh, :secp256r1)
    id = :crypto.strong_rand_bytes(32)
    cose = CBOR.encode(%{1 => 2, 3 => -7, -1 => 1, -2 => bytes(x), -3 => bytes(y)})

    auth =
      :crypto.hash(:sha256, "elix.cool") <>
        <<0x45, 0::32, 0::128, byte_size(id)::16>> <> id <> cose

    attestation = CBOR.encode(%{"fmt" => "none", "attStmt" => %{}, "authData" => bytes(auth)})

    client =
      Jason.encode!(%{
        type: "webauthn.create",
        challenge: options["publicKey"]["challenge"],
        origin: "https://elix.cool",
        crossOrigin: false
      })

    credential = %{
      "id" => b64(id),
      "rawId" => b64(id),
      "type" => "public-key",
      "response" => %{"attestationObject" => b64(attestation), "clientDataJSON" => b64(client)}
    }

    now = DateTime.utc_now()

    delegation = %{
      "type" => "io.trisaura.identity.webCredentialDelegation",
      "version" => 1,
      "delegation_id" => "wcd_test",
      "challenge_id" => options["challenge_id"],
      "subject_did" => ctx.did,
      "credential_id_hash" => hash(id),
      "rp_id" => "elix.cool",
      "origin" => "https://elix.cool",
      "attestation_sha256" => hash(attestation),
      "issued_at" => DateTime.to_iso8601(DateTime.add(now, -60)),
      "expires_at" => DateTime.to_iso8601(DateTime.add(now, 3600)),
      "allowed_actions" => ["forum.publish"]
    }

    signature = sign(ctx.private, WebPublication.canonical_json(delegation))

    assert {:ok, stored} =
             WebauthnSync.finish_registration(
               ctx.did,
               options["challenge_id"],
               credential,
               signature,
               delegation
             )

    %{id: id, key: key, stored: stored}
  end

  test "registered DID-bound passkey produces independently verifiable content-bound evidence",
       ctx do
    enrolled = enroll(ctx)
    assert enrolled.stored.delegation["subject_did"] == ctx.did
    now = DateTime.utc_now()
    payload = %{"title" => "Independently signed", "body" => "Test content"}

    operation = %{
      "type" => "io.trisaura.webPublicationOperation",
      "version" => 1,
      "operation_id" => "web-proof-conformance",
      "author_did" => ctx.did,
      "action" => "forum.publish",
      "target_forum_host" => "https://elix.cool",
      "board_id" => "proof-board",
      "entity_type" => "thread",
      "entity_id" => "proof-thread",
      "parent_id" => nil,
      "visibility" => "public",
      "federate" => false,
      "payload" => payload,
      "payload_hash" => hash(WebPublication.canonical_json(payload)),
      "created_at" => DateTime.to_iso8601(now),
      "expires_at" => DateTime.to_iso8601(DateTime.add(now, 120)),
      "nonce" => b64(:crypto.strong_rand_bytes(24))
    }

    operation_hash = hash(WebPublication.canonical_json(operation))

    {:ok, options} =
      WebauthnSync.publication_options(ctx.did, "session-1", operation, operation_hash)

    assert options["publicKey"]["challenge"] ==
             b64(WebauthnSync.publication_challenge(operation_hash))

    client =
      Jason.encode!(%{
        type: "webauthn.get",
        challenge: options["publicKey"]["challenge"],
        origin: "https://elix.cool",
        crossOrigin: false
      })

    auth = :crypto.hash(:sha256, "elix.cool") <> <<5, 1::32>>

    signature =
      :crypto.sign(:ecdsa, :sha256, auth <> :crypto.hash(:sha256, client), [
        enrolled.key,
        :secp256r1
      ])

    credential = %{
      "rawId" => b64(enrolled.id),
      "response" => %{
        "authenticatorData" => b64(auth),
        "clientDataJSON" => b64(client),
        "signature" => b64(signature)
      }
    }

    assert {:ok, proof} =
             WebauthnSync.verify_publication(
               ctx.did,
               "session-1",
               options["challenge_id"],
               operation,
               operation_hash,
               credential
             )

    assert proof["delegation"] == enrolled.stored.delegation
    assert proof["registration_attestation"] == enrolled.stored.registration_attestation

    assert {:error, _} =
             WebauthnSync.verify_publication(
               ctx.did,
               "session-1",
               options["challenge_id"],
               operation,
               operation_hash,
               credential
             )

    assert Repo.get!(WebauthnCredential, enrolled.id).sign_count == 1

    projected =
      payload
      |> Map.merge(%{
        "boardId" => operation["board_id"],
        "threadId" => nil,
        "createdAt" => operation["created_at"],
        "publishedAt" => operation["created_at"],
        "visibility" => "public",
        "federate" => false,
        "web_author_proof" => proof,
        "web_operation" => operation,
        "web_operation_hash" => operation_hash,
        "web_host_receipt" => %{}
      })

    op = %{
      "log_id" => 707,
      "op_id" => operation["operation_id"],
      "author_did" => ctx.did,
      "entity_type" => "thread",
      "entity_id" => "proof-thread",
      "op_type" => "insert",
      "payload" => Base.encode64(Jason.encode!(projected)),
      "signature" => proof["signature"],
      "public_key_hex" => hex(ctx.pub),
      "identity_chain" => [ctx.anchor],
      "anchor_expires_at" => "2099-01-01T00:00:00Z"
    }

    if path = System.get_env("ELIX_AUTHOR_FIXTURE_OUTPUT") do
      revocation = %{"type" => "io.trisaura.identity.webCredentialRevocation", "version" => 1,
        "subject_did" => ctx.did, "credential_id" => b64(enrolled.id),
        "revoked_at" => DateTime.to_iso8601(now), "nonce" => "independent-witness-fixture-revocation"}
      fixture = Map.merge(op, %{"fixture_revocation" => revocation,
        "fixture_revocation_signature" => sign(ctx.private, WebPublication.canonical_json(revocation))})
      File.write!(path, Jason.encode!(fixture, pretty: true))
    end
    Repo.update!(Ecto.Changeset.change(enrolled.stored, revoked_at: DateTime.utc_now()))

    assert {:error, :not_enrolled} =
             WebauthnSync.publication_options(ctx.did, "session-1", operation, operation_hash)
  end

  test "expired delegation cannot authorize a new publication", ctx do
    enrolled = enroll(ctx)

    Repo.update!(
      Ecto.Changeset.change(enrolled.stored,
        delegation_expires_at: DateTime.add(DateTime.utc_now(), -1)
      )
    )

    assert {:error, :not_enrolled} =
             WebauthnSync.publication_options(
               ctx.did,
               "session-1",
               %{"action" => "forum.publish"},
               "hash"
             )
  end

  test "legacy unbound delegation cannot authorize publication", ctx do
    enrolled = enroll(ctx)
    Repo.update!(Ecto.Changeset.change(enrolled.stored, delegation: nil))

    assert {:error, :not_enrolled} =
             WebauthnSync.publication_options(
               ctx.did,
               "session-1",
               %{"action" => "forum.publish"},
               "hash"
             )
  end
end
