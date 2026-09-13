defmodule AnsibleRelay.Repo.Migrations.AddPublicReadIndex do
  use Ecto.Migration

  def up do
    # Both deployed wire encodings occur in historical ops. Invalid payloads
    # fail closed; decoding never changes the original signed bytes.
    execute("""
    CREATE FUNCTION relay_read_payload(value text) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE STRICT AS $$
    BEGIN
      BEGIN RETURN value::jsonb;
      EXCEPTION WHEN OTHERS THEN
        BEGIN RETURN convert_from(decode(value, 'base64'), 'UTF8')::jsonb;
        EXCEPTION WHEN OTHERS THEN RETURN '{}'::jsonb; END;
      END;
    END $$
    """)

    execute(
      "ALTER TABLE ops ADD COLUMN read_payload jsonb GENERATED ALWAYS AS (relay_read_payload(payload)) STORED"
    )

    create(index(:ops, [:entity_type, :entity_id, :id]))
    create(index(:ops, [:author_did, :id]))
    execute("CREATE INDEX ops_read_thread ON ops ((read_payload->>'threadId'), id)")

    execute("""
    CREATE VIEW relay_read_items AS
      SELECT latest.id AS log_id, latest.op_id,
        latest.author_did, latest.entity_type, latest.entity_id, latest.op_type,
        latest.payload AS signed_payload,
        COALESCE(folded.payload, '{}'::jsonb) AS payload,
        latest.signature, latest.schema_version, latest.received_at
      FROM (SELECT DISTINCT ON (entity_type, entity_id) * FROM ops
        ORDER BY entity_type, entity_id, id DESC) latest
      LEFT JOIN LATERAL (SELECT author_did FROM ops original
        WHERE original.entity_type = latest.entity_type AND original.entity_id = latest.entity_id
          AND original.op_type = 'insert' ORDER BY original.id LIMIT 1) original ON true
      LEFT JOIN LATERAL (
        SELECT jsonb_object_agg(fields.key, fields.value ORDER BY history.id) AS payload
        FROM ops history CROSS JOIN LATERAL jsonb_each(
          CASE WHEN jsonb_typeof(history.read_payload) = 'object' THEN history.read_payload ELSE '{}'::jsonb END
        ) fields
        WHERE history.entity_type = latest.entity_type AND history.entity_id = latest.entity_id
          AND (history.author_did = original.author_did OR EXISTS (
            SELECT 1 FROM did_elix_migrations m WHERE m.state = 'completed'
              AND m.legacy_did = original.author_did AND m.v1_did = history.author_did
          ))
      ) folded ON true
    """)
  end

  def down do
    execute("DROP VIEW relay_read_items")
    execute("DROP INDEX ops_read_thread")
    drop(index(:ops, [:author_did, :id]))
    drop(index(:ops, [:entity_type, :entity_id, :id]))
    execute("ALTER TABLE ops DROP COLUMN read_payload")
    execute("DROP FUNCTION relay_read_payload(text)")
  end
end
