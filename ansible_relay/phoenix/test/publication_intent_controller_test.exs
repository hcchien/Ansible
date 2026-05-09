defmodule AnsibleRelay.Web.PublicationIntentControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Web.Router
  alias AnsibleRelay.{Db.PublicationIntent, IdentityCache, Repo}

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

  defp sign(private_key, message) do
    :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  defp seed_did(did, public_key) do
    IdentityCache.put(did, public_key, "nullifier_#{System.unique_integer()}")
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
    assert body["delivery_status"] == "queued"
    assert is_binary(body["publication_id"])

    stored = Repo.get_by!(PublicationIntent, publication_id: body["publication_id"])
    assert stored.author_did == did
    assert stored.action == "publish"
    assert stored.visibility == "public"
    assert stored.delivery_status == "queued"
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
