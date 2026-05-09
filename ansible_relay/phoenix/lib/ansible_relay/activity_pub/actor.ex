defmodule AnsibleRelay.ActivityPub.Actor do
  @moduledoc "Relay-owned ActivityPub actor and WebFinger document helpers."

  @context "https://www.w3.org/ns/activitystreams"

  def webfinger(actor, base_url, host) do
    %{
      subject: "acct:#{actor}@#{host}",
      aliases: [actor_url(actor, base_url)],
      links: [
        %{
          rel: "self",
          type: "application/activity+json",
          href: actor_url(actor, base_url)
        }
      ]
    }
  end

  def document(actor, base_url) do
    id = actor_url(actor, base_url)

    %{
      "@context" => @context,
      "id" => id,
      "type" => "Person",
      "preferredUsername" => actor,
      "name" => actor,
      "inbox" => "#{id}/inbox",
      "outbox" => "#{id}/outbox",
      "followers" => "#{id}/followers",
      "publicKey" => %{
        "id" => "#{id}#main-key",
        "owner" => id,
        "publicKeyPem" => ""
      }
    }
  end

  def actor_url(actor, base_url), do: "#{base_url}/users/#{actor}"
end
