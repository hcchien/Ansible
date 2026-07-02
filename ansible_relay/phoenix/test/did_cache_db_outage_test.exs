defmodule AnsibleRelay.DidCacheDbOutageTest do
  @moduledoc """
  A DB/infrastructure outage during a DID lookup must be distinguishable from a
  genuine "unknown DID": the cache returns `{:error, :unavailable}` (not
  `:not_found`), and the op-ingest path maps that to a retryable 503 rather than
  a 401 that would prompt a client to (destructively) re-anchor.

  The outage is simulated by renaming the backing table inside the sandbox
  transaction so the read-through query raises; the sandbox rolls the rename
  back at the end of the test.
  """

  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{AbuseDetector, IdentityCache, OpStore, Repo}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    for mod <- [IdentityCache, AbuseDetector, OpStore, AnsibleRelay.DidAccountCache] do
      case mod.start_link([]) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end

    AbuseDetector.reset()
    :ok
  end

  # --- Unit: IdentityCache.get/1 distinguishes outage from miss ---

  test "IdentityCache.get returns :not_found for a genuinely unknown DID" do
    assert :not_found = IdentityCache.get("did:key:z6MkUnknown#{System.unique_integer()}")
  end

  test "IdentityCache.get returns {:error, :unavailable} on a DB fault" do
    did = "did:key:z6MkOutage#{System.unique_integer([:positive])}"

    with_db_fault(:verified_dids, fn ->
      assert {:error, :unavailable} = IdentityCache.get(did)
    end)
  end

  test "DidAccountCache.get returns {:error, :unavailable} on a DB fault" do
    did = "did:key:z6MkAcctOutage#{System.unique_integer([:positive])}"

    with_db_fault(:did_accounts, fn ->
      assert {:error, :unavailable} = AnsibleRelay.DidAccountCache.get(did)
    end)
  end

  # --- Integration: op ingest returns 503 (not 401) during the outage ---

  test "op ingest returns 503 (not 401) when identity verification is unavailable" do
    did = "did:key:z6MkIngestOutage#{System.unique_integer([:positive])}"
    {_public_key, private_key} = ed25519_keypair()

    response =
      with_db_fault(:verified_dids, fn ->
        post_json("/api/v1/ops", valid_op(did, private_key))
      end)

    assert response.status == 503
    body = Jason.decode!(response.resp_body)
    assert body["error"] == "verification_unavailable"
    assert body["retryable"] == true
  end

  # --- Helpers ---

  # Rename the table away so the next Repo query against it raises (simulating a
  # DB fault), run `fun`, then rename it back. If the raising query aborts the
  # transaction, the sandbox rollback restores the schema regardless.
  defp with_db_fault(table, fun) do
    Repo.query!("ALTER TABLE #{table} RENAME TO #{table}_faulted", [])
    result = fun.()
    restore_table(table)
    result
  end

  defp restore_table(table) do
    Repo.query!("ALTER TABLE #{table}_faulted RENAME TO #{table}", [])
  rescue
    _ ->
      # The faulting query aborted the transaction; the sandbox rollback will
      # restore the original schema, so nothing more to do here.
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

  defp valid_op(did, private_key) do
    op = %{
      "op_id" => "op-#{System.unique_integer()}",
      "author_did" => did,
      "entity_type" => "post",
      "entity_id" => "entity-#{System.unique_integer()}",
      "op_type" => "insert",
      "payload" => Base.encode64("hello world")
    }

    Map.put(op, "signature", sign(private_key, signing_payload(op)))
  end

  defp signing_payload(op) do
    %{
      "author_did" => op["author_did"],
      "entity_id" => op["entity_id"],
      "entity_type" => op["entity_type"],
      "op_id" => op["op_id"],
      "op_type" => op["op_type"],
      "payload" => op["payload"]
    }
    |> canonical_json()
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
end
