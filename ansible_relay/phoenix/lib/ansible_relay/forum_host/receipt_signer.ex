defmodule AnsibleRelay.ForumHost.ReceiptSigner do
  @moduledoc "Signs Forum Host acceptance receipts without impersonating the author."

  def sign(operation_hash) when is_binary(operation_hash) do
    with {:ok, {public_key_hex, seed}} <- keypair() do
      signature =
        :crypto.sign(:eddsa, :none, operation_hash, [seed, :ed25519])
        |> Base.encode16(case: :lower)

      {:ok,
       %{
         "scheme" => "ed25519",
         "key_id" => "forum-host-receipt-v1",
         "public_key_hex" => public_key_hex,
         "operation_hash" => operation_hash,
         "signature" => signature,
         "accepted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
       }}
    end
  end

  def public_key do
    with {:ok, {public_key_hex, _seed}} <- keypair() do
      {:ok,
       %{
         "key_id" => "forum-host-receipt-v1",
         "scheme" => "ed25519",
         "purpose" => "web-publication-receipt",
         "public_key_hex" => public_key_hex
       }}
    end
  end

  defp keypair do
    case Application.get_env(:ansible_relay, :forum_host_signing_key_hex) do
      hex when is_binary(hex) -> from_seed_hex(hex)
      nil -> {:ok, derived_dev_keypair()}
    end
  end

  defp from_seed_hex(hex) do
    with true <- byte_size(hex) == 64,
         {:ok, seed} <- Base.decode16(hex, case: :mixed),
         true <- byte_size(seed) == 32 do
      {public_key, _private} = :crypto.generate_key(:eddsa, :ed25519, seed)
      {:ok, {Base.encode16(public_key, case: :lower), seed}}
    else
      _ -> {:error, :invalid_forum_host_signing_key}
    end
  end

  defp derived_dev_keypair do
    seed =
      :crypto.hash(
        :sha256,
        "ansible_relay.forum_host_receipt.dev." <>
          to_string(node()) <> "." <> to_string(:erlang.get_cookie())
      )

    {public_key, _private} = :crypto.generate_key(:eddsa, :ed25519, seed)
    {Base.encode16(public_key, case: :lower), seed}
  end
end
