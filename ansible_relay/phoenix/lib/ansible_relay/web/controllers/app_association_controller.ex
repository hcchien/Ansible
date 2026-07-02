defmodule AnsibleRelay.Web.Controllers.AppAssociationController do
  @moduledoc """
  OS universal-link association files (outbound sharing loop).

  Share URLs are derived from `canonical_board_uri`, which points at this
  host's origin — so this host must publish the association files for the OS
  to open `https://<host>/boards/...` links directly in the app:

    - iOS:     `/.well-known/apple-app-site-association` (+ the legacy
               root-path alias Apple still probes)
    - Android: `/.well-known/assetlinks.json`

  Fail-closed: each file 404s until its environment variables are configured,
  so an unconfigured deployment never publishes a bogus association.

    UNIVERSAL_LINK_IOS_APP_IDS         comma-separated `TEAMID.bundle.id`
    APP_LINK_ANDROID_PACKAGE           Android applicationId
    APP_LINK_ANDROID_SHA256_CERTS      comma-separated SHA-256 cert
                                       fingerprints (colon-separated bytes)
  """

  import Plug.Conn

  # GET /.well-known/apple-app-site-association (and /apple-app-site-association)
  def apple(conn, _params) do
    case csv_env("UNIVERSAL_LINK_IOS_APP_IDS") do
      [] ->
        send_json(conn, 404, %{error: "universal_links_not_configured"})

      app_ids ->
        # `components` is the modern (iOS 13+) matcher; `paths` keeps older
        # AASA parsers working. Both scope to shared-content routes only.
        send_json(conn, 200, %{
          applinks: %{
            details: [
              %{
                appIDs: app_ids,
                components: [%{"/" => "/boards/*"}],
                paths: ["/boards/*"]
              }
            ]
          }
        })
    end
  end

  # GET /.well-known/assetlinks.json
  def android(conn, _params) do
    package = System.get_env("APP_LINK_ANDROID_PACKAGE")
    fingerprints = csv_env("APP_LINK_ANDROID_SHA256_CERTS")

    if package in [nil, ""] or fingerprints == [] do
      send_json(conn, 404, %{error: "app_links_not_configured"})
    else
      send_json(conn, 200, [
        %{
          relation: ["delegate_permission/common.handle_all_urls"],
          target: %{
            namespace: "android_app",
            package_name: package,
            sha256_cert_fingerprints: fingerprints
          }
        }
      ])
    end
  end

  defp csv_env(name) do
    (System.get_env(name) || "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
