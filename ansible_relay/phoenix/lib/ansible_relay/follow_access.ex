defmodule AnsibleRelay.FollowAccess do
  @moduledoc """
  Validates and projects approved-follower relationships from signed ops.

  A follower signs `follow`; the target signs `follow_grant`.  Neither side can
  create an accepted edge alone.  The grant payload is a minimal relationship
  VC and never carries identity or Wallet claims.
  """

  alias AnsibleRelay.OpStore

  @credential_types ["VerifiableCredential", "FollowGrantCredential"]

  def validate_op(%{"entity_type" => "follow"} = params) do
    with true <- params["op_type"] in ["insert", "delete"],
         {:ok, payload} <- decode_payload(params["payload"]),
         target when is_binary(target) and target != "" <- payload["targetDid"],
         true <- target == params["entity_id"],
         true <- target != params["author_did"],
         true <- valid_follow_state?(params["op_type"], payload["state"]) do
      :ok
    else
      _ -> {:error, :invalid_follow_request}
    end
  end

  def validate_op(%{"entity_type" => "follow_grant"} = params) do
    with true <- params["op_type"] in ["insert", "delete"],
         {:ok, payload} <- decode_payload(params["payload"]),
         follower when is_binary(follower) and follower != "" <- payload["followerDid"],
         target when is_binary(target) and target != "" <- payload["targetDid"],
         request_id when is_binary(request_id) and request_id != "" <- payload["requestOpId"],
         true <- target == params["author_did"],
         true <- follower == params["entity_id"],
         %{} = request <- OpStore.get_by_op_id(request_id),
         true <- matching_request?(request, follower, target),
         :ok <- validate_grant_body(params["op_type"], payload, follower, target) do
      :ok
    else
      _ -> {:error, :invalid_follow_grant}
    end
  end

  def validate_op(_params), do: :ok

  def state(follower_did, target_did) do
    ops = OpStore.follow_ops(follower_did, target_did)
    request = Enum.find(ops, &(&1.entity_type == "follow"))
    grant = Enum.find(ops, &(&1.entity_type == "follow_grant"))

    cond do
      is_nil(request) or request.op_type == "delete" ->
        :none

      grant && grant_for_request?(grant, request.op_id) && grant.op_type == "insert" ->
        :accepted

      grant && grant_for_request?(grant, request.op_id) && grant.op_type == "delete" ->
        rejection_state(grant)

      true ->
        :pending
    end
  end

  def active_grant?(follower_did, target_did),
    do: state(follower_did, target_did) == :accepted

  def pending_requests(target_did) do
    target_did
    |> OpStore.follow_requests_for()
    |> Enum.reduce({MapSet.new(), []}, fn op, {seen, result} ->
      follower = op.author_did

      cond do
        MapSet.member?(seen, follower) ->
          {seen, result}

        op.op_type == "insert" and state(follower, target_did) == :pending ->
          payload = decoded_or_empty(op.payload)

          {MapSet.put(seen, follower),
           [
             %{
               request_op_id: op.op_id,
               follower_did: follower,
               target_did: target_did,
               created_at: payload["createdAt"] || op.received_at
             }
             | result
           ]}

        true ->
          {MapSet.put(seen, follower), result}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  def relationship(follower_did, target_did) do
    %{follower_did: follower_did, target_did: target_did, state: state(follower_did, target_did)}
  end

  def decode_payload(payload) when is_map(payload), do: {:ok, payload}

  def decode_payload(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = decoded} ->
        {:ok, decoded}

      _ ->
        with {:ok, json} <- Base.decode64(payload),
             {:ok, %{} = decoded} <- Jason.decode(json) do
          {:ok, decoded}
        else
          _ -> {:error, :invalid_payload}
        end
    end
  end

  def decode_payload(_), do: {:error, :invalid_payload}

  defp decoded_or_empty(payload) do
    case decode_payload(payload) do
      {:ok, decoded} -> decoded
      _ -> %{}
    end
  end

  defp matching_request?(request, follower, target) do
    payload = decoded_or_empty(request.payload)

    request.entity_type == "follow" and request.op_type == "insert" and
      request.author_did == follower and request.entity_id == target and
      payload["targetDid"] == target
  end

  defp validate_grant_body("delete", payload, _follower, _target) do
    if payload["reason"] in ["rejected", "revoked"],
      do: :ok,
      else: {:error, :invalid_follow_grant}
  end

  defp validate_grant_body("insert", payload, follower, target) do
    credential = payload["credential"]
    subject = is_map(credential) && credential["credentialSubject"]

    cond do
      not is_map(credential) or not is_map(subject) ->
        {:error, :invalid_follow_grant}

      credential["type"] != @credential_types ->
        {:error, :invalid_follow_grant}

      credential["issuer"] != target ->
        {:error, :invalid_follow_grant}

      subject["id"] != follower or subject["targetDid"] != target or
          subject["relationship"] != "approved_follower" ->
        {:error, :invalid_follow_grant}

      not valid_timestamp?(credential["issuanceDate"]) ->
        {:error, :invalid_follow_grant}

      true ->
        :ok
    end
  end

  defp valid_follow_state?("insert", state), do: state in [nil, "requested"]
  defp valid_follow_state?("delete", state), do: state in [nil, "cancelled"]

  defp rejection_state(grant) do
    case decoded_or_empty(grant.payload)["reason"] do
      "rejected" -> :rejected
      _ -> :none
    end
  end

  defp grant_for_request?(grant, request_op_id) do
    decoded_or_empty(grant.payload)["requestOpId"] == request_op_id
  end

  defp valid_timestamp?(value) when is_binary(value),
    do: match?({:ok, _, _}, DateTime.from_iso8601(value))

  defp valid_timestamp?(_), do: false
end
