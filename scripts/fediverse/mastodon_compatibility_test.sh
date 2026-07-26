#!/usr/bin/env bash
set -euo pipefail

# Live Mastodon interoperability test. It uses a dedicated Mastodon test
# account to discover and follow an enabled Elix actor, then publishes a
# public mention and confirms that the signed Create reached Relay's durable
# inbound log. The status and follow are removed on exit.
#
# Required:
#   MASTODON_BASE_URL       e.g. https://mastodon.social
#   MASTODON_ACCESS_TOKEN   token for a disposable test account
#   RELAY_BASE_URL          e.g. https://relay-dev.elix.cool
#   ELIX_ACTOR              local Relay actor handle, without @domain

for name in MASTODON_BASE_URL MASTODON_ACCESS_TOKEN RELAY_BASE_URL ELIX_ACTOR; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 2
  fi
done

for command in curl jq; do
  command -v "${command}" >/dev/null || {
    echo "${command} is required" >&2
    exit 2
  }
done

mastodon="${MASTODON_BASE_URL%/}"
relay="${RELAY_BASE_URL%/}"
relay_host="$(printf '%s' "${relay}" | sed -E 's#^https?://([^/]+).*$#\1#')"
acct="${ELIX_ACTOR}@${relay_host}"
marker="elix-mastodon-compat-$(date +%s)-${RANDOM}"
status_id=""
account_id=""

api() {
  curl --fail-with-body --silent --show-error \
    -H "Authorization: Bearer ${MASTODON_ACCESS_TOKEN}" \
    "$@"
}

cleanup() {
  if [[ -n "${status_id}" ]]; then
    api -X DELETE "${mastodon}/api/v1/statuses/${status_id}" >/dev/null || true
  fi
  if [[ -n "${account_id}" ]]; then
    api -X POST "${mastodon}/api/v1/accounts/${account_id}/unfollow" >/dev/null || true
  fi
}
trap cleanup EXIT

me="$(api "${mastodon}/api/v1/accounts/verify_credentials")"
remote_actor="$(jq -er '.url' <<<"${me}")"

search="$(
  api --get \
    --data-urlencode "q=@${acct}" \
    --data-urlencode "type=accounts" \
    --data-urlencode "resolve=true" \
    "${mastodon}/api/v2/search"
)"
account_id="$(jq -er --arg acct "${acct}" '.accounts[] | select(.acct == $acct) | .id' <<<"${search}" | head -1)"
api -X POST "${mastodon}/api/v1/accounts/${account_id}/follow" >/dev/null

follow_seen=false
for _ in $(seq 1 30); do
  followers="$(curl --fail-with-body --silent --show-error -H 'Accept: application/activity+json' "${relay}/users/${ELIX_ACTOR}/followers")"
  if jq -e --arg actor "${remote_actor}" '.orderedItems | index($actor) != null' <<<"${followers}" >/dev/null; then
    follow_seen=true
    break
  fi
  sleep 2
done
[[ "${follow_seen}" == true ]] || {
  echo "Mastodon Follow was not accepted by Relay within 60 seconds" >&2
  exit 1
}

created="$(
  api -X POST \
    --data-urlencode "status=@${acct} ${marker}" \
    --data-urlencode "visibility=public" \
    "${mastodon}/api/v1/statuses"
)"
status_id="$(jq -er '.id' <<<"${created}")"

create_seen=false
for _ in $(seq 1 45); do
  delta="$(curl --fail-with-body --silent --show-error "${relay}/api/v1/federation/inbound?cursor=0&limit=500")"
  if jq -e --arg actor "${remote_actor}" --arg marker "${marker}" \
    '.activities[] | select(.activity_type == "Create" and .remote_actor == $actor and (.payload.object.content // "" | contains($marker)))' \
    <<<"${delta}" >/dev/null; then
    create_seen=true
    break
  fi
  sleep 2
done
[[ "${create_seen}" == true ]] || {
  echo "Signed Mastodon Create was not durably ingested within 90 seconds" >&2
  exit 1
}

echo "Mastodon compatibility passed: WebFinger, actor discovery, signed Follow/Accept, and signed public Create ingest."
