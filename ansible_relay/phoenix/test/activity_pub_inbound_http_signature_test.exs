defmodule AnsibleRelay.ActivityPub.InboundHttpSignatureTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  alias AnsibleRelay.ActivityPub.InboundHttpSignature
  alias AnsibleRelay.Repo

  @actor "https://mastodon.example/users/alice"
  @key_id @actor <> "#main-key"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    private = :public_key.generate_key({:rsa, 2048, 65_537})
    public = {:RSAPublicKey, elem(private, 2), elem(private, 3)}

    public_pem =
      :public_key.pem_encode([:public_key.pem_entry_encode(:SubjectPublicKeyInfo, public)])

    %{private: private, public_pem: public_pem}
  end

  test "accepts a Mastodon-compatible signed inbox request and rejects replay", ctx do
    activity = %{
      "id" => "https://mastodon.example/activities/1",
      "type" => "Follow",
      "actor" => @actor,
      "object" => "https://relay.elix.cool/users/bob"
    }

    now = ~U[2026-07-26 12:00:00Z]
    conn = signed_conn(activity, ctx.private, now)
    fetcher = fn @actor -> {:ok, actor_document(ctx.public_pem)} end
    opts = [now: now, key_fetcher: fetcher, host_validator: fn _ -> :ok end]

    assert {:ok, %{actor_uri: @actor, key_id: @key_id}} =
             InboundHttpSignature.verify(conn, activity, opts)

    assert {:error, :replayed_http_signature} =
             InboundHttpSignature.verify(conn, activity, opts)
  end

  test "rejects body tampering and stale Date", ctx do
    activity = %{"id" => "https://mastodon.example/a/2", "type" => "Follow", "actor" => @actor}
    signed_at = ~U[2026-07-26 12:00:00Z]
    conn = signed_conn(activity, ctx.private, signed_at)
    fetcher = fn @actor -> {:ok, actor_document(ctx.public_pem)} end
    base = [key_fetcher: fetcher, host_validator: fn _ -> :ok end]

    tampered = put_private(conn, :raw_body, ~s({"tampered":true}))

    assert {:error, :digest_mismatch} =
             InboundHttpSignature.verify(tampered, activity, [now: signed_at] ++ base)

    assert {:error, :stale_http_signature} =
             InboundHttpSignature.verify(
               conn,
               activity,
               [
                 now: DateTime.add(signed_at, 301, :second)
               ] ++ base
             )
  end

  defp signed_conn(activity, private, now) do
    body = Jason.encode!(activity)
    date = Calendar.strftime(now, "%a, %d %b %Y %H:%M:%S GMT")
    digest = "SHA-256=" <> (:crypto.hash(:sha256, body) |> Base.encode64())

    signing_string =
      [
        "(request-target): post /users/bob/inbox",
        "host: relay.elix.cool",
        "date: #{date}",
        "digest: #{digest}"
      ]
      |> Enum.join("\n")

    signature = :public_key.sign(signing_string, :sha256, private) |> Base.encode64()

    %{conn(:post, "/users/bob/inbox", body) | host: "relay.elix.cool", scheme: :https, port: 443}
    |> put_private(:raw_body, body)
    |> put_req_header("date", date)
    |> put_req_header("digest", digest)
    |> put_req_header(
      "signature",
      ~s|keyId="#{@key_id}",algorithm="rsa-sha256",headers="(request-target) host date digest",signature="#{signature}"|
    )
  end

  defp actor_document(public_pem) do
    %{
      "id" => @actor,
      "publicKey" => %{
        "id" => @key_id,
        "owner" => @actor,
        "publicKeyPem" => public_pem
      }
    }
  end
end
