defmodule AnsibleRelay.ForumHost.PrivateBoardKeysTest do
  use ExUnit.Case, async: false

  alias AnsibleRelay.Db.{ForumHostBoard, ForumHostBoardAccessGrant}
  alias AnsibleRelay.ForumHost.{BoardAccessPolicy, PrivateBoardKeys}
  alias AnsibleRelay.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Application.get_env(:ansible_relay, :encrypted_boards_enabled, false)
    Application.put_env(:ansible_relay, :encrypted_boards_enabled, true)
    on_exit(fn -> Application.put_env(:ansible_relay, :encrypted_boards_enabled, previous) end)
    :ok
  end

  test "complete device envelopes activate an epoch and repeat registration does not rotate" do
    board = insert_board("private-one")
    grant = grant(board)
    public = "04" <> String.duplicate("11", 64)

    assert {:ok, key} =
             PrivateBoardKeys.register_device(board.hosted_board_id, grant, %{
               "agreement_public_key_hex" => public
             })

    envelope = envelope(board, key, public)

    assert {:ok, epoch} =
             PrivateBoardKeys.activate_epoch(
               board.hosted_board_id,
               grant,
               1,
               board.access_policy_version,
               [envelope]
             )

    assert epoch.epoch == 1
    assert Repo.get!(ForumHostBoard, board.hosted_board_id).encryption_state == "ready"

    assert {:ok, _same} =
             PrivateBoardKeys.register_device(board.hosted_board_id, grant, %{
               "agreement_public_key_hex" => public
             })

    assert Repo.get!(ForumHostBoard, board.hosted_board_id).encryption_state == "ready"
    assert {:ok, _, ^envelope} = PrivateBoardKeys.current_envelope(board.hosted_board_id, grant)
  end

  test "missing recipient envelope and plaintext content fail closed" do
    board = insert_board("private-two")
    grant = grant(board)
    public = "04" <> String.duplicate("22", 64)

    assert {:ok, key} =
             PrivateBoardKeys.register_device(board.hosted_board_id, grant, %{
               "agreement_public_key_hex" => public
             })

    assert {:error, :incomplete_epoch_envelopes} =
             PrivateBoardKeys.activate_epoch(
               board.hosted_board_id,
               grant,
               1,
               board.access_policy_version,
               []
             )

    ready = %{board | encryption_state: "ready", encryption_epoch: 1}

    assert {:error, :private_board_plaintext_forbidden} =
             PrivateBoardKeys.validate_content_envelope(ready, "post", "post-1", %{
               "boardId" => board.hosted_board_id,
               "content" => "must never reach the relay",
               "private_envelope" => envelope(board, key, public)
             })
  end

  defp insert_board(id) do
    policy =
      BoardAccessPolicy.default()
      |> Map.put("discovery", "credential_required")
      |> Map.put("read", %{"requirement" => "member"})
      |> Map.put("post", %{"requirement" => "member"})
      |> Map.put("requirements", %{
        "member" => %{
          "credential_type" => "PoliticalPartyMembershipCredential",
          "trusted_issuers" => ["did:web:issuer.elix.cool"],
          "claims" => [%{"path" => "membership", "op" => "equals", "value" => true}],
          "holder_binding" => "required",
          "status" => %{"required" => true, "max_age_seconds" => 300}
        }
      })
      |> Map.put("content_visibility", "end_to_end_encrypted")
      |> Map.put("federation", "disabled")

    Repo.insert!(%ForumHostBoard{
      hosted_board_id: id,
      slug: id,
      canonical_board_uri: "https://relay.example/boards/#{id}",
      title: id,
      access_policy: policy,
      access_policy_version: 1,
      content_visibility: "end_to_end_encrypted",
      federation_policy: %{"mode" => "disabled"},
      encryption_state: "rotation_required"
    })
  end

  defp grant(board) do
    %ForumHostBoardAccessGrant{
      hosted_board_id: board.hosted_board_id,
      pairwise_subject_hash: String.duplicate("a", 64),
      device_key_thumbprint: "device-signing-thumbprint",
      policy_version: board.access_policy_version,
      scopes: ["read", "moderate", "key:read"]
    }
  end

  defp envelope(board, key, public) do
    public_hash =
      :crypto.hash(:sha256, Base.decode16!(public, case: :mixed)) |> Base.encode16(case: :lower)

    %{
      "version" => 1,
      "board_id" => board.hosted_board_id,
      "epoch" => 1,
      "recipient_device_key_id" => key.device_key_id,
      "recipient_public_key_hash" => key.public_key_hash,
      "sender_public_key_hash" => public_hash,
      "policy_version" => board.access_policy_version,
      "algorithm" => "P256-HKDF-SHA256+A256GCM",
      "sender_public_key_hex" => public,
      "nonce" => Base.url_encode64(:binary.copy(<<1>>, 12), padding: false),
      "ciphertext" => Base.url_encode64(:binary.copy(<<2>>, 32), padding: false),
      "mac" => Base.url_encode64(:binary.copy(<<3>>, 16), padding: false)
    }
  end
end
