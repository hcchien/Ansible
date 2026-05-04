defmodule AnsibleIssuer.Web.VcControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleIssuer.{OtpStore, VcIssuer}

  @router_opts AnsibleIssuer.Web.Router.init([])
  @valid_did "did:plc:abcdefghijklmnop"
  @valid_email "alice@example.com"

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> AnsibleIssuer.Web.Router.call(@router_opts)
  end

  setup do
    case OtpStore.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    OtpStore.reset()
    :ok
  end

  test "request_vc returns OTP in mock mode" do
    response = post_json("/api/v1/vc/request", %{"did" => @valid_did, "email" => @valid_email})
    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["status"] == "otp_sent"
    # mock_mode default is true in test env
    assert is_binary(body["otp"])
    assert byte_size(body["otp"]) == 6
  end

  test "request_vc rejects missing fields" do
    response = post_json("/api/v1/vc/request", %{"did" => @valid_did})
    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "missing_field"
  end

  test "request_vc rejects invalid email" do
    response =
      post_json("/api/v1/vc/request", %{"did" => @valid_did, "email" => "not-an-email"})

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "invalid_email"
  end

  test "issue_vc returns a signed W3C VC" do
    req = post_json("/api/v1/vc/request", %{"did" => @valid_did, "email" => @valid_email})
    otp = Jason.decode!(req.resp_body)["otp"]

    response =
      post_json("/api/v1/vc/issue", %{"did" => @valid_did, "email" => @valid_email, "otp" => otp})

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    vc = body["vc"]

    assert vc["type"] == ["VerifiableCredential", "EmailCredential"]
    assert vc["credentialSubject"]["id"] == @valid_did
    assert vc["credentialSubject"]["email"] == @valid_email
    assert vc["credentialSubject"]["emailVerified"] == true
    assert is_map(vc["proof"])
    assert vc["proof"]["type"] == "Ed25519Signature2020"
    assert is_binary(vc["proof"]["proofValue"])
  end

  test "issued VC proof signature is valid" do
    req = post_json("/api/v1/vc/request", %{"did" => @valid_did, "email" => @valid_email})
    otp = Jason.decode!(req.resp_body)["otp"]

    response =
      post_json("/api/v1/vc/issue", %{"did" => @valid_did, "email" => @valid_email, "otp" => otp})

    vc = Jason.decode!(response.resp_body)["vc"]
    assert VcIssuer.verify_vc_proof(vc) == true
  end

  test "issue_vc rejects wrong OTP" do
    post_json("/api/v1/vc/request", %{"did" => @valid_did, "email" => @valid_email})

    response =
      post_json("/api/v1/vc/issue", %{
        "did" => @valid_did,
        "email" => @valid_email,
        "otp" => "000000"
      })

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_otp"
  end

  test "OTP is single-use" do
    req = post_json("/api/v1/vc/request", %{"did" => @valid_did, "email" => @valid_email})
    otp = Jason.decode!(req.resp_body)["otp"]

    first =
      post_json("/api/v1/vc/issue", %{"did" => @valid_did, "email" => @valid_email, "otp" => otp})

    second =
      post_json("/api/v1/vc/issue", %{"did" => @valid_did, "email" => @valid_email, "otp" => otp})

    assert first.status == 200
    assert second.status == 401
    assert Jason.decode!(second.resp_body)["error"] == "invalid_otp"
  end
end
