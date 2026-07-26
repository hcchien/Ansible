defmodule AnsibleRelay.HumanAssurance do
  @moduledoc """
  Orthogonal assurance dimensions derived from issuer-signed VC claims.

  Identity/key control is intentionally not ranked against human evidence.
  A VP proves `did_key` control for this presentation; a separate WebAuthn
  ceremony may prove `passkey_uv` for a particular operation.
  """

  @type profile :: %{
          identity_control: String.t(),
          human_evidence: String.t(),
          uniqueness: String.t(),
          method_class: String.t()
        }

  @doc "Derives the assurance profile for a verified credential presentation."
  @spec from_credential(String.t(), map() | nil) :: profile()
  def from_credential("TrisAuraHumanityCredential", %{} = credential) do
    subject = Map.get(credential, "credentialSubject", %{})

    case {
      Map.get(subject, "humanVerified"),
      Map.get(subject, "humanAssurance"),
      Map.get(subject, "uniquenessAssurance")
    } do
      {true, "verified", uniqueness} when uniqueness in ["strong", "limited", "unknown"] ->
        %{
          identity_control: "did_key",
          human_evidence: "natural_person",
          uniqueness: uniqueness,
          method_class: Map.get(subject, "verificationMethodClass", "unspecified")
        }

      {true, "liveness", uniqueness} when uniqueness in ["limited", "unknown"] ->
        %{
          identity_control: "did_key",
          human_evidence: "liveness",
          uniqueness: uniqueness,
          method_class: Map.get(subject, "verificationMethodClass", "liveness")
        }

      {true, nil, nil} ->
        %{
          identity_control: "did_key",
          human_evidence: "legacy_verified",
          uniqueness: "unknown",
          method_class: "legacy"
        }

      _ ->
        none()
    end
  end

  def from_credential(_credential_type, _credential), do: none()

  @doc "Legacy scalar projection for existing posting and federation APIs."
  def compatibility_tier(%{human_evidence: "natural_person", uniqueness: "strong"}),
    do: "unique_human"

  def compatibility_tier(%{human_evidence: "natural_person"}), do: "humanity_limited"
  def compatibility_tier(%{human_evidence: "liveness"}), do: "humanity_limited"
  def compatibility_tier(%{human_evidence: "legacy_verified"}), do: "verified_human"
  def compatibility_tier(_profile), do: "basic"

  defp none do
    %{
      identity_control: "did_key",
      human_evidence: "none",
      uniqueness: "unknown",
      method_class: "none"
    }
  end
end
