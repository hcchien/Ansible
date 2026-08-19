defmodule AnsibleRelay.DidElixV1ConformanceTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{DidElix, Repo, SigVerifier}
  alias AnsibleRelay.Identity.{AnchorStore, FederatedResolver, MigrationStore}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])
  @anchor_type "io.trisaura.identity.anchor"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case AnsibleRelay.DidAccountCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    AnsibleRelay.DidAccountCache.reset()
    AnchorStore.reset()
    :ok
  end

  defp keypair do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public, case: :lower), private}
  end

  defp sign(private, message) do
    :crypto.sign(:eddsa, :none, message, [private, :ed25519])
    |> Base.encode16(case: :lower)
  end

  defp commitment(key, nonce \\ String.duplicate("01", 32)) do
    %{
      "method" => "did:elix",
      "method_version" => 1,
      "genesis_key" => key,
      "genesis_nonce" => nonce
    }
  end

  defp v1_anchor(fields, private, authorization_private \\ nil) do
    unsigned =
      Map.merge(
        %{
          "type" => @anchor_type,
          "schema_version" => 4,
          "identity_key_algorithm" => "ed25519",
          "also_known_as" => [],
          "custody_class" => "software",
          "devices" => [],
          "prev_anchor_cid" => nil,
          "reason" => "initial",
          "created_at" => "2026-08-19T00:00:00.000Z"
        },
        fields
      )

    body = AnchorStore.canonical_body(unsigned)

    signed = Map.put(unsigned, "sig", sign(private, body))

    if authorization_private,
      do: Map.put(signed, "device_sig", sign(authorization_private, body)),
      else: signed
  end

  defp legacy_anchor(key, private, handle) do
    did = DidElix.derive(key, handle)

    unsigned = %{
      "type" => @anchor_type,
      "schema_version" => 3,
      "did" => did,
      "handle" => handle,
      "identity_key" => key,
      "identity_key_algorithm" => "ed25519",
      "also_known_as" => [],
      "custody_class" => "software",
      "devices" => [],
      "prev_anchor_cid" => nil,
      "reason" => "initial",
      "created_at" => "2026-08-19T00:00:00.000Z"
    }

    {did, Map.put(unsigned, "sig", sign(private, AnchorStore.canonical_body(unsigned)))}
  end

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp get(path), do: conn(:get, path) |> Router.call(@router_opts)

  defp portable_vectors do
    __DIR__
    |> Path.join("../../../docs/architecture/did_elix_v1_conformance_vectors.json")
    |> File.read!()
    |> Jason.decode!()
  end

  test "portable vectors verify exact bytes, signatures, transitions, and migration" do
    vectors = portable_vectors()
    commitment = vectors["genesis"]["commitment"]
    did = vectors["genesis"]["did"]

    assert DidElix.canonical_v1_commitment(commitment) ==
             vectors["genesis"]["canonical_commitment"]

    assert DidElix.derive_v1(commitment) == {:ok, did}

    registration = vectors["registration"]
    genesis_key = vectors["test_only_keys"]["genesis"]["public_key"]

    assert DidElix.registration_payload(registration["relay_nonce"], did, commitment) ==
             registration["canonical_payload"]

    assert SigVerifier.verify_ed25519(
             genesis_key,
             registration["canonical_payload"],
             registration["signature"]
           )

    for name <- ~w(genesis rotation recovery) do
      vector = vectors["anchors"][name]
      object = vector["object"]
      assert AnchorStore.canonical_body(object) == vector["canonical_body"]
      assert AnchorStore.compute_cid(object) == vector["cid"]

      assert SigVerifier.verify_ed25519(
               object["identity_key"],
               vector["canonical_body"],
               object["sig"]
             )
    end

    chain = vectors["anchors"]["resolved_chain"]
    assert FederatedResolver.verified_chain?(did, chain)

    [genesis, rotation, recovery] = chain

    assert SigVerifier.verify_ed25519(
             genesis["identity_key"],
             AnchorStore.canonical_body(rotation),
             rotation["device_sig"]
           )

    assert SigVerifier.verify_ed25519(
             rotation["identity_key"],
             AnchorStore.canonical_body(recovery),
             recovery["recovery_proof"]
           )

    legacy = vectors["legacy"]
    assert AnchorStore.canonical_body(legacy["object"]) == legacy["canonical_body"]
    assert AnchorStore.compute_cid(legacy["object"]) == legacy["cid"]

    assert DidElix.matches?(
             legacy["object"]["did"],
             legacy["object"]["identity_key"],
             legacy["object"]["handle"]
           )

    migration = vectors["migration"]
    assert MigrationStore.canonical_body(migration["object"]) == migration["canonical_body"]

    assert SigVerifier.verify_ed25519(
             legacy["object"]["identity_key"],
             migration["canonical_body"],
             migration["object"]["legacy_sig"]
           )

    assert SigVerifier.verify_ed25519(
             recovery["identity_key"],
             migration["canonical_body"],
             migration["object"]["v1_sig"]
           )

    invalid = Map.new(vectors["invalid"], &{&1["name"], &1})

    assert DidElix.validate_v1_commitment(invalid["uppercase_nonce"]["commitment"]) ==
             {:error, :invalid_genesis_commitment}

    assert DidElix.validate_v1_commitment(invalid["unknown_commitment_property"]["commitment"]) ==
             {:error, :invalid_genesis_commitment}

    for name <-
          ~w(commitment_substitution invalid_signature missing_link fork missing_previous_authority reason_key_mismatch) do
      candidate = invalid[name]["anchor"]

      candidate_chain =
        case name do
          name when name in ~w(commitment_substitution invalid_signature) -> [candidate]
          "fork" -> [genesis, rotation, candidate]
          _ -> [genesis, candidate]
        end

      refute FederatedResolver.verified_chain?(did, candidate_chain),
             "#{name} must fail closed"
    end
  end

  test "portable invalid vectors fail closed at the Relay boundary" do
    vectors = portable_vectors()
    genesis = vectors["anchors"]["genesis"]["object"]
    assert post_json("/api/v1/identity/anchor", genesis).status == 201

    invalid = Map.new(vectors["invalid"], &{&1["name"], &1})

    reason_response =
      post_json(
        "/api/v1/identity/anchor",
        invalid["reason_key_mismatch"]["anchor"]
      )

    assert reason_response.status == 422
    assert Jason.decode!(reason_response.resp_body)["error"] == "invalid_transition"

    malformed_time = Map.put(genesis, "created_at", "2026-08-19T00:00:00.000000Z")
    malformed_response = post_json("/api/v1/identity/anchor", malformed_time)
    assert malformed_response.status == 422
    assert Jason.decode!(malformed_response.resp_body)["error"] == "malformed_anchor"

    extended =
      Map.put(
        genesis,
        "genesis_commitment",
        invalid["unknown_commitment_property"]["commitment"]
      )

    extended_response = post_json("/api/v1/identity/anchor", extended)
    assert extended_response.status == 422

    assert Jason.decode!(extended_response.resp_body)["error"] ==
             "invalid_genesis_commitment"
  end

  test "schema v4 canonical bytes and CID are fixed cross-runtime vectors" do
    key = String.duplicate("aa", 32)
    nonce = String.duplicate("01", 32)
    did = "did:elix:zlg5xyogxphkrhi453x3gxpubfxdveaev6xmgnpcw3zus4653mfyq"

    anchor = %{
      "type" => @anchor_type,
      "schema_version" => 4,
      "did" => did,
      "handle" => "alice.elix.cool",
      "identity_key" => key,
      "identity_key_algorithm" => "ed25519",
      "genesis_commitment" => commitment(key, nonce),
      "also_known_as" => [],
      "custody_class" => "software",
      "devices" => [],
      "prev_anchor_cid" => nil,
      "reason" => "initial",
      "created_at" => "2026-08-19T00:00:00.000Z"
    }

    expected =
      ~s({"type":"io.trisaura.identity.anchor","schema_version":4,"did":"#{did}","handle":"alice.elix.cool","identity_key":"#{key}","identity_key_algorithm":"ed25519","genesis_commitment":{"method":"did:elix","method_version":1,"genesis_key":"#{key}","genesis_nonce":"#{nonce}"},"also_known_as":[],"custody_class":"software","devices":[],"prev_anchor_cid":null,"reason":"initial","created_at":"2026-08-19T00:00:00.000Z"})

    assert AnchorStore.canonical_body(anchor) == expected

    assert AnchorStore.compute_cid(anchor) ==
             "sha256:" <> Base.encode16(:crypto.hash(:sha256, expected), case: :lower)
  end

  test "v1 genesis and dual-signed rotation resolve as a verified full chain" do
    {genesis_key, genesis_private} = keypair()
    genesis_commitment = commitment(genesis_key)
    {:ok, did} = DidElix.derive_v1(genesis_commitment)

    genesis =
      v1_anchor(
        %{
          "did" => did,
          "handle" => "alice.elix.cool",
          "identity_key" => genesis_key,
          "genesis_commitment" => genesis_commitment
        },
        genesis_private
      )

    assert post_json("/api/v1/identity/anchor", genesis).status == 201
    genesis_cid = AnchorStore.compute_cid(genesis)

    {rotated_key, rotated_private} = keypair()

    rotation =
      v1_anchor(
        %{
          "did" => did,
          "handle" => "alice-renamed.elix.cool",
          "identity_key" => rotated_key,
          "genesis_commitment" => genesis_commitment,
          "prev_anchor_cid" => genesis_cid,
          "reason" => "rotation",
          "created_at" => "2026-08-19T01:00:00.000Z"
        },
        rotated_private,
        genesis_private
      )

    assert post_json("/api/v1/identity/anchor", rotation).status == 200

    response = get("/api/v1/identity/chain/#{did}")
    assert response.status == 200
    assert %{"anchors" => [served_genesis, served_rotation]} = Jason.decode!(response.resp_body)
    assert served_genesis["anchor_cid"] == genesis_cid
    assert served_rotation["prev_anchor_cid"] == genesis_cid
    assert served_rotation["identity_key"] == rotated_key
    assert served_rotation["genesis_commitment"] == genesis_commitment
  end

  test "v1 rejects missing commitment, bad signature, missing link, and fork" do
    {key, private} = keypair()
    genesis_commitment = commitment(key)
    {:ok, did} = DidElix.derive_v1(genesis_commitment)

    missing =
      v1_anchor(
        %{"did" => did, "handle" => "bad.elix.cool", "identity_key" => key},
        private
      )

    assert post_json("/api/v1/identity/anchor", missing).status == 422

    genesis =
      v1_anchor(
        %{
          "did" => did,
          "handle" => "good.elix.cool",
          "identity_key" => key,
          "genesis_commitment" => genesis_commitment
        },
        private
      )

    assert post_json("/api/v1/identity/anchor", genesis).status == 201
    cid = AnchorStore.compute_cid(genesis)
    {new_key, new_private} = keypair()

    invalid_sig =
      v1_anchor(
        %{
          "did" => did,
          "handle" => "good.elix.cool",
          "identity_key" => new_key,
          "genesis_commitment" => genesis_commitment,
          "prev_anchor_cid" => cid,
          "reason" => "rotation"
        },
        new_private,
        private
      )
      |> Map.put("sig", String.duplicate("00", 64))

    assert post_json("/api/v1/identity/anchor", invalid_sig).status == 401

    missing_link =
      v1_anchor(
        %{
          "did" => did,
          "handle" => "good.elix.cool",
          "identity_key" => new_key,
          "genesis_commitment" => genesis_commitment,
          "prev_anchor_cid" => "sha256:" <> String.duplicate("00", 32),
          "reason" => "rotation"
        },
        new_private,
        private
      )

    assert post_json("/api/v1/identity/anchor", missing_link).status == 409

    accepted =
      v1_anchor(
        %{
          "did" => did,
          "handle" => "good.elix.cool",
          "identity_key" => new_key,
          "genesis_commitment" => genesis_commitment,
          "prev_anchor_cid" => cid,
          "reason" => "rotation"
        },
        new_private,
        private
      )

    assert post_json("/api/v1/identity/anchor", accepted).status == 200

    {fork_key, fork_private} = keypair()

    fork =
      v1_anchor(
        %{
          "did" => did,
          "handle" => "fork.elix.cool",
          "identity_key" => fork_key,
          "genesis_commitment" => genesis_commitment,
          "prev_anchor_cid" => cid,
          "reason" => "rotation"
        },
        fork_private,
        private
      )

    assert post_json("/api/v1/identity/anchor", fork).status == 409
  end

  test "recovery authorization is retained for independent chain verification" do
    {key, private} = keypair()
    genesis_commitment = commitment(key)
    {:ok, did} = DidElix.derive_v1(genesis_commitment)

    genesis =
      v1_anchor(
        %{
          "did" => did,
          "handle" => "recover.elix.cool",
          "identity_key" => key,
          "genesis_commitment" => genesis_commitment
        },
        private
      )

    assert post_json("/api/v1/identity/anchor", genesis).status == 201
    {new_key, new_private} = keypair()

    unsigned =
      v1_anchor(
        %{
          "did" => did,
          "handle" => "recover.elix.cool",
          "identity_key" => new_key,
          "genesis_commitment" => genesis_commitment,
          "prev_anchor_cid" => AnchorStore.compute_cid(genesis),
          "reason" => "recovery"
        },
        new_private
      )

    proof = sign(private, AnchorStore.canonical_body(unsigned))
    response = post_json("/api/v1/identity/anchor", Map.put(unsigned, "recovery_proof", proof))
    assert response.status == 202
    assert {:ok, [_]} = AnchorStore.promote_due(DateTime.add(DateTime.utc_now(), 4, :day))

    chain = get("/api/v1/identity/chain/#{did}")
    assert chain.status == 200
    assert %{"anchors" => [_, %{"recovery_proof" => ^proof}]} = Jason.decode!(chain.resp_body)
  end

  test "legacy migration is dual-signed, resolvable, and reflected as an alias" do
    original_persistence = Application.get_env(:ansible_relay, :persist_did_accounts)
    Application.put_env(:ansible_relay, :persist_did_accounts, true)

    on_exit(fn ->
      Application.put_env(:ansible_relay, :persist_did_accounts, original_persistence)
    end)

    {legacy_key, legacy_private} = keypair()
    {legacy_did, legacy} = legacy_anchor(legacy_key, legacy_private, "legacy.elix.cool")
    assert post_json("/api/v1/identity/anchor", legacy).status == 201

    nullifier = "migration-person-#{System.unique_integer([:positive])}"
    :ok = AnsibleRelay.IdentityCache.put(legacy_did, legacy_key, nullifier)

    {v1_key, v1_private} = keypair()
    genesis_commitment = commitment(v1_key, String.duplicate("04", 32))
    {:ok, v1_did} = DidElix.derive_v1(genesis_commitment)

    v1 =
      v1_anchor(
        %{
          "did" => v1_did,
          "handle" => "legacy.elix.cool",
          "identity_key" => v1_key,
          "genesis_commitment" => genesis_commitment
        },
        v1_private
      )

    assert post_json("/api/v1/identity/anchor", v1).status == 201

    migration = %{
      "type" => "io.trisaura.identity.migration",
      "version" => 1,
      "legacy_did" => legacy_did,
      "v1_did" => v1_did,
      "created_at" => "2026-08-19T02:00:00.000Z"
    }

    body = AnsibleRelay.Identity.MigrationStore.canonical_body(migration)

    response =
      post_json(
        "/api/v1/identity/migration",
        migration
        |> Map.put("legacy_sig", sign(legacy_private, body))
        |> Map.put("v1_sig", sign(v1_private, body))
      )

    assert response.status == 201
    migration_response = Jason.decode!(response.resp_body)
    assert migration_response["created_at"] == migration["created_at"]
    assert migration_response["state"] == "completed"
    assert migration_response["handle"] == "legacy.elix.cool"
    assert get("/api/v1/identity/migration/#{legacy_did}").status == 200

    # Handle/trust routing switches through the committed proof without
    # rewriting the durable legacy account or its signed history.
    assert {:ok, ^v1_did} =
             AnsibleRelay.DidAccountCache.get_by_handle("legacy.elix.cool")

    assert {:ok, projected} = AnsibleRelay.DidAccountCache.get(v1_did)
    assert projected.public_key_hex == v1_key
    assert projected.handle == "legacy.elix.cool"

    assert {:ok, assurance} = AnsibleRelay.IdentityCache.get(v1_did)
    assert assurance.public_key_hex == v1_key
    assert assurance.nullifier == nullifier

    assert Repo.get_by(AnsibleRelay.Db.IdentityRecoveryAuditEvent,
             did: v1_did,
             event_type: "identity_migrated"
           )

    blocked_legacy_anchor = post_json("/api/v1/identity/anchor", legacy)
    assert blocked_legacy_anchor.status == 409
    assert Jason.decode!(blocked_legacy_anchor.resp_body)["error"] == "identity_migrated"

    retry_response =
      post_json(
        "/api/v1/identity/migration",
        migration
        |> Map.put("legacy_sig", sign(legacy_private, body))
        |> Map.put("v1_sig", sign(v1_private, body))
      )

    assert retry_response.status == 200
    assert Jason.decode!(retry_response.resp_body)["v1_did"] == v1_did

    document = get("/api/v1/identity/did/#{legacy_did}")
    assert document.status == 200
    assert v1_did in Jason.decode!(document.resp_body)["alsoKnownAs"]

    universal = get("/1.0/identifiers/#{v1_did}")
    assert universal.status == 200
    universal_body = Jason.decode!(universal.resp_body)
    assert universal_body["didDocument"]["id"] == v1_did
    assert universal_body["didResolutionMetadata"]["methodVersion"] == 1
    assert legacy_did in universal_body["didDocumentMetadata"]["equivalentId"]
  end
end
