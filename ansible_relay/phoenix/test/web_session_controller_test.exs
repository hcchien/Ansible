defmodule AnsibleRelay.Web.WebSessionControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{AbuseDetector, IdentityCache, Repo, WebSessionStore}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  defp get_json(path, headers \\ []) do
    Enum.reduce(headers, conn(:get, path), fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
    |> Router.call(@router_opts)
  end

  defp post_json(path, body, headers \\ []) do
    Enum.reduce(headers, conn(:post, path, Jason.encode!(body)), fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp options(path, headers \\ []) do
    Enum.reduce(headers, conn(:options, path), fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
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

  defp grant(challenge, did, expires_at \\ nil) do
    %{
      "type" => "io.trisaura.webSessionGrant",
      "version" => 1,
      "challenge_id" => challenge.challenge_id,
      "relay_origin" => challenge.relay_origin,
      "web_origin" => challenge.web_origin,
      "audience" => Map.get(challenge, :audience, challenge.relay_origin),
      "subject_did" => did,
      "approving_device_id" => "app_device_test",
      "scopes" => challenge.scopes,
      "expires_at" =>
        DateTime.to_iso8601(expires_at || DateTime.add(DateTime.utc_now(), 300, :second)),
      "created_at" => DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  defp session_id(session_token) do
    digest =
      :crypto.hash(:sha256, session_token)
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 22)

    "wsi_" <> digest
  end

  defp approved_store_session(did, scopes \\ ["forum:read"]) do
    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => scopes,
        "ttl_seconds" => 300
      })

    {:ok, session} =
      WebSessionStore.approve_challenge(challenge.challenge_id, %{
        subject_did: did,
        approving_device_id: "app_device_#{System.unique_integer([:positive])}",
        scopes: scopes,
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

    session
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case IdentityCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case WebSessionStore.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> WebSessionStore.reset()
    end

    case AbuseDetector.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> AbuseDetector.reset()
    end

    original_origin = Application.get_env(:ansible_relay, :relay_origin)
    original_abuse_policy = Application.get_env(:ansible_relay, :abuse_detector)
    original_allowed_origins = Application.get_env(:ansible_relay, :web_allowed_origins)
    Application.put_env(:ansible_relay, :relay_origin, "https://relay.trisaura.io")

    Application.put_env(:ansible_relay, :web_allowed_origins, [
      "https://trisaura.io",
      "http://127.0.0.1:5173"
    ])

    on_exit(fn ->
      if original_origin do
        Application.put_env(:ansible_relay, :relay_origin, original_origin)
      else
        Application.delete_env(:ansible_relay, :relay_origin)
      end

      if original_abuse_policy do
        Application.put_env(:ansible_relay, :abuse_detector, original_abuse_policy)
      else
        Application.delete_env(:ansible_relay, :abuse_detector)
      end

      if original_allowed_origins do
        Application.put_env(:ansible_relay, :web_allowed_origins, original_allowed_origins)
      else
        Application.delete_env(:ansible_relay, :web_allowed_origins)
      end
    end)

    :ok
  end

  test "approved challenge creates a scoped session token" do
    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read", "forum:post"],
        "ttl_seconds" => 300
      })

    assert {:ok, pending} = WebSessionStore.get_challenge(challenge.challenge_id)
    assert pending.status == "pending"
    assert pending.audience == "https://relay.trisaura.io"

    assert {:ok, session} =
             WebSessionStore.approve_challenge(challenge.challenge_id, %{
               subject_did: "did:plc:abc23456789",
               approving_device_id: "app_device_store",
               scopes: ["forum:read", "forum:post"],
               expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
             })

    assert {:ok, found} = WebSessionStore.get_session(session.session_token)
    assert found.subject_did == "did:plc:abc23456789"
    assert found.approving_device_id == "app_device_store"
    assert found.audience == "https://relay.trisaura.io"
    assert found.scopes == ["forum:read", "forum:post"]
    assert {:error, :consumed} = WebSessionStore.get_challenge(challenge.challenge_id)
  end

  test "web session challenge routes allow configured browser origins" do
    original_allowed_origins = Application.get_env(:ansible_relay, :web_allowed_origins)
    Application.put_env(:ansible_relay, :web_allowed_origins, ["http://127.0.0.1:5173"])

    on_exit(fn ->
      if original_allowed_origins do
        Application.put_env(:ansible_relay, :web_allowed_origins, original_allowed_origins)
      else
        Application.delete_env(:ansible_relay, :web_allowed_origins)
      end
    end)

    preflight =
      options("/api/v1/web-sessions/challenges", [
        {"origin", "http://127.0.0.1:5173"},
        {"access-control-request-method", "POST"}
      ])

    assert preflight.status == 204

    assert get_resp_header(preflight, "access-control-allow-origin") == [
             "http://127.0.0.1:5173"
           ]

    response =
      post_json(
        "/api/v1/web-sessions/challenges",
        %{
          "web_origin" => "http://127.0.0.1:5173",
          "relay_origin" => "https://relay.trisaura.io",
          "scopes" => ["forum:read", "forum:post"]
        },
        [{"origin", "http://127.0.0.1:5173"}]
      )

    assert response.status == 201

    assert get_resp_header(response, "access-control-allow-origin") == [
             "http://127.0.0.1:5173"
           ]
  end

  test "POST /api/v1/web-sessions/challenges rejects unconfigured web origins" do
    response =
      post_json("/api/v1/web-sessions/challenges", %{
        "web_origin" => "https://evil.example",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"]
      })

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "web_origin_not_allowed"
  end

  test "POST /api/v1/web-sessions/challenges rejects invalid audiences" do
    for audience <- [
          "did:plc:not-an-origin",
          "http://user@localhost:4001",
          "http://localhost:4001.evil",
          "http://localhost:4001abc"
        ] do
      response =
        post_json("/api/v1/web-sessions/challenges", %{
          "web_origin" => "https://trisaura.io",
          "relay_origin" => "https://relay.trisaura.io",
          "audience" => audience,
          "scopes" => ["forum:read"]
        })

      assert response.status == 422
      assert Jason.decode!(response.resp_body)["error"] == "invalid_audience"
    end
  end

  test "store caps active web sessions per DID across app devices" do
    did = "did:plc:cap23456789"

    sessions =
      for index <- 1..5 do
        {:ok, challenge} =
          WebSessionStore.issue_challenge(%{
            "web_origin" => "https://trisaura.io",
            "relay_origin" => "https://relay.trisaura.io",
            "scopes" => ["forum:read"],
            "ttl_seconds" => 300
          })

        {:ok, session} =
          WebSessionStore.approve_challenge(challenge.challenge_id, %{
            subject_did: did,
            approving_device_id: "app_device_#{index}",
            scopes: ["forum:read"],
            expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
          })

        session
      end

    {:ok, extra_challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    assert {:error, :too_many_active_sessions} =
             WebSessionStore.approve_challenge(extra_challenge.challenge_id, %{
               subject_did: did,
               approving_device_id: "app_device_6",
               scopes: ["forum:read"],
               expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
             })

    assert {:ok, _} = WebSessionStore.revoke_session(List.first(sessions).session_token)

    assert {:ok, session} =
             WebSessionStore.approve_challenge(extra_challenge.challenge_id, %{
               subject_did: did,
               approving_device_id: "app_device_6",
               scopes: ["forum:read"],
               expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
             })

    assert session.subject_did == did
  end

  test "store limits web session approvals per app device" do
    did = "did:plc:cooldown23456789"

    for _index <- 1..3 do
      {:ok, challenge} =
        WebSessionStore.issue_challenge(%{
          "web_origin" => "https://trisaura.io",
          "relay_origin" => "https://relay.trisaura.io",
          "scopes" => ["forum:read"],
          "ttl_seconds" => 300
        })

      assert {:ok, _session} =
               WebSessionStore.approve_challenge(challenge.challenge_id, %{
                 subject_did: did,
                 approving_device_id: "app_device_limited",
                 scopes: ["forum:read"],
                 expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
               })
    end

    {:ok, blocked_challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    assert {:error, :approval_rate_limited} =
             WebSessionStore.approve_challenge(blocked_challenge.challenge_id, %{
               subject_did: did,
               approving_device_id: "app_device_limited",
               scopes: ["forum:read"],
               expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
             })
  end

  test "POST /api/v1/web-sessions/challenges creates a challenge and QR payload" do
    response =
      post_json("/api/v1/web-sessions/challenges", %{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read", "forum:post"]
      })

    assert response.status == 201
    body = Jason.decode!(response.resp_body)
    assert String.starts_with?(body["challenge_id"], "wsc_")
    assert body["audience"] == "https://relay.trisaura.io"
    assert String.contains?(body["deep_link"], "trisaura://web-session/approve")
    assert body["qr_payload"] == body["deep_link"]
    assert {:ok, _} = WebSessionStore.get_challenge(body["challenge_id"])
  end

  test "approved challenge persists audience into session response" do
    {public_key_hex, private_key} = ed25519_keypair()
    did = "did:plc:audience23456789"
    :ok = IdentityCache.put(did, public_key_hex, "web_session_test_#{System.unique_integer()}")

    challenge_response =
      post_json("/api/v1/web-sessions/challenges", %{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "audience" => "http://localhost:4001",
        "scopes" => ["forum:post"]
      })

    assert challenge_response.status == 201
    challenge_body = Jason.decode!(challenge_response.resp_body)
    assert challenge_body["audience"] == "http://localhost:4001"
    assert {:ok, stored_challenge} = WebSessionStore.get_challenge(challenge_body["challenge_id"])

    grant = grant(stored_challenge, did)
    signature = sign(private_key, canonical_json(grant))

    response =
      post_json("/api/v1/web-sessions/approve", %{
        "challenge_id" => challenge_body["challenge_id"],
        "subject_did" => did,
        "grant" => grant,
        "signature" => signature
      })

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["audience"] == "http://localhost:4001"
  end

  test "POST /api/v1/web-sessions/challenges is rate limited by peer metadata" do
    Application.put_env(:ansible_relay, :abuse_detector, %{
      peer: %{capacity: 1, refill_per_second: 0, suspension_ms: 60_000}
    })

    body = %{
      "web_origin" => "https://trisaura.io",
      "relay_origin" => "https://relay.trisaura.io",
      "scopes" => ["forum:read"]
    }

    first = post_json("/api/v1/web-sessions/challenges", body)
    second = post_json("/api/v1/web-sessions/challenges", body)

    assert first.status == 201
    assert second.status == 429
    assert Jason.decode!(second.resp_body)["error"] == "rate_limited"
  end

  test "poll challenge sets httpOnly session cookie and returns trust info after valid app approval" do
    did = "did:plc:abc23456789"
    {public_key, private_key} = ed25519_keypair()
    IdentityCache.put(did, public_key, "web_session_test_#{System.unique_integer()}")

    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read", "forum:post"],
        "ttl_seconds" => 300
      })

    grant = grant(challenge, did)

    response =
      post_json("/api/v1/web-sessions/approve", %{
        "challenge_id" => challenge.challenge_id,
        "subject_did" => did,
        "grant" => grant,
        "signature" => sign(private_key, canonical_json(grant))
      })

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert String.starts_with?(body["session_token"], "wst_")
    assert body["trust_tier"] == "self_custody_did"
    assert body["approving_device_id"] == "app_device_test"

    poll = get_json("/api/v1/web-sessions/challenges/#{challenge.challenge_id}")
    poll_body = Jason.decode!(poll.resp_body)
    assert poll_body["status"] == "approved"
    assert poll_body["trust_tier"] == "self_custody_did"
    assert poll_body["subject_did"] == did
    # session_token must NOT be exposed to browser JavaScript
    refute Map.has_key?(poll_body, "session_token")

    # The relay must set an httpOnly cookie on the poll response
    set_cookie = get_resp_header(poll, "set-cookie")
    assert Enum.any?(set_cookie, &String.contains?(&1, "trisaura_session="))
    assert Enum.any?(set_cookie, &String.contains?(&1, "HttpOnly"))
  end

  test "approve rejects over-scoped grants" do
    did = "did:plc:scope23456789"
    {public_key, private_key} = ed25519_keypair()
    IdentityCache.put(did, public_key, "web_session_test_#{System.unique_integer()}")

    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    grant = Map.put(grant(challenge, did), "scopes", ["forum:read", "forum:post"])

    response =
      post_json("/api/v1/web-sessions/approve", %{
        "challenge_id" => challenge.challenge_id,
        "subject_did" => did,
        "grant" => grant,
        "signature" => sign(private_key, canonical_json(grant))
      })

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "scope_not_allowed"
  end

  test "approve rejects grant audience mismatch" do
    did = "did:plc:audiencemismatch23456789"
    {public_key, private_key} = ed25519_keypair()
    IdentityCache.put(did, public_key, "web_session_test_#{System.unique_integer()}")

    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "audience" => "http://localhost:4001",
        "scopes" => ["forum:post"],
        "ttl_seconds" => 300
      })

    grant = Map.put(grant(challenge, did), "audience", "https://other-host.test")

    response =
      post_json("/api/v1/web-sessions/approve", %{
        "challenge_id" => challenge.challenge_id,
        "subject_did" => did,
        "grant" => grant,
        "signature" => sign(private_key, canonical_json(grant))
      })

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "audience_mismatch"
  end

  test "reject, revoke, and me endpoints expose web session state via Bearer token (backward compat)" do
    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    reject = post_json("/api/v1/web-sessions/reject", %{"challenge_id" => challenge.challenge_id})
    assert reject.status == 200
    assert Jason.decode!(reject.resp_body)["status"] == "rejected"

    {:ok, approved_challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    {:ok, session} =
      WebSessionStore.approve_challenge(approved_challenge.challenge_id, %{
        subject_did: "did:plc:me23456789",
        approving_device_id: "app_device_me",
        scopes: ["forum:read"],
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

    me =
      get_json("/api/v1/web-sessions/me", [{"authorization", "Bearer #{session.session_token}"}])

    assert me.status == 200
    me_body = Jason.decode!(me.resp_body)
    assert me_body["subject_did"] == "did:plc:me23456789"
    assert me_body["session_id"] == session_id(session.session_token)
    refute Map.has_key?(me_body, "session_token")

    revoke =
      post_json(
        "/api/v1/web-sessions/revoke",
        %{},
        [{"authorization", "Bearer #{session.session_token}"}]
      )

    assert revoke.status == 200
    assert Jason.decode!(revoke.resp_body)["revoked"] == true
  end

  test "me and revoke endpoints work via httpOnly session cookie" do
    {:ok, challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    {:ok, session} =
      WebSessionStore.approve_challenge(challenge.challenge_id, %{
        subject_did: "did:plc:cookie23456789",
        approving_device_id: "app_device_cookie",
        scopes: ["forum:read"],
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

    me =
      get_json("/api/v1/web-sessions/me", [
        {"cookie", "trisaura_session=#{session.session_token}"}
      ])

    assert me.status == 200
    assert Jason.decode!(me.resp_body)["subject_did"] == "did:plc:cookie23456789"

    revoke =
      post_json(
        "/api/v1/web-sessions/revoke",
        %{},
        [{"cookie", "trisaura_session=#{session.session_token}"}]
      )

    assert revoke.status == 200
    assert Jason.decode!(revoke.resp_body)["revoked"] == true

    # Revocation of the current session must clear the cookie
    set_cookie = get_resp_header(revoke, "set-cookie")
    assert Enum.any?(set_cookie, &String.contains?(&1, "trisaura_session="))
    assert Enum.any?(set_cookie, &String.contains?(&1, "max-age=0"))
  end

  test "me and revoke endpoints prefer bearer over cookie when both are present" do
    cookie_session = approved_store_session("did:plc:cookieprecedence23456789")
    bearer_session = approved_store_session("did:plc:bearerprecedence23456789")

    headers = [
      {"authorization", "Bearer #{bearer_session.session_token}"},
      {"cookie", "trisaura_session=#{cookie_session.session_token}"}
    ]

    me = get_json("/api/v1/web-sessions/me", headers)

    assert me.status == 200
    assert Jason.decode!(me.resp_body)["subject_did"] == "did:plc:bearerprecedence23456789"

    revoke = post_json("/api/v1/web-sessions/revoke", %{}, headers)

    assert revoke.status == 200
    assert Jason.decode!(revoke.resp_body)["revoked"] == true
    assert {:error, :revoked} = WebSessionStore.get_session(bearer_session.session_token)
    assert {:ok, _session} = WebSessionStore.get_session(cookie_session.session_token)
  end

  test "malformed authorization header does not fall back to cookie on session endpoints" do
    cookie_session = approved_store_session("did:plc:malformedauth23456789")

    for authorization <- ["Basic #{cookie_session.session_token}", "Bearer "] do
      me =
        get_json("/api/v1/web-sessions/me", [
          {"authorization", authorization},
          {"cookie", "trisaura_session=#{cookie_session.session_token}"}
        ])

      assert me.status == 401
      assert Jason.decode!(me.resp_body)["error"] == "invalid_web_session"
    end
  end

  test "me endpoint lists active sessions for the same DID" do
    {:ok, first_challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    {:ok, first_session} =
      WebSessionStore.approve_challenge(first_challenge.challenge_id, %{
        subject_did: "did:plc:list23456789",
        approving_device_id: "app_device_list_1",
        scopes: ["forum:read"],
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

    {:ok, second_challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    {:ok, _second_session} =
      WebSessionStore.approve_challenge(second_challenge.challenge_id, %{
        subject_did: "did:plc:list23456789",
        approving_device_id: "app_device_list_2",
        scopes: ["forum:read"],
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

    response =
      get_json("/api/v1/web-sessions", [
        {"authorization", "Bearer #{first_session.session_token}"}
      ])

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert length(body["sessions"]) == 2
    assert Enum.all?(body["sessions"], &(&1["subject_did"] == "did:plc:list23456789"))
    assert Enum.all?(body["sessions"], &Map.has_key?(&1, "session_id"))
    refute Enum.any?(body["sessions"], &Map.has_key?(&1, "session_token"))
  end

  test "session revoke endpoint can revoke another active session for the same DID by session id" do
    {:ok, first_challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    {:ok, first_session} =
      WebSessionStore.approve_challenge(first_challenge.challenge_id, %{
        subject_did: "did:plc:revoke23456789",
        approving_device_id: "app_device_revoke_1",
        scopes: ["forum:read"],
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

    {:ok, second_challenge} =
      WebSessionStore.issue_challenge(%{
        "web_origin" => "https://trisaura.io",
        "relay_origin" => "https://relay.trisaura.io",
        "scopes" => ["forum:read"],
        "ttl_seconds" => 300
      })

    {:ok, second_session} =
      WebSessionStore.approve_challenge(second_challenge.challenge_id, %{
        subject_did: "did:plc:revoke23456789",
        approving_device_id: "app_device_revoke_2",
        scopes: ["forum:read"],
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

    response =
      post_json(
        "/api/v1/web-sessions/revoke",
        %{"session_id" => session_id(second_session.session_token)},
        [{"authorization", "Bearer #{first_session.session_token}"}]
      )

    assert response.status == 200
    assert Jason.decode!(response.resp_body)["revoked"] == true
    assert {:error, :revoked} = WebSessionStore.get_session(second_session.session_token)
    assert {:ok, _} = WebSessionStore.get_session(first_session.session_token)
  end
end
