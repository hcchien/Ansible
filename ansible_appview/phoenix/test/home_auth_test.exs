defmodule AnsibleAppview.HomeAuthTest do
  use ExUnit.Case, async: false

  alias AnsibleAppview.HomeAuth
  alias AnsibleAppview.Ingest.Folder
  alias AnsibleAppview.SigningPayload

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AnsibleAppview.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AnsibleAppview.Repo, {:shared, self()})
    :ok
  end

  defp keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  # Fold a public murmur so the DID<->pubkey binding exists in feed_items.
  defp seed_binding(did, pub, priv) do
    op = %{
      "log_id" => System.unique_integer([:positive]),
      "op_id" => "op-#{System.unique_integer([:positive])}",
      "author_did" => did,
      "entity_type" => "murmur",
      "entity_id" => "e-#{System.unique_integer([:positive])}",
      "op_type" => "insert",
      "payload" => Base.encode64(Jason.encode!(%{"body" => "hi", "visibility" => "public"})),
      "public_key_hex" => pub,
      "reputation_tier" => "basic",
      "received_at" => "2026-06-05T00:00:00Z"
    }

    sig = :crypto.sign(:eddsa, :none, SigningPayload.build(op), [priv, :ed25519]) |> Base.encode16(case: :lower)
    Folder.apply_ops([Map.put(op, "signature", sig)])
  end

  defp signed_headers(did, pub, priv, ts) do
    challenge = HomeAuth.challenge(did, ts)
    sig = :crypto.sign(:eddsa, :none, challenge, [priv, :ed25519]) |> Base.encode16(case: :lower)

    %{
      "x-reader-did" => did,
      "x-reader-public-key" => pub,
      "x-reader-timestamp" => Integer.to_string(ts),
      "x-reader-signature" => sig
    }
  end

  test "authorizes a correctly-signed request from the DID owner" do
    did = "did:key:owner#{System.unique_integer([:positive])}"
    {pub, priv} = keypair()
    seed_binding(did, pub, priv)

    headers = signed_headers(did, pub, priv, System.os_time(:second))
    assert :ok = HomeAuth.authorize(headers, did)
  end

  test "rejects a request whose reader param != signed did" do
    did = "did:key:owner#{System.unique_integer([:positive])}"
    {pub, priv} = keypair()
    seed_binding(did, pub, priv)

    headers = signed_headers(did, pub, priv, System.os_time(:second))
    assert {:error, :unauthorized} = HomeAuth.authorize(headers, "did:key:someone-else")
  end

  test "rejects a self-minted keypair impersonating another DID (key not bound)" do
    victim = "did:key:victim#{System.unique_integer([:positive])}"
    {vpub, vpriv} = keypair()
    seed_binding(victim, vpub, vpriv)

    # Attacker generates their OWN keypair and signs a valid challenge for the
    # victim DID, but that key is not bound to the victim in feed_items.
    {apub, apriv} = keypair()
    headers = signed_headers(victim, apub, apriv, System.os_time(:second))
    assert {:error, :unknown_reader} = HomeAuth.authorize(headers, victim)
  end

  test "rejects a stale timestamp" do
    did = "did:key:owner#{System.unique_integer([:positive])}"
    {pub, priv} = keypair()
    seed_binding(did, pub, priv)

    stale = System.os_time(:second) - 10_000
    headers = signed_headers(did, pub, priv, stale)
    assert {:error, :unauthorized} = HomeAuth.authorize(headers, did)
  end

  test "rejects missing headers" do
    assert {:error, :unauthorized} = HomeAuth.authorize(%{}, "did:key:x")
  end
end
