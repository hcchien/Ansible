defmodule AnsibleRelay.Web.SafetyReportControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.Db.SafetyEvent
  alias AnsibleRelay.ForumHost.SignedIntent
  alias AnsibleRelay.{IdentityCache, Repo}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case IdentityCache.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    original_base_url = Application.get_env(:ansible_relay, :forum_host_base_url)
    Application.put_env(:ansible_relay, :forum_host_base_url, "http://localhost:4001")
    on_exit(fn -> restore_env(:forum_host_base_url, original_base_url) end)

    :ok
  end

  test "a signed block creates one reason-coded operator intake record" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    reporter = "did:elix:safety-reporter"
    :ok = IdentityCache.put(reporter, Base.encode16(public_key, case: :lower), "safety-nullifier")

    params = signed_params(private_key, reporter)

    first = post_json("/api/v1/safety/reports", params)
    assert first.status == 201

    assert %{"event" => %{"event_type" => "block_user", "reason_code" => "harassment"}} =
             Jason.decode!(first.resp_body)

    second = post_json("/api/v1/safety/reports", params)
    assert second.status == 200

    assert [%SafetyEvent{} = event] = Repo.all(SafetyEvent)
    assert event.reporter_did == reporter
    assert event.subject_did == "did:elix:abusive-user"
    assert event.target_kind == "post"
    assert event.target_ref == "post-123"
    assert event.status == "open"
  end

  test "an intent for another relay is rejected" do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    reporter = "did:elix:wrong-audience"
    :ok = IdentityCache.put(reporter, Base.encode16(public_key, case: :lower), "wrong-audience")

    params = signed_params(private_key, reporter, "https://other.example")
    response = post_json("/api/v1/safety/reports", params)

    assert response.status == 403
    assert Jason.decode!(response.resp_body) == %{"error" => "audience_mismatch"}
    assert Repo.aggregate(SafetyEvent, :count) == 0
  end

  defp signed_params(private_key, reporter, audience \\ "http://localhost:4001") do
    created_at = DateTime.utc_now()

    params = %{
      "action" => "block_user",
      "author_did" => reporter,
      "created_at" => DateTime.to_iso8601(created_at),
      "expires_at" => created_at |> DateTime.add(300, :second) |> DateTime.to_iso8601(),
      "intent_id" => "safety-intent-123",
      "report" => %{
        "note" => "Repeated threats",
        "reason_code" => "harassment",
        "subject_did" => "did:elix:abusive-user",
        "target_kind" => "post",
        "target_ref" => "post-123"
      },
      "target_relay" => audience,
      "type" => "io.trisaura.safety.report",
      "version" => 1
    }

    signature =
      :crypto.sign(:eddsa, :none, SignedIntent.canonical_json(params), [private_key, :ed25519])
      |> Base.encode16(case: :lower)

    Map.put(params, "signature", signature)
  end

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp restore_env(key, nil), do: Application.delete_env(:ansible_relay, key)
  defp restore_env(key, value), do: Application.put_env(:ansible_relay, key, value)
end
