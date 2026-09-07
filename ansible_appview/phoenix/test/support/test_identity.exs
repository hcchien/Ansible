defmodule AnsibleAppview.TestIdentity do
  @moduledoc "Synthetic self-certifying identities for projection fixtures; never loaded in production."
  alias AnsibleAppview.{DidElix, SigVerifier, SigningPayload}
  alias AnsibleAppview.Identity.AnchorEncoding
  defp hex(x), do: Base.encode16(x, case: :lower)
  defp sign(key, body), do: :crypto.sign(:eddsa, :none, body, [key, :ed25519]) |> hex()

  def did(label) do
    seed = :crypto.hash(:sha256, "appview-test:" <> label)
    {pub, _} = :crypto.generate_key(:eddsa, :ed25519, seed)

    commitment = %{
      "method" => "did:elix",
      "method_version" => 1,
      "genesis_key" => hex(pub),
      "genesis_nonce" => hex(seed)
    }

    legacy = String.ends_with?(label, "-legacy")

    did =
      if legacy,
        do: DidElix.derive(hex(pub), "test.elix.cool"),
        else: elem(DidElix.derive_v1(commitment), 1)

    anchor = %{
      "schema_version" => if(legacy, do: 3, else: 4),
      "did" => did,
      "identity_key" => hex(pub),
      "identity_key_algorithm" => "ed25519",
      "genesis_commitment" => commitment,
      "handle" => "test.elix.cool",
      "custody_class" => "software",
      "devices" => [],
      "also_known_as" => [],
      "prev_anchor_cid" => nil,
      "reason" => "initial",
      "created_at" => "2026-01-01T00:00:00Z"
    }

    anchor = Map.put(anchor, "sig", sign(seed, AnchorEncoding.canonical_body(anchor)))
    :persistent_term.put({__MODULE__, did}, {seed, hex(pub), anchor})
    did
  end

  # Preserve deliberate bad-signature test cases while migrating previously
  # arbitrary DID labels to true self-certifying fixtures. This only runs at
  # fixture construction; the production Folder still checks every signature.
  def attach(op) do
    {seed, pub, anchor} = :persistent_term.get({__MODULE__, op["author_did"]})

    {:ok, _} = AnsibleAppview.Authority.Witness.checkpoint(op["author_did"], [anchor])

    valid =
      SigVerifier.verify_ed25519(op["public_key_hex"], SigningPayload.build(op), op["signature"])

    op =
      op
      |> Map.put("identity_chain", [anchor])
      |> Map.put("public_key_hex", pub)
      |> Map.put_new("anchor_expires_at", "2099-01-01T00:00:00Z")
      |> Map.put(
        "signature",
        if(valid, do: sign(seed, SigningPayload.build(op)), else: String.duplicate("00", 64))
      )

    target = op["canonical_author_did"]

    if is_binary(target) and target != op["author_did"] do
      {target_seed, _, target_anchor} = :persistent_term.get({__MODULE__, target})

      {:ok, _} = AnsibleAppview.Authority.Witness.checkpoint(target, [target_anchor])

      evidence = %{
        "type" => "io.trisaura.identity.migration",
        "version" => 1,
        "legacy_did" => op["author_did"],
        "v1_did" => target,
        "created_at" => "2026-01-02T00:00:00Z"
      }

      body =
        ~s({"type":"io.trisaura.identity.migration","version":1,"legacy_did":) <>
          Jason.encode!(op["author_did"]) <>
          ~s(,"v1_did":) <> Jason.encode!(target) <> ~s(,"created_at":"2026-01-02T00:00:00Z"})

      Map.put(
        op,
        "identity_migration",
        Map.merge(evidence, %{
          "legacy_sig" => sign(seed, body),
          "v1_sig" => sign(target_seed, body),
          "target_chain" => [target_anchor]
        })
      )
    else
      op
    end
  end

  def public_key(did), do: elem(:persistent_term.get({__MODULE__, did}), 1)
end
