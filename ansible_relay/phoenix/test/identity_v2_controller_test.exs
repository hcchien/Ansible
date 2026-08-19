defmodule AnsibleRelay.Web.IdentityV2ControllerTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias AnsibleRelay.{DidAccountCache, IdentityCache, Repo}
  alias AnsibleRelay.Web.Router

  @router_opts Router.init([])
  @valid_public_key String.duplicate("ab", 32)
  @valid_did "did:plc:abcdefghijklmnop"

  defp post_json(path, body) do
    conn(:post, path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> Router.call(@router_opts)
  end

  defp ed25519_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    {Base.encode16(public_key, case: :lower), private_key}
  end

  defp sign_nonce(private_key, nonce) do
    :eddsa
    |> :crypto.sign(:none, nonce, [private_key, :ed25519])
    |> Base.encode16(case: :lower)
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    case DidAccountCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case IdentityCache.start_link([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    DidAccountCache.reset()
    :ok
  end

  test "register issues a nonce for a passkeys public key" do
    response =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => @valid_public_key,
        "handle_suffix" => "alice"
      })

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert is_binary(body["nonce"])
    assert byte_size(body["nonce"]) > 20
    assert is_binary(body["expires_at"])
    assert body["handle"] == "alice.elix.cool"
  end

  test "register uses the configured handle domain for this Relay space" do
    previous = Application.get_env(:ansible_relay, :identity_handle_domain)
    Application.put_env(:ansible_relay, :identity_handle_domain, "new-elix.cool")

    on_exit(fn ->
      Application.put_env(:ansible_relay, :identity_handle_domain, previous)
    end)

    response =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => @valid_public_key,
        "handle_suffix" => "alice"
      })

    assert response.status == 200
    assert Jason.decode!(response.resp_body)["handle"] == "alice.new-elix.cool"
  end

  test "register rejects Ed25519 when the first-party write policy is P-256 only" do
    original = Application.get_env(:ansible_relay, :identity_write_algorithms)
    Application.put_env(:ansible_relay, :identity_write_algorithms, ["p256-sha256"])

    on_exit(fn ->
      Application.put_env(:ansible_relay, :identity_write_algorithms, original)
    end)

    response =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => @valid_public_key,
        "handle_suffix" => "legacy",
        "signing_algorithm" => "ed25519"
      })

    assert response.status == 422
    body = Jason.decode!(response.resp_body)
    assert body["error"] == "unsupported_signing_algorithm"
    assert body["expected"] == ["p256-sha256"]
  end

  test "register reserves a handle while a nonce is pending" do
    first =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => @valid_public_key,
        "handle_suffix" => "alice"
      })

    second =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => String.duplicate("cd", 32),
        "handle_suffix" => "alice"
      })

    assert first.status == 200
    assert second.status == 409
    assert Jason.decode!(second.resp_body)["error"] == "handle_pending"
  end

  test "register rejects the legacy public_key field" do
    response =
      post_json("/api/v2/identity/register", %{
        "public_key" => @valid_public_key,
        "handle_suffix" => "alice"
      })

    assert response.status == 422
    body = Jason.decode!(response.resp_body)
    assert body["error"] == "missing_fields"
    assert body["field"] == "public_key_hex"
  end

  test "register validates the public key and handle suffix" do
    bad_key =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => "not-hex",
        "handle_suffix" => "alice"
      })

    assert bad_key.status == 422
    assert Jason.decode!(bad_key.resp_body)["detail"] =~ "public_key_hex"

    bad_handle =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => @valid_public_key,
        "handle_suffix" => "-alice"
      })

    assert bad_handle.status == 422
    assert Jason.decode!(bad_handle.resp_body)["detail"] =~ "handle_suffix"
  end

  test "anchor rejects invalid signatures without consuming the nonce" do
    register =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => @valid_public_key,
        "handle_suffix" => "alice"
      })

    nonce = Jason.decode!(register.resp_body)["nonce"]

    response =
      post_json("/api/v2/identity/anchor", %{
        "did" => @valid_did,
        "public_key_hex" => @valid_public_key,
        "handle" => "alice.elix.cool",
        "registration_sig" => "00",
        "nonce" => nonce
      })

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "invalid_sig"
    assert :ok = DidAccountCache.consume_nonce(@valid_public_key, nonce)
  end

  test "anchor verifies a real Ed25519 signature and activates the DID" do
    {public_key_hex, private_key} = ed25519_keypair()

    register =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => public_key_hex,
        "handle_suffix" => "alice"
      })

    nonce = Jason.decode!(register.resp_body)["nonce"]
    signature = sign_nonce(private_key, nonce)

    response =
      post_json("/api/v2/identity/anchor", %{
        "did" => @valid_did,
        "public_key_hex" => public_key_hex,
        "handle" => "alice.elix.cool",
        "registration_sig" => signature,
        "nonce" => nonce
      })

    assert response.status == 200
    body = Jason.decode!(response.resp_body)
    assert body["did"] == @valid_did
    assert body["handle"] == "alice.elix.cool"
    assert {:ok, %{public_key_hex: ^public_key_hex}} = DidAccountCache.get(@valid_did)
    assert {:ok, %{public_key_hex: ^public_key_hex}} = IdentityCache.get(@valid_did)
  end

  test "same hardware identity can re-anchor after a local reinstall" do
    {public_key_hex, private_key} = ed25519_keypair()

    first_register =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => public_key_hex,
        "handle_suffix" => "alice"
      })

    first_nonce = Jason.decode!(first_register.resp_body)["nonce"]

    first_anchor =
      post_json("/api/v2/identity/anchor", %{
        "did" => @valid_did,
        "public_key_hex" => public_key_hex,
        "handle" => "alice.elix.cool",
        "registration_sig" => sign_nonce(private_key, first_nonce),
        "nonce" => first_nonce
      })

    assert first_anchor.status == 200
    :ok = IdentityCache.remove(@valid_did)

    retry_register =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => public_key_hex,
        "handle_suffix" => "alice"
      })

    assert retry_register.status == 200
    retry_nonce = Jason.decode!(retry_register.resp_body)["nonce"]

    retry_anchor =
      post_json("/api/v2/identity/anchor", %{
        "did" => @valid_did,
        "public_key_hex" => public_key_hex,
        "handle" => "alice.elix.cool",
        "registration_sig" => sign_nonce(private_key, retry_nonce),
        "nonce" => retry_nonce
      })

    assert retry_anchor.status == 200
    assert {:ok, %{public_key_hex: ^public_key_hex}} = IdentityCache.get(@valid_did)
  end

  test "anchor accepts development signatures only when enabled" do
    original = Application.get_env(:ansible_relay, :allow_dev_identity_signatures, false)
    Application.put_env(:ansible_relay, :allow_dev_identity_signatures, true)

    on_exit(fn ->
      Application.put_env(:ansible_relay, :allow_dev_identity_signatures, original)
    end)

    register =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => @valid_public_key,
        "handle_suffix" => "alice"
      })

    nonce = Jason.decode!(register.resp_body)["nonce"]

    response =
      post_json("/api/v2/identity/anchor", %{
        "did" => @valid_did,
        "public_key_hex" => @valid_public_key,
        "handle" => "alice.elix.cool",
        "registration_sig" => "dev-sig-local",
        "nonce" => nonce
      })

    assert response.status == 200
    assert Jason.decode!(response.resp_body)["did"] == @valid_did
  end

  test "anchor rejects a handle that was not bound to the registration nonce" do
    {public_key_hex, private_key} = ed25519_keypair()

    register =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => public_key_hex,
        "handle_suffix" => "alice"
      })

    nonce = Jason.decode!(register.resp_body)["nonce"]
    signature = sign_nonce(private_key, nonce)

    response =
      post_json("/api/v2/identity/anchor", %{
        "did" => @valid_did,
        "public_key_hex" => public_key_hex,
        "handle" => "bob.elix.cool",
        "registration_sig" => signature,
        "nonce" => nonce
      })

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["error"] == "handle_mismatch"
  end

  test "v1 registration binds nonce, DID, and genesis commitment" do
    {public_key_hex, private_key} = ed25519_keypair()

    register =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => public_key_hex,
        "handle_suffix" => "v1alice"
      })

    nonce = Jason.decode!(register.resp_body)["nonce"]

    commitment = %{
      "method" => "did:elix",
      "method_version" => 1,
      "genesis_key" => public_key_hex,
      "genesis_nonce" => String.duplicate("01", 32)
    }

    {:ok, did} = AnsibleRelay.DidElix.derive_v1(commitment)
    proof = AnsibleRelay.DidElix.registration_payload(nonce, did, commitment)

    response =
      post_json("/api/v2/identity/anchor", %{
        "did" => did,
        "public_key_hex" => public_key_hex,
        "handle" => "v1alice.elix.cool",
        "registration_sig" => sign_nonce(private_key, proof),
        "nonce" => nonce,
        "genesis_commitment" => commitment
      })

    assert response.status == 200
    assert Jason.decode!(response.resp_body)["did"] == did
  end

  test "v1 registration rejects commitment substitution without consuming nonce" do
    {public_key_hex, private_key} = ed25519_keypair()

    register =
      post_json("/api/v2/identity/register", %{
        "public_key_hex" => public_key_hex,
        "handle_suffix" => "bound"
      })

    nonce = Jason.decode!(register.resp_body)["nonce"]

    commitment = %{
      "method" => "did:elix",
      "method_version" => 1,
      "genesis_key" => public_key_hex,
      "genesis_nonce" => String.duplicate("02", 32)
    }

    {:ok, did} = AnsibleRelay.DidElix.derive_v1(commitment)
    proof = AnsibleRelay.DidElix.registration_payload(nonce, did, commitment)
    substituted = %{commitment | "genesis_nonce" => String.duplicate("03", 32)}

    response =
      post_json("/api/v2/identity/anchor", %{
        "did" => did,
        "public_key_hex" => public_key_hex,
        "handle" => "bound.elix.cool",
        "registration_sig" => sign_nonce(private_key, proof),
        "nonce" => nonce,
        "genesis_commitment" => substituted
      })

    assert response.status == 422
    assert Jason.decode!(response.resp_body)["error"] == "did_mismatch"
    assert :ok = DidAccountCache.consume_nonce(public_key_hex, nonce)
  end
end
