defmodule AnsibleAppview.Ingest.External.HttpSignature do
  @moduledoc """
  Records the validity of an HTTP Signature accompanying a fetched AP item.

  CRITICAL: HTTP signatures are **transport authentication** — they prove the
  bytes came from a host controlling a key — they are NOT Elix identity and they
  must NEVER cause `sig_verified=true`. This module only *records* a status
  (`:valid | :invalid | :absent`) for observability/audit; the ingest path keeps
  external items at `sig_verified=false` regardless of the result.

  Pull-based ingest fetches public outboxes, where signed *responses* are
  uncommon, so the usual outcome is `:absent`. When an item carries a
  `signature`/`http_signature` hint (e.g. supplied by a test stub or a future
  signed-fetch path), we surface that as the recorded status. Verifying the
  cryptographic detail of remote keys is out of scope for this slice; the point
  is that the status is recorded and is decoupled from Elix verification.
  """

  @type status :: :valid | :invalid | :absent

  @doc """
  Derive the recorded HTTP-signature status for one fetched item.

  Looks for an explicit `"_http_signature_valid"` boolean hint (set by the
  fetch layer / test stub). Absent any hint, returns `:absent`.
  """
  @spec status(map()) :: status()
  def status(%{"_http_signature_valid" => true}), do: :valid
  def status(%{"_http_signature_valid" => false}), do: :invalid
  def status(_item), do: :absent
end
