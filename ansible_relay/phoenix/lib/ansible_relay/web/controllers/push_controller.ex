defmodule AnsibleRelay.Web.Controllers.PushController do
  @moduledoc """
  Push token registry endpoints (Phase B notifications).

  Registration binds an opaque transport token to (subject_did, device_id)
  with the wake categories the user opted into. Requests are authenticated
  like other signed intents: Ed25519 by the subject DID over the sorted-key
  canonical JSON of the body with `request_signature` excluded, and the
  embedded timestamp must fall within ±5 minutes of relay time.

  Unregister deletes the row outright — mandatory per the notification plan's
  constitution review (disabling push must leave nothing to wake).
  """

  import Plug.Conn

  alias AnsibleRelay.{IdentityCache, SigVerifier}
  alias AnsibleRelay.Push.TokenRegistry

  @valid_platforms ~w(fcm apns)
  @valid_categories ~w(reply follow messenger)
  @register_required ~w(subject_did device_id push_token platform categories registered_at request_signature)
  @unregister_required ~w(subject_did device_id unregistered_at request_signature)
  @default_timestamp_window_seconds 300

  # POST /api/v1/push/tokens
  def register(conn, params) do
    with :ok <- validate_fields(params, @register_required),
         :ok <- validate_platform(params["platform"]),
         :ok <- validate_categories(params["categories"]),
         :ok <- validate_timestamp(params["registered_at"]),
         :ok <- verify_subject_signature(params),
         {:ok, outcome} <-
           TokenRegistry.register(%{
             subject_did: params["subject_did"],
             device_id: params["device_id"],
             push_token: params["push_token"],
             platform: params["platform"],
             categories: params["categories"]
           }) do
      send_json(conn, if(outcome == :created, do: 201, else: 200), %{ok: true})
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  # POST /api/v1/push/tokens/unregister
  def unregister(conn, params) do
    with :ok <- validate_fields(params, @unregister_required),
         :ok <- validate_timestamp(params["unregistered_at"]),
         :ok <- verify_subject_signature(params),
         {:ok, _deleted} <- TokenRegistry.unregister(params["subject_did"], params["device_id"]) do
      send_json(conn, 200, %{ok: true})
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  # --- Validation ---

  defp validate_fields(params, required) do
    missing = Enum.filter(required, &(is_nil(params[&1]) or params[&1] == ""))
    if missing == [], do: :ok, else: {:error, {:missing_fields, missing}}
  end

  defp validate_platform(platform) do
    if platform in @valid_platforms, do: :ok, else: {:error, :invalid_platform}
  end

  defp validate_categories(categories) when is_list(categories) do
    if Enum.all?(categories, &(&1 in @valid_categories)) do
      :ok
    else
      {:error, :invalid_categories}
    end
  end

  defp validate_categories(_categories), do: {:error, :invalid_categories}

  defp validate_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} ->
        if abs(DateTime.diff(DateTime.utc_now(), timestamp, :second)) <=
             timestamp_window_seconds() do
          :ok
        else
          {:error, :stale_timestamp}
        end

      _error ->
        {:error, :invalid_timestamp}
    end
  end

  defp validate_timestamp(_value), do: {:error, :invalid_timestamp}

  defp timestamp_window_seconds do
    Application.get_env(
      :ansible_relay,
      :push_token_timestamp_window_seconds,
      @default_timestamp_window_seconds
    )
  end

  # --- Signature (Ed25519 over canonical JSON, request_signature excluded) ---

  defp verify_subject_signature(params) do
    signature = params["request_signature"]
    message = params |> Map.delete("request_signature") |> canonical_json()

    case IdentityCache.public_key_hex(params["subject_did"]) do
      nil ->
        {:error, :unverified_did}

      public_key ->
        if SigVerifier.verify_ed25519(public_key, message, signature) do
          :ok
        else
          {:error, :invalid_signature}
        end
    end
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

  # --- Responses ---

  defp send_error(conn, {:missing_fields, fields}) do
    send_json(conn, 422, %{error: "missing_required_fields", fields: fields})
  end

  defp send_error(conn, reason) when reason in [:invalid_signature, :unverified_did] do
    send_json(conn, 401, %{error: to_string(reason)})
  end

  defp send_error(conn, %Ecto.Changeset{}) do
    send_json(conn, 422, %{error: "invalid_registration"})
  end

  defp send_error(conn, reason) do
    send_json(conn, 422, %{error: to_string(reason)})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
