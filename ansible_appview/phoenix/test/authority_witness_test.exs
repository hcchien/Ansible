defmodule AnsibleAppview.AuthorityWitnessTest do
  use ExUnit.Case, async: false
  alias AnsibleAppview.{Repo, DidElix, SigningPayload}
  alias AnsibleAppview.Authority.Witness
  alias AnsibleAppview.Identity.AnchorEncoding
  alias AnsibleAppview.Ingest.{AuthorVerifier, Folder}
  defp hex(x), do: Base.encode16(x, case: :lower)
  defp sign(key, bytes), do: :crypto.sign(:eddsa, :none, bytes, [key, :ed25519]) |> hex()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    {pub, private} = :crypto.generate_key(:eddsa, :ed25519)
    {next, next_private} = :crypto.generate_key(:eddsa, :ed25519)
    did = DidElix.derive(hex(pub), "witness.elix.cool")

    initial = %{
      "schema_version" => 3,
      "did" => did,
      "identity_key" => hex(pub),
      "identity_key_algorithm" => "ed25519",
      "handle" => "witness.elix.cool",
      "custody_class" => "software",
      "devices" => [],
      "also_known_as" => [],
      "reason" => "initial",
      "prev_anchor_cid" => nil,
      "created_at" => "2026-01-01T00:00:00Z"
    }

    initial = Map.put(initial, "sig", sign(private, AnchorEncoding.canonical_body(initial)))

    rotated =
      Map.merge(initial, %{
        "identity_key" => hex(next),
        "reason" => "rotation",
        "prev_anchor_cid" => AnchorEncoding.compute_cid(initial),
        "created_at" => "2026-02-01T00:00:00Z"
      })

    body = AnchorEncoding.canonical_body(rotated)

    rotated =
      Map.merge(rotated, %{"sig" => sign(next_private, body), "device_sig" => sign(private, body)})

    %{did: did, private: private, next_private: next_private, initial: initial, rotated: rotated}
  end

  defp operation(c, id, key, at \\ "2026-01-15T00:00:00Z") do
    payload = %{"body" => "original #{id}", "createdAt" => at, "visibility" => "public"}

    op = %{
      "log_id" => System.unique_integer([:positive]),
      "op_id" => id,
      "author_did" => c.did,
      "entity_type" => "murmur",
      "entity_id" => id,
      "op_type" => "insert",
      "payload" => Base.encode64(Jason.encode!(payload)),
      "identity_chain" => [c.initial],
      "anchor_expires_at" => "2099-01-01T00:00:00Z"
    }

    {Map.put(op, "signature", sign(key, SigningPayload.build(op))), payload}
  end

  test "unknown state is not bootstrapped from untrusted firehose", c do
    {op, payload} = operation(c, "unknown", c.private)
    assert {:error, :authority_checkpoint_required} = Witness.observe(op, payload)
    assert {0, _} = Folder.apply_ops([op])
  end

  test "acknowledged rotation rejects a hidden successor and backdated new operation", c do
    assert {:ok, _} = Witness.checkpoint(c.did, [c.initial])
    {historical, payload} = operation(c, "historical", c.private)
    assert {:ok, _} = Witness.observe(historical, payload)
    assert {:ok, _} = Witness.checkpoint(c.did, [c.initial, c.rotated])
    assert {:error, :authority_rollback_or_fork} = Witness.checkpoint(c.did, [c.initial])
    {attack, attack_payload} = operation(c, "new-backdated", c.private)
    assert {:ok, _} = AuthorVerifier.verify(attack, attack_payload)
    assert {:error, :unobserved_obsolete_authority} = Witness.observe(attack, attack_payload)
    assert {:ok, _} = Witness.observe(historical, payload)
    # Removing a cache-expiry field cannot erase an independent old observation.
    assert {1, _} = Folder.apply_ops([Map.delete(historical, "anchor_expires_at")])
    Repo.query!("TRUNCATE feed_items, appview_profiles, appview_follows, appview_context_notes")
    assert {1, _} = Folder.apply_ops([historical])
  end

  test "observed operation identity cannot be reused with different signed bytes", c do
    {:ok, _} = Witness.checkpoint(c.did, [c.initial])
    {op, payload} = operation(c, "same-id", c.private)
    assert {:ok, _} = Witness.observe(op, payload)
    changed = Map.put(payload, "body", "different")
    changed_op = Map.put(op, "payload", Base.encode64(Jason.encode!(changed)))

    changed_op =
      Map.put(changed_op, "signature", sign(c.private, SigningPayload.build(changed_op)))

    assert {:error, :conflicting_observed_operation} = Witness.observe(changed_op, changed)
  end

  test "current owner may explicitly revalidate exact old content but old key cannot", c do
    {:ok, _} = Witness.checkpoint(c.did, [c.initial, c.rotated])
    {op, payload} = operation(c, "offline-history", c.private)
    assert {:error, :unobserved_obsolete_authority} = Witness.observe(op, payload)

    auth = %{
      "observer_origin" => "http://localhost:4000",
      "type" => "io.trisaura.authorizeHistoricalOperation",
      "version" => 1,
      "subject_did" => c.did,
      "op_id" => op["op_id"],
      "operation_digest" => Witness.operation_digest(op),
      "issued_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "nonce" => "unique-owner-review-12345"
    }

    assert {:error, _} =
             Witness.revalidate(op, auth, sign(c.private, AuthorVerifier.canonical_json(auth)))

    wrong_origin = Map.put(auth, "observer_origin", "https://other.example")

    assert {:error, _} =
             Witness.revalidate(
               op,
               wrong_origin,
               sign(c.next_private, AuthorVerifier.canonical_json(wrong_origin))
             )

    changed =
      Map.put(
        op,
        "payload",
        Base.encode64(Jason.encode!(Map.put(payload, "body", "substituted")))
      )

    assert {:error, _} =
             Witness.revalidate(
               changed,
               auth,
               sign(c.next_private, AuthorVerifier.canonical_json(auth))
             )

    conn =
      Plug.Test.conn(
        :post,
        "/api/v1/authority/revalidate",
        Jason.encode!(%{
          "operation" => op,
          "authorization" => auth,
          "did_signature" => sign(c.next_private, AuthorVerifier.canonical_json(auth))
        })
      )
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> AnsibleAppview.Web.Router.call([])

    assert conn.status == 200
    assert %{"revalidated" => true, "indexed" => 1} = Jason.decode!(conn.resp_body)
    assert {:ok, bound} = Witness.observe(op, payload)
    assert bound["public_key_hex"] == c.initial["identity_key"]
    assert bound["observation_kind"] == "owner_revalidated"
  end

  test "signed revocation cannot be hidden by replaying a valid old delegation", c do
    # A real WebAuthn fixture; only the independent observer's clock is
    # simulated at the original ceremony, not supplied via any HTTP endpoint.
    op =
      File.read!(Path.join(__DIR__, "fixtures/witness_author_proof_v1.json")) |> Jason.decode!()

    payload = op["payload"] |> Base.decode64!() |> Jason.decode!()
    {:ok, at, _} = DateTime.from_iso8601(payload["web_operation"]["created_at"])
    {:ok, _} = Witness.checkpoint(op["author_did"], op["identity_chain"])
    assert {:ok, _} = Witness.observe(op, payload, at)

    assert {:ok, %{revoked: true}} =
             Witness.revoke(op["fixture_revocation"], op["fixture_revocation_signature"], at)

    assert {:ok, _} = Witness.observe(op, payload, DateTime.add(at, 86400))
    Repo.query!("DELETE FROM authority_observations WHERE did=$1", [op["author_did"]])
    assert {:error, :delegation_not_current} = Witness.observe(op, payload, at)
    Repo.query!("DELETE FROM authority_revocations WHERE did=$1", [op["author_did"]])

    assert {:error, :delegation_not_current} =
             Witness.observe(op, payload, DateTime.add(at, 86400))

    # Native/root revocation: unauthorised old key is rejected after rotation.
    {:ok, _} = Witness.checkpoint(c.did, [c.initial, c.rotated])

    body = %{
      "type" => "io.trisaura.identity.webCredentialRevocation",
      "version" => 1,
      "subject_did" => c.did,
      "credential_id" => Base.url_encode64("credential", padding: false),
      "revoked_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "nonce" => "revocation-nonce-12345"
    }

    assert {:error, _} =
             Witness.revoke(body, sign(c.private, AuthorVerifier.canonical_json(body)))

    assert {:ok, %{revoked: true}} =
             Witness.revoke(body, sign(c.next_private, AuthorVerifier.canonical_json(body)))

    assert {:ok, %{revoked: true}} =
             Witness.revoke(body, sign(c.next_private, AuthorVerifier.canonical_json(body)))
  end

  test "source cannot backdate a recovery to skip observer grace; veto is durable", c do
    {:ok, _} = Witness.checkpoint(c.did, [c.initial])
    recovery = Map.put(c.rotated, "reason", "recovery")
    body = AnchorEncoding.canonical_body(recovery)

    recovery =
      Map.merge(recovery, %{
        "sig" => sign(c.next_private, body),
        "recovery_proof" => sign(c.private, body)
      })

    assert {:error, :recovery_observation_pending} =
             Witness.checkpoint(c.did, [c.initial, recovery])

    assert {:ok, %{vetoed: true}} =
             Witness.veto(c.did, AnchorEncoding.compute_cid(recovery), sign(c.private, body))

    Repo.query!("UPDATE authority_frontiers SET pending_since=$2 WHERE did=$1", [
      c.did,
      DateTime.add(DateTime.utc_now(), -400_000)
    ])

    assert {:error, :recovery_observation_pending} =
             Witness.checkpoint(c.did, [c.initial, recovery])
  end

  test "multiple recoveries cannot borrow a prior recovery observation clock", c do
    {:ok, _} = Witness.checkpoint(c.did, [c.initial])
    recovery = Map.put(c.rotated, "reason", "recovery")
    body = AnchorEncoding.canonical_body(recovery)

    recovery =
      Map.merge(recovery, %{
        "sig" => sign(c.next_private, body),
        "recovery_proof" => sign(c.private, body)
      })

    assert {:error, :recovery_observation_pending} =
             Witness.checkpoint(c.did, [c.initial, recovery])

    Repo.query!("UPDATE authority_frontiers SET pending_since=$2 WHERE did=$1", [
      c.did,
      DateTime.add(DateTime.utc_now(), -400_000)
    ])

    next =
      Map.merge(recovery, %{
        "identity_key" => c.initial["identity_key"],
        "prev_anchor_cid" => AnchorEncoding.compute_cid(recovery),
        "created_at" => "2026-03-01T00:00:00Z"
      })

    next_body = AnchorEncoding.canonical_body(next)

    next =
      Map.merge(next, %{
        "sig" => sign(c.private, next_body),
        "recovery_proof" => sign(c.next_private, next_body)
      })

    assert {:error, :recovery_observation_pending} =
             Witness.checkpoint(c.did, [c.initial, recovery, next])

    assert {:ok, _} = Witness.checkpoint(c.did, [c.initial, recovery])

    assert {:error, :recovery_observation_pending} =
             Witness.checkpoint(c.did, [c.initial, recovery, next])
  end

  test "a backdated dual migration cannot use the target's obsolete authority", c do
    commitment = %{
      "method" => "did:elix",
      "method_version" => 1,
      "genesis_key" => c.initial["identity_key"],
      "genesis_nonce" => hex(:crypto.strong_rand_bytes(32))
    }

    {:ok, target_did} = DidElix.derive_v1(commitment)

    initial =
      Map.merge(c.initial, %{
        "schema_version" => 4,
        "did" => target_did,
        "genesis_commitment" => commitment
      })

    initial = Map.put(initial, "sig", sign(c.private, AnchorEncoding.canonical_body(initial)))

    rotated =
      Map.merge(c.rotated, %{
        "schema_version" => 4,
        "did" => target_did,
        "genesis_commitment" => commitment,
        "prev_anchor_cid" => AnchorEncoding.compute_cid(initial)
      })

    rotated_body = AnchorEncoding.canonical_body(rotated)

    rotated =
      Map.merge(rotated, %{
        "sig" => sign(c.next_private, rotated_body),
        "device_sig" => sign(c.private, rotated_body)
      })

    c = %{c | did: target_did, initial: initial, rotated: rotated}
    {:ok, _} = Witness.checkpoint(c.did, [c.initial, c.rotated])
    {source_pub, source_key} = :crypto.generate_key(:eddsa, :ed25519)
    source_did = DidElix.derive(hex(source_pub), "source.elix.cool")

    anchor =
      Map.merge(c.initial, %{
        "did" => source_did,
        "identity_key" => hex(source_pub),
        "handle" => "source.elix.cool"
      })

    anchor = anchor |> Map.put("schema_version", 3) |> Map.delete("genesis_commitment")
    anchor = Map.put(anchor, "sig", sign(source_key, AnchorEncoding.canonical_body(anchor)))
    {:ok, _} = Witness.checkpoint(source_did, [anchor])

    {op, payload} =
      operation(%{did: source_did, initial: anchor}, "obsolete-migration", source_key)

    evidence = %{
      "type" => "io.trisaura.identity.migration",
      "version" => 1,
      "legacy_did" => source_did,
      "v1_did" => c.did,
      "created_at" => "2026-01-02T00:00:00Z",
      "target_chain" => [c.initial]
    }

    body = AuthorVerifier.migration_body(evidence)

    evidence =
      Map.merge(evidence, %{
        "legacy_sig" => sign(source_key, body),
        "v1_sig" => sign(c.private, body)
      })

    op = op |> Map.put("identity_migration", evidence) |> Map.put("canonical_author_did", c.did)
    assert AuthorVerifier.bind_provenance(op, payload)["canonical_author_did"] == c.did
    assert {:ok, bound} = Witness.observe(op, payload)
    assert bound["canonical_author_did"] == source_did
  end

  test "concurrent first observation and rotation share one committed ordering", c do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> Witness.checkpoint(c.did, [c.initial]) end)

    try do
      {op, payload} = operation(c, "concurrent", c.private)

      first =
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn -> Witness.observe(op, payload) end)
        end)

      rotation =
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
            Witness.checkpoint(c.did, [c.initial, c.rotated])
          end)
        end)

      observed = Task.await(first)
      assert {:ok, _} = Task.await(rotation)

      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        case observed do
          {:ok, _} ->
            assert {:ok, _} = Witness.observe(op, payload)

          {:error, :unobserved_obsolete_authority} ->
            assert {:error, :unobserved_obsolete_authority} = Witness.observe(op, payload)
        end

        {new, new_payload} = operation(c, "after-race", c.private)
        assert {:error, :unobserved_obsolete_authority} = Witness.observe(new, new_payload)
      end)
    after
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        for table <-
              ~w(authority_pending authority_observations authority_revocations authority_frontiers),
            do: Repo.query!("DELETE FROM #{table} WHERE did=$1", [c.did])
      end)
    end
  end

  test "HTTP checkpoint and revocation endpoints verify root proof", c do
    call = fn path, body ->
      Plug.Test.conn(:post, path, Jason.encode!(body))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> AnsibleAppview.Web.Router.call([])
    end

    assert call.("/api/v1/authority/checkpoint", %{"did" => c.did, "chain" => [c.initial]}).status ==
             200

    body = %{
      "type" => "io.trisaura.identity.webCredentialRevocation",
      "version" => 1,
      "subject_did" => c.did,
      "credential_id" => Base.url_encode64("cred", padding: false),
      "revoked_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "nonce" => "endpoint-revocation-12345"
    }

    assert call.("/api/v1/authority/revoke", %{"revocation" => body, "did_signature" => "bad"}).status ==
             409

    assert call.("/api/v1/authority/revoke", %{
             "revocation" => body,
             "did_signature" => sign(c.private, AuthorVerifier.canonical_json(body))
           }).status == 200
  end
end
