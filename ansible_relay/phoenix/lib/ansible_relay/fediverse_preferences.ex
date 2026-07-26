defmodule AnsibleRelay.FediversePreferences do
  @moduledoc "Durable, DID-signed user consent and host policy for ActivityPub."

  import Ecto.Query

  alias AnsibleRelay.{Db.FediversePreference, Repo}

  def get_by_did(did), do: Repo.get_by(FediversePreference, did: did)
  def get_by_actor(actor), do: Repo.get_by(FediversePreference, actor: actor)

  def enabled_for_did?(did), do: match?(%{enabled: true}, get_by_did(did))
  def enabled_actor?(actor), do: match?(%{enabled: true}, get_by_actor(actor))

  def put(attrs) do
    case get_by_did(attrs.did) do
      nil ->
        %FediversePreference{}
        |> FediversePreference.changeset(attrs)
        |> Repo.insert()

      %{revision: revision} when attrs.revision <= revision ->
        {:error, :stale_revision}

      preference ->
        preference
        |> FediversePreference.changeset(attrs)
        |> Repo.update()
    end
  end

  def allowed_remote?(%FediversePreference{} = preference, actor_url, inbox_url \\ nil) do
    actor = normalize_actor(actor_url)
    domains = [domain(actor_url), domain(inbox_url)] |> Enum.reject(&is_nil/1)
    platform_blocks = platform_blocked_domains()

    cond do
      actor in preference.blocked_actors -> false
      Enum.any?(domains, &domain_blocked?(&1, platform_blocks)) -> false
      Enum.any?(domains, &domain_blocked?(&1, preference.blocked_domains)) -> false
      preference.domain_policy == "allowlist" ->
        domains != [] and Enum.all?(domains, &domain_allowed?(&1, preference.allowed_domains))

      true ->
        true
    end
  end

  def allowed_remote?(_, _, _), do: false

  def platform_blocked_domains do
    Application.get_env(:ansible_relay, :activity_pub_blocked_domains, [])
    |> normalize_domains()
  end

  def normalize_domains(values) when is_list(values) do
    values
    |> Enum.map(&normalize_domain/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def normalize_domains(_), do: []

  def normalize_actors(values) when is_list(values) do
    values
    |> Enum.map(&normalize_actor/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def normalize_actors(_), do: []

  def delete_followers_for_actor(actor) do
    Repo.delete_all(
      from(f in AnsibleRelay.Db.ActivityPubFollower, where: f.actor == ^actor)
    )
  end

  defp domain(nil), do: nil

  defp domain(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: "https", host: host} when is_binary(host) -> normalize_domain(host)
      _ -> normalize_domain(value)
    end
  end

  defp domain(_), do: nil

  defp normalize_domain(value) when is_binary(value) do
    value =
      value
      |> String.trim()
      |> String.trim_trailing(".")
      |> String.downcase()

    if value != "" and Regex.match?(~r/^[a-z0-9.-]+$/, value), do: value
  end

  defp normalize_domain(_), do: nil

  defp normalize_actor(value) when is_binary(value) do
    value = String.trim(value)

    case URI.parse(value) do
      %URI{scheme: "https", host: host} when is_binary(host) -> value
      _ -> nil
    end
  end

  defp normalize_actor(_), do: nil

  defp domain_blocked?(domain, blocks),
    do: Enum.any?(blocks, &(domain == &1 or String.ends_with?(domain, "." <> &1)))

  defp domain_allowed?(domain, allowed),
    do: Enum.any?(allowed, &(domain == &1 or String.ends_with?(domain, "." <> &1)))
end
