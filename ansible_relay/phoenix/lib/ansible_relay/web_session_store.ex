defmodule AnsibleRelay.WebSessionStore do
  @moduledoc """
  In-memory challenge and session store for app-mediated web sessions.

  The API is intentionally storage-shaped so it can move behind durable storage
  without changing the controller contract.
  """

  use GenServer

  @trust_tier "self_custody_did"
  @max_active_sessions_per_did 5
  @max_approvals_per_device_per_hour 3
  @approval_window_seconds 3_600

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def issue_challenge(attrs), do: GenServer.call(__MODULE__, {:issue_challenge, attrs})
  def get_challenge(challenge_id), do: GenServer.call(__MODULE__, {:get_challenge, challenge_id})

  def poll_challenge(challenge_id),
    do: GenServer.call(__MODULE__, {:poll_challenge, challenge_id})

  def approve_challenge(challenge_id, attrs),
    do: GenServer.call(__MODULE__, {:approve_challenge, challenge_id, attrs})

  def reject_challenge(challenge_id),
    do: GenServer.call(__MODULE__, {:reject_challenge, challenge_id})

  def get_session(session_token), do: GenServer.call(__MODULE__, {:get_session, session_token})

  def revoke_session(session_token),
    do: GenServer.call(__MODULE__, {:revoke_session, session_token})

  def list_sessions_for_subject(subject_did),
    do: GenServer.call(__MODULE__, {:list_sessions_for_subject, subject_did})

  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(_opts) do
    {:ok, %{challenges: %{}, sessions: %{}}}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{challenges: %{}, sessions: %{}}}
  end

  def handle_call({:issue_challenge, attrs}, _from, state) do
    now = DateTime.utc_now()
    ttl_seconds = int_attr(attrs, "ttl_seconds", 300)

    challenge = %{
      challenge_id: token("wsc"),
      web_origin: string_attr(attrs, "web_origin"),
      relay_origin: string_attr(attrs, "relay_origin"),
      audience: string_attr(attrs, "audience") || string_attr(attrs, "relay_origin"),
      scopes: list_attr(attrs, "scopes"),
      status: "pending",
      created_at: now,
      expires_at: DateTime.add(now, ttl_seconds, :second),
      approved_session_token: nil
    }

    state = put_in(state, [:challenges, challenge.challenge_id], challenge)
    {:reply, {:ok, challenge}, state}
  end

  def handle_call({:get_challenge, challenge_id}, _from, state) do
    {:reply, get_pending_challenge(state, challenge_id), state}
  end

  def handle_call({:poll_challenge, challenge_id}, _from, state) do
    {reply, state} =
      case Map.get(state.challenges, challenge_id) do
        nil ->
          {{:error, :not_found}, state}

        challenge ->
          expire_challenge_if_needed(state, challenge)
      end

    {:reply, reply, state}
  end

  def handle_call({:approve_challenge, challenge_id, attrs}, _from, state) do
    with {:ok, challenge} <- get_pending_challenge(state, challenge_id),
         {:ok, expires_at} <- fetch_datetime(attrs, :expires_at),
         {:ok, approving_device_id} <- fetch_string(attrs, :approving_device_id),
         scopes <- atom_attr(attrs, :scopes, []),
         subject_did <- atom_attr(attrs, :subject_did),
         :ok <- enforce_active_session_cap(state, subject_did),
         :ok <- enforce_device_approval_cooldown(state, subject_did, approving_device_id),
         true <- MapSet.subset?(MapSet.new(scopes), MapSet.new(challenge.scopes)) do
      now = DateTime.utc_now()

      session = %{
        session_token: token("wst"),
        subject_did: subject_did,
        approving_device_id: approving_device_id,
        web_origin: challenge.web_origin,
        relay_origin: challenge.relay_origin,
        audience: challenge.audience,
        scopes: scopes,
        trust_tier: @trust_tier,
        expires_at: expires_at,
        created_at: now,
        revoked_at: nil
      }

      challenge = %{challenge | status: "approved", approved_session_token: session.session_token}

      state =
        state
        |> put_in([:challenges, challenge_id], challenge)
        |> put_in([:sessions, session.session_token], session)

      {:reply, {:ok, session}, state}
    else
      false -> {:reply, {:error, :scope_not_allowed}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:reject_challenge, challenge_id}, _from, state) do
    case Map.get(state.challenges, challenge_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      challenge ->
        challenge = %{challenge | status: "rejected"}
        state = put_in(state, [:challenges, challenge_id], challenge)
        {:reply, {:ok, challenge}, state}
    end
  end

  def handle_call({:get_session, session_token}, _from, state) do
    {:reply, get_active_session(state, session_token), state}
  end

  def handle_call({:revoke_session, session_token}, _from, state) do
    case Map.get(state.sessions, session_token) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        session = %{session | revoked_at: DateTime.utc_now()}
        state = put_in(state, [:sessions, session_token], session)
        {:reply, {:ok, session}, state}
    end
  end

  def handle_call({:list_sessions_for_subject, subject_did}, _from, state) do
    sessions =
      state.sessions
      |> Map.values()
      |> Enum.filter(fn session ->
        session.subject_did == subject_did && active_session?(session)
      end)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})

    {:reply, {:ok, sessions}, state}
  end

  defp get_pending_challenge(state, challenge_id) do
    case Map.get(state.challenges, challenge_id) do
      nil ->
        {:error, :not_found}

      %{status: "pending"} = challenge ->
        if expired?(challenge.expires_at), do: {:error, :expired}, else: {:ok, challenge}

      %{status: "approved"} ->
        {:error, :consumed}

      %{status: "rejected"} ->
        {:error, :rejected}

      %{status: "expired"} ->
        {:error, :expired}
    end
  end

  defp expire_challenge_if_needed(state, %{status: "pending"} = challenge) do
    if expired?(challenge.expires_at) do
      challenge = %{challenge | status: "expired"}
      state = put_in(state, [:challenges, challenge.challenge_id], challenge)
      {{:ok, challenge}, state}
    else
      {{:ok, challenge}, state}
    end
  end

  defp expire_challenge_if_needed(state, challenge), do: {{:ok, challenge}, state}

  defp get_active_session(state, session_token) do
    case Map.get(state.sessions, session_token) do
      nil ->
        {:error, :not_found}

      %{revoked_at: revoked_at} when not is_nil(revoked_at) ->
        {:error, :revoked}

      %{expires_at: expires_at} when not is_nil(expires_at) ->
        if expired?(expires_at),
          do: {:error, :expired},
          else: {:ok, state.sessions[session_token]}
    end
  end

  defp enforce_active_session_cap(state, subject_did) do
    active_count =
      state.sessions
      |> Map.values()
      |> Enum.count(fn session ->
        session.subject_did == subject_did && active_session?(session)
      end)

    if active_count >= @max_active_sessions_per_did,
      do: {:error, :too_many_active_sessions},
      else: :ok
  end

  defp enforce_device_approval_cooldown(state, subject_did, approving_device_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@approval_window_seconds, :second)

    recent_count =
      state.sessions
      |> Map.values()
      |> Enum.count(fn session ->
        session.subject_did == subject_did &&
          session.approving_device_id == approving_device_id &&
          DateTime.compare(session.created_at, cutoff) == :gt
      end)

    if recent_count >= @max_approvals_per_device_per_hour,
      do: {:error, :approval_rate_limited},
      else: :ok
  end

  defp active_session?(session) do
    is_nil(session.revoked_at) && !expired?(session.expires_at)
  end

  defp expired?(%DateTime{} = expires_at),
    do: DateTime.compare(DateTime.utc_now(), expires_at) != :lt

  defp token(prefix) do
    "#{prefix}_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
  end

  defp string_attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, String.to_atom(key))
  defp list_attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, String.to_atom(key)) || []

  defp atom_attr(attrs, key, default \\ nil),
    do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) || default

  defp int_attr(attrs, key, default) do
    case Map.get(attrs, key) || Map.get(attrs, String.to_atom(key)) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> default
        end

      _ ->
        default
    end
  end

  defp fetch_datetime(attrs, key) do
    case atom_attr(attrs, key) do
      %DateTime{} = value ->
        {:ok, value}

      value when is_binary(value) ->
        DateTime.from_iso8601(value)
        |> case do
          {:ok, datetime, _offset} -> {:ok, datetime}
          error -> error
        end

      _ ->
        {:error, :invalid_expiry}
    end
  end

  defp fetch_string(attrs, key) do
    case atom_attr(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :"missing_#{key}"}
    end
  end
end
