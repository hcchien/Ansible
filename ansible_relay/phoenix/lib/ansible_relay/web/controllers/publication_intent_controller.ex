defmodule AnsibleRelay.Web.Controllers.PublicationIntentController do
  @moduledoc "Accepts app-signed publication intents for relay-side distribution."

  import Plug.Conn
  require Logger

  alias AnsibleRelay.{IdentityCache, PublicationIntentStore, SigVerifier}

  @required_fields ~w(intent_id author_did content_item_id action visibility payload payload_hash signature)
  @valid_actions ~w(publish update delete)
  @valid_visibility ~w(public unlisted)
  @signature_scheme "ed25519"

  def create(conn, params) do
    with :ok <- validate_fields(params, @required_fields),
         :ok <- validate_enum(params["action"], @valid_actions, "action"),
         :ok <- reject_private_visibility(params["visibility"]),
         :ok <- validate_enum(params["visibility"], @valid_visibility, "visibility"),
         :ok <- validate_signature_scheme(params["signature_scheme"]),
         :ok <- validate_signature_shape(params["signature"]),
         :ok <- validate_payload_hash(params["payload"], params["payload_hash"]),
         author_did = params["author_did"],
         :ok <- check_did_verified(author_did, params["signature"]),
         public_key = IdentityCache.public_key_hex(author_did),
         :ok <- check_signature(public_key, signing_payload(params), params["signature"]),
         {:ok, intent} <- PublicationIntentStore.accept(normalize(params)) do
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
        send_json(conn, 422, %{error: "invalid_signature_scheme", expected: @signature_scheme})

      {:error, :malformed_signature} ->
        log_rejected_signature(:malformed_signature, params)
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :payload_hash_mismatch} ->
        send_json(conn, 422, %{error: "payload_hash_mismatch"})

      {:error, :unverified_did} ->
        log_rejected_signature(:unverified_did, params)
        send_json(conn, 401, %{error: "unverified_did"})

      {:error, :bad_signature} ->
        log_rejected_signature(:bad_signature, params)
        send_json(conn, 401, %{error: "invalid_signature"})

      {:error, :duplicate} ->
        send_json(conn, 409, %{error: "duplicate_publication_intent"})
    end
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
  defp validate_signature_scheme(@signature_scheme), do: :ok
  defp validate_signature_scheme(_scheme), do: {:error, :invalid_signature_scheme}

  defp validate_signature_shape(signature) when is_binary(signature) do
    lower = String.downcase(signature)

    cond do
      dev_publication_signature?(lower) -> :ok
      String.starts_with?(lower, "dev") -> {:error, :malformed_signature}
      String.starts_with?(lower, "stub") -> {:error, :malformed_signature}
      String.starts_with?(lower, "deadbeef") -> {:error, :malformed_signature}
      String.contains?(lower, "stub") -> {:error, :malformed_signature}
      Regex.match?(~r/^[0-9a-f]{128}$/, lower) -> :ok
      true -> {:error, :malformed_signature}
    end
  end

  defp validate_signature_shape(_signature), do: {:error, :malformed_signature}

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

  defp check_signature(public_key, message, signature) when is_binary(signature) do
    if dev_publication_signature?(signature) do
      :ok
    else
      check_signature_with_public_key(public_key, message, signature)
    end
  end

  defp check_signature_with_public_key(public_key, message, signature) do
    if SigVerifier.verify_ed25519(public_key, message, signature),
      do: :ok,
      else: {:error, :bad_signature}
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

  defp normalize(params) do
    %{
      intent_id: params["intent_id"],
      author_did: params["author_did"],
      content_item_id: params["content_item_id"],
      action: params["action"],
      visibility: params["visibility"],
      payload: params["payload"],
      payload_hash: String.downcase(params["payload_hash"]),
      signature: String.downcase(params["signature"]),
      signature_scheme: params["signature_scheme"] || @signature_scheme
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
