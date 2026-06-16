defmodule AnsibleRelay.Identity.FederatedResolverTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.Repo
  alias AnsibleRelay.DidElix
  alias AnsibleRelay.Identity.{AnchorStore, FederatedResolver}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    AnchorStore.reset()
    :ok
  end

  defp keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(pub, case: :lower), priv}
  end

  defp sign(priv, msg),
    do: :crypto.sign(:eddsa, :none, msg, [priv, :ed25519]) |> Base.encode16(case: :lower)

  # A fully-signed, self-certifying active-anchor object map (as a peer would
  # serve it). `key_priv` lets a forger sign with a key that does NOT match the
  # DID.
  defp anchor_object(handle, opts \\ []) do
    {pub, priv} = keypair()
    did = Keyword.get(opts, :did, DidElix.derive(pub, handle))
    sign_pub = Keyword.get(opts, :identity_key, pub)
    sign_priv = Keyword.get(opts, :sign_priv, priv)

    object = %{
      "type" => "io.trisaura.identity.anchor",
      "schema_version" => 2,
      "did" => did,
      "handle" => handle,
      "identity_key" => sign_pub,
      "also_known_as" => ["at://#{handle}"],
      "custody_class" => "software",
      "devices" => [],
      "prev_anchor_cid" => nil,
      "reason" => "initial",
      "created_at" => "2026-06-16T00:00:00.000Z"
    }

    Map.put(object, "sig", sign(sign_priv, AnchorStore.canonical_body(object)))
  end

  test "verified? accepts a self-certifying signed anchor" do
    assert FederatedResolver.verified?(anchor_object("v.elix.cool"))
  end

  test "verified? rejects a DID that does not self-certify" do
    obj = anchor_object("v.elix.cool") |> Map.put("did", "did:elix:forged")
    refute FederatedResolver.verified?(obj)
  end

  test "verified? rejects a tampered field (signature no longer matches)" do
    obj = anchor_object("v.elix.cool") |> Map.put("also_known_as", ["at://evil"])
    refute FederatedResolver.verified?(obj)
  end

  test "resolve falls back to a peer and returns the verified answer" do
    obj = anchor_object("peerhosted.elix.cool")
    did = obj["did"]
    fetch = fn _peer, ^did -> {:ok, obj} end

    assert {:ok, ^obj, {:peer, "https://peer.example"}} =
             FederatedResolver.resolve(did, peers: ["https://peer.example"], fetch: fetch)
  end

  test "resolve REJECTS a lying peer that serves a forged anchor for the DID" do
    {victim_pub, _victim_priv} = keypair()
    handle = "victim.elix.cool"
    did = DidElix.derive(victim_pub, handle)

    # The peer serves an anchor under the victim's DID but signed by a key it
    # controls. Self-certification (did ⇔ identity_key) fails, so it is dropped.
    {evil_pub, evil_priv} = keypair()

    forged =
      anchor_object(handle, did: did, identity_key: evil_pub, sign_priv: evil_priv)

    fetch = fn _peer, ^did -> {:ok, forged} end

    assert {:error, :not_found} =
             FederatedResolver.resolve(did, peers: ["https://peer.example"], fetch: fetch)
  end

  test "resolve prefers a local anchor over peers" do
    {pub, priv} = keypair()
    handle = "localfirst.elix.cool"
    did = DidElix.derive(pub, handle)

    genesis = anchor_object(handle, did: did, identity_key: pub, sign_priv: priv)
    assert {:ok, :active, _} = AnchorStore.submit(genesis)

    # A peer fetch that would explode if called — proving local wins.
    fetch = fn _peer, _did -> raise "peers must not be consulted when local resolves" end

    assert {:ok, object, :local} =
             FederatedResolver.resolve(did, peers: ["https://peer.example"], fetch: fetch)

    assert object["did"] == did
  end

  test "resolve returns not_found when neither local nor peers have it" do
    assert {:error, :not_found} =
             FederatedResolver.resolve("did:elix:missing", peers: [], fetch: fn _, _ -> {:error, :x} end)
  end
end
