defmodule AnsibleRelay.Identity.RecoveryStoreTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.{DidAccountCache, Repo}
  alias AnsibleRelay.Identity.{AnchorStore, RecoveryStore}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case DidAccountCache.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    DidAccountCache.reset()
    AnchorStore.reset()
    :ok
  end

  test "recovery codes are hash-only, one-time, delayed, and audited" do
    did = "did:plc:recovery-test"
    {old_public, old_private} = keypair()
    initial = anchor(did, old_public, old_private, "initial", nil)
    assert {:ok, :active, active} = AnchorStore.submit(initial)

    code = "ABCDE-FGHIJ-KLMNO-PQRST"
    generated_at = "2026-07-22T12:00:00Z"

    configuration = %{
      "type" => "io.trisaura.identity.recoveryCodes",
      "version" => 1,
      "did" => did,
      "generated_at" => generated_at,
      "code_hashes" => [
        %{
          "id" => "code-1",
          "hash" => RecoveryStore.hash_code(did, code),
          "hint" => "ABCD"
        }
      ]
    }

    signed =
      Map.put(
        configuration,
        "signature",
        sign(old_private, RecoveryStore.canonical_configuration(configuration))
      )

    assert {:ok, %{"configured" => true, "remaining" => 1}} =
             RecoveryStore.configure(signed)

    {new_public, new_private} = keypair()
    recovery = anchor(did, new_public, new_private, "recovery", active.anchor_cid)

    assert {:ok, {:pending, pending}} = RecoveryStore.recover(recovery, code)
    assert pending.grace_until != nil
    assert RecoveryStore.status(did)["remaining"] == 0
    assert RecoveryStore.status(did)["used"] == 1
    assert {:error, :invalid_recovery_code} = RecoveryStore.recover(recovery, code)

    event_types = RecoveryStore.audit(did) |> Enum.map(& &1.event_type)
    assert "recovery_codes_configured" in event_types
    assert "recovery_started" in event_types
    assert "recovery_pending" in event_types
  end

  test "an invalid code never consumes an active code" do
    did = "did:plc:recovery-invalid"
    {public, private} = keypair()

    assert {:ok, :active, active} =
             AnchorStore.submit(anchor(did, public, private, "initial", nil))

    code = "ABCDE-FGHIJ-KLMNO-PQRST"

    config = %{
      "type" => "io.trisaura.identity.recoveryCodes",
      "version" => 1,
      "did" => did,
      "generated_at" => "2026-07-22T12:00:00Z",
      "code_hashes" => [
        %{"id" => "code-1", "hash" => RecoveryStore.hash_code(did, code), "hint" => "ABCD"}
      ]
    }

    assert {:ok, _} =
             RecoveryStore.configure(
               Map.put(
                 config,
                 "signature",
                 sign(private, RecoveryStore.canonical_configuration(config))
               )
             )

    {new_public, new_private} = keypair()
    recovery = anchor(did, new_public, new_private, "recovery", active.anchor_cid)
    assert {:error, :invalid_recovery_code} = RecoveryStore.recover(recovery, "WRONG-CODE")
    assert RecoveryStore.status(did)["remaining"] == 1
  end

  test "v1 rejects recovery-code-only authority without consuming the code" do
    {old_public, old_private} = keypair()

    commitment = %{
      "method" => "did:elix",
      "method_version" => 1,
      "genesis_key" => old_public,
      "genesis_nonce" => String.duplicate("01", 32)
    }

    {:ok, did} = AnsibleRelay.DidElix.derive_v1(commitment)

    initial =
      v1_anchor(did, old_public, old_private, commitment, "initial", nil)

    assert {:ok, :active, active} = AnchorStore.submit(initial)

    code = "ABCDE-FGHIJ-KLMNO-PQRST"

    config = %{
      "type" => "io.trisaura.identity.recoveryCodes",
      "version" => 1,
      "did" => did,
      "generated_at" => "2026-08-19T12:00:00Z",
      "code_hashes" => [
        %{"id" => "code-1", "hash" => RecoveryStore.hash_code(did, code), "hint" => "ABCD"}
      ]
    }

    assert {:ok, _} =
             RecoveryStore.configure(
               Map.put(
                 config,
                 "signature",
                 sign(old_private, RecoveryStore.canonical_configuration(config))
               )
             )

    {new_public, new_private} = keypair()

    recovery =
      v1_anchor(
        did,
        new_public,
        new_private,
        commitment,
        "recovery",
        active.anchor_cid
      )

    assert {:error, :invalid_recovery_proof} = RecoveryStore.recover(recovery, code)
    assert RecoveryStore.status(did)["remaining"] == 1
    assert RecoveryStore.status(did)["used"] == 0
  end

  defp anchor(did, public, private, reason, previous_cid) do
    unsigned = %{
      "type" => "io.trisaura.identity.anchor",
      "schema_version" => 1,
      "did" => did,
      "handle" => "recovery.elix.cool",
      "identity_key" => public,
      "also_known_as" => [],
      "custody_class" => "software",
      "devices" => [],
      "prev_anchor_cid" => previous_cid,
      "reason" => reason,
      "created_at" => "2026-07-22T12:00:00Z"
    }

    Map.put(unsigned, "sig", sign(private, AnchorStore.canonical_body(unsigned)))
  end

  defp v1_anchor(did, public, private, commitment, reason, previous_cid) do
    unsigned = %{
      "type" => "io.trisaura.identity.anchor",
      "schema_version" => 4,
      "did" => did,
      "handle" => "recovery.elix.cool",
      "identity_key" => public,
      "identity_key_algorithm" => "ed25519",
      "genesis_commitment" => commitment,
      "also_known_as" => [],
      "custody_class" => "software",
      "devices" => [],
      "prev_anchor_cid" => previous_cid,
      "reason" => reason,
      "created_at" => "2026-08-19T12:00:00.000Z"
    }

    Map.put(unsigned, "sig", sign(private, AnchorStore.canonical_body(unsigned)))
  end

  defp keypair do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public, case: :lower), private}
  end

  defp sign(private, message) do
    :crypto.sign(:eddsa, :none, message, [private, :ed25519])
    |> Base.encode16(case: :lower)
  end
end
