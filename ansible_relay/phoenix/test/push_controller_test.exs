defmodule AnsibleRelay.Web.PushControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{IdentityCache, MessengerStore, Repo}
  alias AnsibleRelay.Db.DevicePushToken
  alias AnsibleRelay.Push.{TestSender, TokenRegistry, WakeScheduler}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    for mod <- [IdentityCache, MessengerStore, WakeScheduler] do
      case mod.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end

    TestSender.reset()
    :ok = WakeScheduler.reset()
    :ok = TokenRegistry.reset()
    :ok
  end

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

  defp seed_did(did, public_key_hex) do
    :ok = IdentityCache.put(did, public_key_hex, "push:#{did}")
  end

  defp register_body(did, overrides \\ %{}) do
    Map.merge(
      %{
        "subject_did" => did,
        "device_id" => "dev_1",
        "push_token" => "tok_abc",
        "platform" => "fcm",
        "categories" => ["reply", "mention", "follow", "messenger"],
        "registered_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      },
      overrides
    )
  end

  defp signed(body, private_key) do
    Map.put(body, "request_signature", sign(private_key, canonical_json(body)))
  end

  defp register(did, private_key, overrides \\ %{}) do
    post_json("/api/v1/push/tokens", signed(register_body(did, overrides), private_key))
  end

  defp unregister(did, private_key, device_id) do
    body = %{
      "subject_did" => did,
      "device_id" => device_id,
      "unregistered_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    post_json("/api/v1/push/tokens/unregister", signed(body, private_key))
  end

  # Drain the scheduler's cast queue, wait out the debounce window, then
  # drain the flush message so any pending send has happened.
  defp await_flush do
    :sys.get_state(WakeScheduler)
    Process.sleep(Application.fetch_env!(:ansible_relay, :push_wake_debounce_ms) + 50)
    :sys.get_state(WakeScheduler)
  end

  test "registering a new device token returns 201 and stores the row" do
    {public_key, private_key} = ed25519_keypair()
    did = "did:plc:push_create_#{System.unique_integer([:positive])}"
    seed_did(did, public_key)

    response = register(did, private_key)

    assert response.status == 201
    assert Jason.decode!(response.resp_body) == %{"ok" => true}

    row = Repo.get_by(DevicePushToken, subject_did: did, device_id: "dev_1")
    assert row.push_token == "tok_abc"
    assert row.platform == "fcm"
    assert row.categories == ["reply", "mention", "follow", "messenger"]
  end

  test "re-registering the same (did, device) upserts and returns 200" do
    {public_key, private_key} = ed25519_keypair()
    did = "did:plc:push_update_#{System.unique_integer([:positive])}"
    seed_did(did, public_key)

    assert register(did, private_key).status == 201

    response =
      register(did, private_key, %{
        "push_token" => "tok_rotated",
        "platform" => "apns",
        "categories" => ["messenger"]
      })

    assert response.status == 200
    assert Jason.decode!(response.resp_body) == %{"ok" => true}

    row = Repo.get_by(DevicePushToken, subject_did: did, device_id: "dev_1")
    assert row.push_token == "tok_rotated"
    assert row.platform == "apns"
    assert row.categories == ["messenger"]
  end

  test "a bad signature is rejected with 401 and stores nothing" do
    {public_key, _private_key} = ed25519_keypair()
    did = "did:plc:push_badsig_#{System.unique_integer([:positive])}"
    seed_did(did, public_key)

    response =
      post_json("/api/v1/push/tokens", Map.put(register_body(did), "request_signature", "00"))

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
    assert Repo.get_by(DevicePushToken, subject_did: did, device_id: "dev_1") == nil
  end

  test "an unknown platform is rejected with 422 invalid_platform" do
    {public_key, private_key} = ed25519_keypair()
    did = "did:plc:push_platform_#{System.unique_integer([:positive])}"
    seed_did(did, public_key)

    response = register(did, private_key, %{"platform" => "carrier_pigeon"})

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_platform"
  end

  test "categories outside the allowed set are rejected with 422 invalid_categories" do
    {public_key, private_key} = ed25519_keypair()
    did = "did:plc:push_categories_#{System.unique_integer([:positive])}"
    seed_did(did, public_key)

    response = register(did, private_key, %{"categories" => ["reply", "everything"]})

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_categories"
  end

  test "missing required fields are rejected with 422" do
    response =
      post_json("/api/v1/push/tokens", %{
        "subject_did" => "did:plc:push_missing",
        "platform" => "fcm"
      })

    assert response.status == 422
    body = Jason.decode!(response.resp_body)
    assert body["error"] == "missing_required_fields"
    assert "device_id" in body["fields"]
    assert "push_token" in body["fields"]
    assert "request_signature" in body["fields"]
  end

  test "a registered_at outside the ±5 minute window is rejected" do
    {public_key, private_key} = ed25519_keypair()
    did = "did:plc:push_stale_#{System.unique_integer([:positive])}"
    seed_did(did, public_key)

    stale =
      DateTime.utc_now()
      |> DateTime.add(-600, :second)
      |> DateTime.to_iso8601()

    response = register(did, private_key, %{"registered_at" => stale})

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "stale_timestamp"
  end

  test "unregister deletes the row and a subsequent wake trigger sends nothing" do
    {public_key, private_key} = ed25519_keypair()
    did = "did:plc:push_unreg_#{System.unique_integer([:positive])}"
    sender = "did:plc:push_unreg_sender"
    seed_did(did, public_key)

    assert register(did, private_key).status == 201

    # The registered device wakes on mailbox delivery.
    WakeScheduler.mailbox_delivered(sender, did)
    await_flush()
    assert [%{token: "tok_abc", platform: "fcm"}] = TestSender.calls()

    response = unregister(did, private_key, "dev_1")
    assert response.status == 200
    assert Jason.decode!(response.resp_body) == %{"ok" => true}
    assert Repo.get_by(DevicePushToken, subject_did: did, device_id: "dev_1") == nil

    # After deletion the same trigger must never fire a wake again.
    TestSender.reset()
    WakeScheduler.mailbox_delivered(sender, did)
    await_flush()
    assert TestSender.calls() == []
  end

  test "unregister with a bad signature is rejected and keeps the row" do
    {public_key, private_key} = ed25519_keypair()
    did = "did:plc:push_unreg_sig_#{System.unique_integer([:positive])}"
    seed_did(did, public_key)

    assert register(did, private_key).status == 201

    response =
      post_json("/api/v1/push/tokens/unregister", %{
        "subject_did" => did,
        "device_id" => "dev_1",
        "unregistered_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "request_signature" => "00"
      })

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_signature"
    refute Repo.get_by(DevicePushToken, subject_did: did, device_id: "dev_1") == nil
  end
end
