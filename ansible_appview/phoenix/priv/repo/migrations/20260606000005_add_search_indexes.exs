defmodule AnsibleAppview.Repo.Migrations.AddSearchIndexes do
  use Ecto.Migration

  @moduledoc """
  Trigram-based substring search. Chosen over tsvector because the network is
  bilingual (zh/en) and stock Postgres has no Chinese word tokenizer — trigram
  ILIKE matches CJK and Latin uniformly and is GIN-indexable.
  """

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Generated, lower-cased search blob over the public text of each item.
    alter table(:feed_items) do
      add :search_text, :text,
        generated:
          "ALWAYS AS (lower(coalesce(payload->>'body','') || ' ' || coalesce(payload->>'title','') || ' ' || coalesce(payload->>'content',''))) STORED"
    end

    execute "CREATE INDEX feed_items_search_trgm ON feed_items USING gin (search_text gin_trgm_ops)"

    execute "CREATE INDEX appview_profiles_handle_trgm ON appview_profiles USING gin (lower(coalesce(handle,'')) gin_trgm_ops)"

    execute "CREATE INDEX appview_profiles_name_trgm ON appview_profiles USING gin (lower(coalesce(display_name,'')) gin_trgm_ops)"
  end

  def down do
    execute "DROP INDEX IF EXISTS appview_profiles_name_trgm"
    execute "DROP INDEX IF EXISTS appview_profiles_handle_trgm"
    execute "DROP INDEX IF EXISTS feed_items_search_trgm"

    alter table(:feed_items) do
      remove :search_text
    end

    # Leave the pg_trgm extension in place; other objects may rely on it.
  end
end
