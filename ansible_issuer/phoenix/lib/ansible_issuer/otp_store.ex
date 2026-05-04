defmodule AnsibleIssuer.OtpStore do
  @moduledoc """
  ETS-backed OTP store for email verification.

  Key: {did, email}
  Value: %{otp: string, expires_at: DateTime}

  Each OTP is single-use (consumed on verify_and_consume/3).
  """

  use GenServer
  require Logger

  @table :vc_otp_store

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Issue a new 6-character hex OTP for (did, email). Overwrites any existing entry."
  def issue(did, email) when is_binary(did) and is_binary(email) do
    ttl = Application.get_env(:ansible_issuer, :otp_ttl_seconds, 300)
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)
    otp = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    :ets.insert(@table, {{did, email}, %{otp: otp, expires_at: expires_at}})
    otp
  end

  @doc """
  Verify and consume an OTP for (did, email).
  Returns :ok, {:error, :expired_otp}, or {:error, :invalid_otp}.
  """
  def verify_and_consume(did, email, otp)
      when is_binary(did) and is_binary(email) and is_binary(otp) do
    key = {did, email}

    case :ets.lookup(@table, key) do
      [{^key, %{otp: ^otp, expires_at: exp}}] ->
        :ets.delete(@table, key)

        if DateTime.compare(DateTime.utc_now(), exp) == :lt do
          :ok
        else
          {:error, :expired_otp}
        end

      [{^key, _wrong_otp}] ->
        {:error, :invalid_otp}

      [] ->
        {:error, :invalid_otp}
    end
  end

  @doc "Clear all entries (intended for tests)."
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    Logger.info("OtpStore ETS table created")
    {:ok, %{}}
  end
end
