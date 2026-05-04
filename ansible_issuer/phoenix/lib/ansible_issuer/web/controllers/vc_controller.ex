defmodule AnsibleIssuer.Web.Controllers.VcController do
  @moduledoc """
  POST /api/v1/vc/request — issue an OTP for email verification
  POST /api/v1/vc/issue   — verify OTP and return a signed W3C EmailCredential VC
  """

  alias AnsibleIssuer.{OtpStore, VcIssuer}

  # POST /api/v1/vc/request
  def request_vc(conn, params) do
    with {:ok, did} <- require_field(params, "did"),
         {:ok, email} <- require_field(params, "email"),
         :ok <- validate_did(did),
         :ok <- validate_email(email) do
      otp = OtpStore.issue(did, email)
      mock_mode = Application.get_env(:ansible_issuer, :mock_mode, true)

      body =
        if mock_mode do
          # Dev / CI only — exposes OTP directly so clients can test without email.
          %{status: "otp_sent", hint: "mock mode — use this OTP directly", otp: otp}
        else
          %{status: "otp_sent", hint: "check your inbox for a 6-character code"}
        end

      send_json(conn, 200, body)
    else
      {:error, {:missing_field, field}} ->
        send_json(conn, 422, %{error: "missing_field", field: field})

      {:error, :invalid_did} ->
        send_json(conn, 422, %{error: "invalid_did"})

      {:error, :invalid_email} ->
        send_json(conn, 422, %{error: "invalid_email"})
    end
  end

  # POST /api/v1/vc/issue
  def issue_vc(conn, params) do
    with {:ok, did} <- require_field(params, "did"),
         {:ok, email} <- require_field(params, "email"),
         {:ok, otp} <- require_field(params, "otp"),
         :ok <- validate_did(did),
         :ok <- validate_email(email),
         :ok <- OtpStore.verify_and_consume(did, email, otp) do
      vc = VcIssuer.issue_email_vc(did, email)
      send_json(conn, 200, %{vc: vc})
    else
      {:error, {:missing_field, field}} ->
        send_json(conn, 422, %{error: "missing_field", field: field})

      {:error, :invalid_did} ->
        send_json(conn, 422, %{error: "invalid_did"})

      {:error, :invalid_email} ->
        send_json(conn, 422, %{error: "invalid_email"})

      {:error, :invalid_otp} ->
        send_json(conn, 401, %{error: "invalid_otp"})

      {:error, :expired_otp} ->
        send_json(conn, 401, %{error: "expired_otp"})
    end
  end

  # --- Helpers ---

  defp require_field(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:missing_field, key}}
      "" -> {:error, {:missing_field, key}}
      val -> {:ok, val}
    end
  end

  defp validate_did(did) when is_binary(did) do
    if Regex.match?(~r/\Adid:(plc:[a-z2-7]{10,}|web:.+)\z/, did),
      do: :ok,
      else: {:error, :invalid_did}
  end

  defp validate_did(_), do: {:error, :invalid_did}

  defp validate_email(email) when is_binary(email) do
    if Regex.match?(~r/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, email),
      do: :ok,
      else: {:error, :invalid_email}
  end

  defp validate_email(_), do: {:error, :invalid_email}

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
