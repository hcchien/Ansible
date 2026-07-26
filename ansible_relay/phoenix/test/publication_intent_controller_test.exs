defmodule AnsibleRelay.Web.PublicationIntentControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.Db.{FediversePreference, PublicationIntent}
  alias AnsibleRelay.{DidAccountCache, IdentityCache, Repo}

  @router_opts Router.init([])

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp ed25519_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp p256_keypair do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256r1)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  defp sign_p256(private_key, message) do
    :crypto.sign(:ecdsa, :sha256, message, [private_key, :secp256r1])
    |> Base.encode16(case: :lower)
  end

  defp seed_did(did, public_key, signing_algorithm \\ "ed25519") do
    handle = "ap-#{System.unique_integer([:positive])}"

    IdentityCache.put(
      did,
      public_key,
      "nullifier_#{System.unique_integer()}",
      nil,
      signing_algorithm
    )

    DidAccountCache.put(
      did,
      public_key,
      handle,
      reputation_tier: "verified_human",
      signing_algorithm: signing_algorithm
    )

    Repo.insert!(%FediversePreference{
      did: did,
      actor: handle,
      enabled: true,
      revision: System.unique_integer([:positive]),
      signature: String.duplicate("a", 128),
      signature_scheme: signing_algorithm
    })
  end

  defp payload_hash(payload) do
    :crypto.hash(:sha256, canonical_json(payload))
    |> Base.encode16(case: :lower)
  end

  defp signing_payload(intent) do
    Jason.encode!([
      intent["author_did"],
      intent["content_item_id"],
      intent["action"],
      intent["visibility"],
      intent["payload_hash"]
    ])
  end

  defp valid_intent(did, private_key) do
    payload = %{
      "type" => "note",
      "title" => "Relay note",
      "body" => "published through ActivityPub relay"
    }

    intent = %{
      "intent_id" => "intent-#{System.unique_integer([:positive])}",
      "author_did" => did,
      "content_item_id" => "note-#{System.unique_integer([:positive])}",
      "action" => "publish",
      "visibility" => "public",
      "payload" => payload,
      "payload_hash" => payload_hash(payload),
      "signature_scheme" => "ed25519"
    }

    Map.put(intent, "signature", sign(private_key, signing_payload(intent)))
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, entry_value} -> {to_string(key), entry_value} end)
      |> Enum.sort_by(fn {key, _entry_value} -> key end)
      |> Enum.map(fn {key, entry_value} ->
        Jason.encode!(key) <> ":" <> canonical_json(entry_value)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case IdentityCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  test "POST /api/v1/publication-intents accepts signed public intent" do
    did = "did:key:z6MkPublication#{System.unique_integer([:positive])}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    response = post_json("/api/v1/publication-intents", valid_intent(did, private_key))

    assert response.status == 202
    body = Jason.decode!(response.resp_body)
    assert body["accepted"] == true
    assert body["status"] == "accepted"
    assert body["delivery_status"] == "awaiting_followers"
    assert is_binary(body["publication_id"])

    stored = Repo.get_by!(PublicationIntent, publication_id: body["publication_id"])
    assert stored.author_did == did
    assert stored.action == "publish"
    assert stored.visibility == "public"
    assert stored.delivery_status == "awaiting_followers"
  end

  test "ActivityPub Note requires verified-human tier" do
    did = "did:key:z6MkBasicPublication#{System.unique_integer([:positive])}"
    {public_key, private_key} = ed25519_keypair()

    IdentityCache.put(
      did,
      public_key,
      "nullifier_#{System.unique_integer()}",
      nil,
      "ed25519"
    )

    DidAccountCache.put(
      did,
      public_key,
      "basic-#{System.unique_integer([:positive])}",
      reputation_tier: "basic"
    )

    response = post_json("/api/v1/publication-intents", valid_intent(did, private_key))
    assert response.status == 403
    assert Jason.decode!(response.resp_body)["error"] == "activity_pub_requires_verified_human"
  end

  test "ActivityPub endpoint rejects murmurs while the first slice is notes-only" do
    did = "did:key:z6MkMurmurPublication#{System.unique_integer([:positive])}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    intent = valid_intent(did, private_key)
    payload = %{"type" => "murmur", "text" => "not enabled yet"}
    intent = %{intent | "payload" => payload, "payload_hash" => payload_hash(payload)}
    intent = Map.put(intent, "signature", sign(private_key, signing_payload(intent)))

    response = post_json("/api/v1/publication-intents", intent)
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "activity_pub_notes_only"
  end

  test "POST /api/v1/publication-intents accepts a DER P-256 hardware signature" do
    did = "did:elix:p256-publication-#{System.unique_integer([:positive])}"
    {public_key, private_key} = p256_keypair()
    seed_did(did, public_key, "p256-sha256")

    intent =
      valid_intent(did, elem(ed25519_keypair(), 1))
      |> Map.put("signature_scheme", "p256-sha256")

    intent = Map.put(intent, "signature", sign_p256(private_key, signing_payload(intent)))
    response = post_json("/api/v1/publication-intents", intent)

    assert response.status == 202
    assert Jason.decode!(response.resp_body)["accepted"] == true
  end

  test "publication rejects Ed25519 when the first-party write policy is P-256 only" do
    original = Application.get_env(:ansible_relay, :identity_write_algorithms)
    Application.put_env(:ansible_relay, :identity_write_algorithms, ["p256-sha256"])

    on_exit(fn ->
      Application.put_env(:ansible_relay, :identity_write_algorithms, original)
    end)

    did = "did:key:z6MkLegacyPublication#{System.unique_integer([:positive])}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    response = post_json("/api/v1/publication-intents", valid_intent(did, private_key))

    assert response.status == 422
    body = Jason.decode!(response.resp_body)
    assert body["error"] == "unsupported_signing_algorithm"
    assert body["expected"] == ["p256-sha256"]
  end

  test "rejects private visibility" do
    did = "did:key:z6MkPrivatePublication#{System.unique_integer([:positive])}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    intent = valid_intent(did, private_key) |> Map.put("visibility", "private")
    intent = Map.put(intent, "signature", sign(private_key, signing_payload(intent)))

    response = post_json("/api/v1/publication-intents", intent)

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "private_visibility_not_federated"
  end

  test "rejects missing signatures" do
    did = "did:key:z6MkMissingSigPublication#{System.unique_integer([:positive])}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)

    response =
      post_json(
        "/api/v1/publication-intents",
        valid_intent(did, private_key) |> Map.delete("signature")
      )

    assert response.status == 422
    body = Jason.decode!(response.resp_body)
    assert body["error"] == "missing_required_fields"
    assert "signature" in body["fields"]
  end

  test "rejects stub signatures" do
    did = "did:key:z6MkStubPublication#{System.unique_integer([:positive])}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    intent = valid_intent(did, private_key) |> Map.put("signature", "stub-signature")

    response = post_json("/api/v1/publication-intents", intent)

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
  end

  test "accepts development publication signatures only when enabled" do
    original = Application.get_env(:ansible_relay, :allow_dev_publication_signatures, false)
    Application.put_env(:ansible_relay, :allow_dev_publication_signatures, true)

    on_exit(fn ->
      Application.put_env(:ansible_relay, :allow_dev_publication_signatures, original)
    end)

    did = "did:key:z6MkDevPublication#{System.unique_integer([:positive])}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    intent = valid_intent(did, private_key) |> Map.put("signature", "dev-signature-local")

    response = post_json("/api/v1/publication-intents", intent)

    assert response.status == 202
    assert Jason.decode!(response.resp_body)["accepted"] == true
  end

  test "development signatures do not bypass the verified-human gate" do
    original = Application.get_env(:ansible_relay, :allow_dev_publication_signatures, false)
    Application.put_env(:ansible_relay, :allow_dev_publication_signatures, true)

    on_exit(fn ->
      Application.put_env(:ansible_relay, :allow_dev_publication_signatures, original)
    end)

    did = "did:plc:qrstuvwxyz234567abcdefgh"
    {_public_key, private_key} = ed25519_keypair()
    intent = valid_intent(did, private_key) |> Map.put("signature", "dev-signature-local")

    response = post_json("/api/v1/publication-intents", intent)

    assert response.status == 403

    assert Jason.decode!(response.resp_body)["error"] ==
             "activity_pub_requires_verified_human"
  end

  test "rejects tampered payload hash" do
    did = "did:key:z6MkTamperedPublication#{System.unique_integer([:positive])}"
    {public_key, private_key} = ed25519_keypair()
    seed_did(did, public_key)
    intent = valid_intent(did, private_key) |> Map.put("payload_hash", String.duplicate("0", 64))
    intent = Map.put(intent, "signature", sign(private_key, signing_payload(intent)))

    response = post_json("/api/v1/publication-intents", intent)

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "payload_hash_mismatch"
  end
end
