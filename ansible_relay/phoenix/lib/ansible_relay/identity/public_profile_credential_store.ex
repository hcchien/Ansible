defmodule AnsibleRelay.Identity.PublicProfileCredentialStore do
  @moduledoc """
  Privacy-minimized public-profile summaries derived only after Relay-side VP
  verification. Rows never contain a VC, credential id, holder document data,
  or a duplicate-prevention commitment.
  """

  import Ecto.Query

  alias AnsibleRelay.{Db.PublicProfileCredential, HumanAssurance, Repo}

  @supported ~w(
    TrisAuraHumanityCredential
    NationalityCredential
    TaiwanCitizenshipCredential
    AgeOver18Credential
  )

  def put_verified(did, credential_type, vc)
      when is_binary(did) and credential_type in @supported and is_map(vc) do
    with {:ok, attrs} <- public_attrs(did, credential_type, vc) do
      %PublicProfileCredential{}
      |> PublicProfileCredential.changeset(attrs)
      |> Repo.insert(
        on_conflict:
          {:replace,
           [
             :issuer_did,
             :badge_key,
             :badge_value,
             :valid_until,
             :verified_at,
             :updated_at
           ]},
        conflict_target: [:did, :credential_type]
      )
      |> case do
        {:ok, row} -> {:ok, to_public_map(row)}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def put_verified(_did, _credential_type, _vc), do: {:error, :unsupported_credential_type}

  def list_public(did, selected_types) when is_binary(did) and is_list(selected_types) do
    now = DateTime.utc_now()
    selected = Enum.filter(selected_types, &(&1 in @supported))

    if selected == [] do
      []
    else
      Repo.all(
        from(c in PublicProfileCredential,
          where: c.did == ^did and c.credential_type in ^selected and c.valid_until > ^now,
          order_by: [asc: c.credential_type]
        )
      )
      |> Enum.map(&to_public_map/1)
    end
  rescue
    _ -> []
  end

  def to_public_map(%PublicProfileCredential{} = row) do
    %{
      credential_type: row.credential_type,
      issuer_did: row.issuer_did,
      badge: row.badge_key,
      value: row.badge_value,
      valid_until: DateTime.to_iso8601(row.valid_until)
    }
  end

  defp public_attrs(did, credential_type, vc) do
    subject = Map.get(vc, "credentialSubject", %{})
    issuer = Map.get(vc, "issuer")

    with true <- is_map(subject),
         true <- is_binary(issuer) and issuer != "",
         {:ok, valid_until} <- valid_until(vc),
         {:ok, badge_key, badge_value} <- badge(credential_type, vc, subject) do
      now = DateTime.utc_now()

      {:ok,
       %{
         did: did,
         credential_type: credential_type,
         issuer_did: issuer,
         badge_key: badge_key,
         badge_value: badge_value,
         valid_until: valid_until,
         verified_at: now
       }}
    else
      _ -> {:error, :invalid_public_profile_claim}
    end
  end

  defp badge("TrisAuraHumanityCredential", vc, _subject) do
    assurance = HumanAssurance.from_credential("TrisAuraHumanityCredential", vc)
    {:ok, "human_assurance", HumanAssurance.compatibility_tier(assurance)}
  end

  defp badge("AgeOver18Credential", _vc, %{"ageOver18" => true}),
    do: {:ok, "age_over_18", "true"}

  defp badge("NationalityCredential", _vc, %{
         "nationalityVerified" => true,
         "nationality" => nationality
       })
       when is_binary(nationality) do
    code = nationality |> String.trim() |> String.upcase()
    if Regex.match?(~r/^[A-Z]{2,3}$/, code), do: {:ok, "nationality", code}, else: :error
  end

  defp badge("TaiwanCitizenshipCredential", _vc, %{"citizenshipVerified" => true}),
    do: {:ok, "taiwan_citizenship", "true"}

  defp badge(_, _, _), do: {:error, :invalid_public_profile_claim}

  defp valid_until(vc) do
    value = Map.get(vc, "validUntil") || Map.get(vc, "expirationDate")

    case value && DateTime.from_iso8601(value) do
      {:ok, instant, _offset} -> {:ok, instant}
      _ -> {:error, :missing_expiry}
    end
  end
end
