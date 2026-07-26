defmodule AnsibleRelay.Web.Controllers.PublicationIntentController do
  @moduledoc "Accepts app-signed publication intents for relay-side distribution."

  import Plug.Conn
  require Logger

  alias AnsibleRelay.{
    DidAccountCache,
    IdentityCache,
    IdentityWritePolicy,
    PublicationIntentStore,
    ReputationTier
  }

  @required_fields ~w(intent_id author_did content_item_id action visibility payload payload_hash signature)
  @valid_actions ~w(publish update delete)
  @valid_visibility ~w(public unlisted)
  @signature_schemes ~w(ed25519 p256-sha256)

  def create(conn, params) do
    with :ok <- validate_fields(params, @required_fields),
         :ok <- validate_enum(params["action"], @valid_actions, "action"),
         :ok <- reject_private_visibility(params["visibility"]),
         :ok <- validate_enum(params["visibility"], @valid_visibility, "visibility"),
         :ok <- validate_signature_scheme(params["signature_scheme"]),
         :ok <- validate_note_payload(params["payload"]),
         :ok <- IdentityWritePolicy.validate(params["signature_scheme"]),
         :ok <- validate_signature_shape(params["signature"], params["signature_scheme"]),
         :ok <- validate_payload_hash(params["payload"], params["payload_hash"]),
         author_did = params["author_did"],
         :ok <- check_sync_capability(conn, author_did),
         :ok <- check_did_verified(author_did, params["signature"]),
         {:ok, actor_handle} <- check_activity_pub_enabled(author_did),
         :ok <- check_signature(author_did, signing_payload(params), params["signature"]),
         {:ok, intent} <- PublicationIntentStore.accept(normalize(params, actor_handle)) do
      send_json(conn, 202, %{
        accepted: true,
        publication_id: intent.publication_id,
        status: intent.status,
        delivery_status: intent.delivery_status
      })
    else
      {:error, :missing_fields, fields} ->
        send_json(conn, 422, %{error: "missing_required_fields", fields: fields})

      {:error, :invalid_enum, {field, value, valid}} ->
        send_json(conn, 422, %{error: "invalid_value", field: field, value: value, valid: valid})

      {:error, :private_visibility} ->
        send_json(conn, 422, %{error: "private_visibility_not_federated"})

      {:error, :invalid_signature_scheme} ->
        send_json(conn, 422, %{error: "invalid_signature_scheme", expected: @signature_schemes})

      {:error, :activity_pub_notes_only} ->
        send_json(conn, 422, %{error: "activity_pub_notes_only"})

      {:error, :unsupported_signing_algorithm} ->
        send_json(conn, 422, %{
          error: "unsupported_signing_algorithm",
          expected: IdentityWritePolicy.expected()
        })

      {:error, :malformed_signature} ->
        log_rejected_signature(:malformed_signature, params)
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :payload_hash_mismatch} ->
        send_json(conn, 422, %{error: "payload_hash_mismatch"})

      {:error, :unverified_did} ->
        log_rejected_signature(:unverified_did, params)
        send_json(conn, 401, %{error: "unverified_did"})

      {:error, :activity_pub_requires_verified_human} ->
        send_json(conn, 403, %{error: "activity_pub_requires_verified_human"})

      {:error, :activity_pub_account_unavailable} ->
        send_json(conn, 503, %{error: "activity_pub_account_unavailable"})

      {:error, :invalid_sync_capability} ->
        send_json(conn, 401, %{error: "invalid_sync_capability"})

      {:error, :bad_signature} ->
        log_rejected_signature(:bad_signature, params)
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :duplicate} ->
        send_json(conn, 409, %{error: "duplicate_publication_intent"})
    end
  end

  defp check_sync_capability(conn, did) do
    if AnsibleRelay.WebauthnSync.enforcement_enabled?(),
      do: AnsibleRelay.WebauthnSync.authorize(conn, did),
      else: :ok
  end

  def signing_payload(params) do
    Jason.encode!([
      params["author_did"],
      params["content_item_id"],
      params["action"],
      params["visibility"],
      String.downcase(params["payload_hash"])
    ])
  end

  defp validate_fields(params, required) do
    missing = Enum.filter(required, &(is_nil(params[&1]) or params[&1] == ""))
    if missing == [], do: :ok, else: {:error, :missing_fields, missing}
  end

  defp validate_enum(value, valid_values, field) do
    if value in valid_values,
      do: :ok,
      else: {:error, :invalid_enum, {field, value, valid_values}}
  end

  defp reject_private_visibility("private"), do: {:error, :private_visibility}
  defp reject_private_visibility(_visibility), do: :ok

  defp validate_signature_scheme(nil), do: :ok
  defp validate_signature_scheme(scheme) when scheme in @signature_schemes, do: :ok
  defp validate_signature_scheme(_scheme), do: {:error, :invalid_signature_scheme}

  defp validate_note_payload(%{"type" => "note"}), do: :ok
  defp validate_note_payload(_payload), do: {:error, :activity_pub_notes_only}

  defp validate_signature_shape(signature, signature_scheme) when is_binary(signature) do
    lower = String.downcase(signature)

    cond do
      dev_publication_signature?(lower) ->
        :ok

      String.starts_with?(lower, "dev") ->
        {:error, :malformed_signature}

      String.starts_with?(lower, "stub") ->
        {:error, :malformed_signature}

      String.starts_with?(lower, "deadbeef") ->
        {:error, :malformed_signature}

      String.contains?(lower, "stub") ->
        {:error, :malformed_signature}

      signature_scheme in [nil, "ed25519"] and Regex.match?(~r/^[0-9a-f]{128}$/, lower) ->
        :ok

      signature_scheme == "p256-sha256" and
        Regex.match?(~r/^[0-9a-f]{136,144}$/, lower) and rem(byte_size(lower), 2) == 0 ->
        :ok

      true ->
        {:error, :malformed_signature}
    end
  end

  defp validate_signature_shape(_signature, _signature_scheme),
    do: {:error, :malformed_signature}

  defp validate_payload_hash(payload, payload_hash) when is_binary(payload_hash) do
    expected =
      :crypto.hash(:sha256, canonical_json(payload))
      |> Base.encode16(case: :lower)

    if String.downcase(payload_hash) == expected,
      do: :ok,
      else: {:error, :payload_hash_mismatch}
  end

  defp validate_payload_hash(_payload, _payload_hash), do: {:error, :payload_hash_mismatch}

  defp check_did_verified(did, signature) do
    cond do
      IdentityCache.verified?(did) ->
        :ok

      dev_publication_signature?(signature) ->
        Logger.warning(
          "accepting unverified DID for development publication author=#{truncate(did, 36)}"
        )

        :ok

      true ->
        {:error, :unverified_did}
    end
  end

  defp check_signature(author_did, message, signature) when is_binary(signature) do
    if dev_publication_signature?(signature) do
      :ok
    else
      if IdentityCache.verify_signature(author_did, message, signature),
        do: :ok,
        else: {:error, :bad_signature}
    end
  end

  # ActivityPub is an explicit high-trust distribution rail. The actor handle
  # comes from the relay-owned account record, never from the client payload,
  # so a signed intent cannot publish under somebody else's fediverse name.
  # The credential/nullifier behind the tier remains relay-local and is never
  # copied into the ActivityPub payload.
  defp check_activity_pub_enabled(did) do
    case DidAccountCache.get(did) do
      {:ok, %{handle: handle, reputation_tier: tier}}
      when is_binary(handle) and handle != "" ->
        if ReputationTier.meets?(tier, "verified_human") do
          {:ok, handle}
        else
          {:error, :activity_pub_requires_verified_human}
        end

      {:error, :unavailable} ->
        {:error, :activity_pub_account_unavailable}

      _ ->
        {:error, :activity_pub_requires_verified_human}
    end
  end

  defp dev_publication_signature?(signature) when is_binary(signature) do
    Application.get_env(:ansible_relay, :allow_dev_publication_signatures, false) &&
      String.starts_with?(String.downcase(signature), "dev-signature-")
  end

  defp dev_publication_signature?(_signature), do: false

  defp log_rejected_signature(reason, params) do
    signature = Map.get(params, "signature", "")
    author_did = Map.get(params, "author_did", "")

    Logger.warning(
      "publication intent rejected reason=#{reason} author=#{truncate(author_did, 36)} " <>
        "signature_prefix=#{truncate(signature, 24)} signature_len=#{byte_size(to_string(signature))} " <>
        "dev_publication_signatures=#{Application.get_env(:ansible_relay, :allow_dev_publication_signatures, false)}"
    )
  end

  defp truncate(value, max) do
    value = to_string(value)

    if String.length(value) > max do
      String.slice(value, 0, max) <> "…"
    else
      value
    end
  end

  defp normalize(params, actor_handle) do
    %{
      intent_id: params["intent_id"],
      author_did: params["author_did"],
      content_item_id: params["content_item_id"],
      action: params["action"],
      visibility: params["visibility"],
      payload: Map.put(params["payload"], "actor", actor_handle),
      payload_hash: String.downcase(params["payload_hash"]),
      signature: String.downcase(params["signature"]),
      signature_scheme: params["signature_scheme"] || "ed25519"
    }
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

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
