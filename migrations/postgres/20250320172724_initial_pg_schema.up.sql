CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE rule_type AS ENUM ('direct','computed_userset','tuple_to_userset','intersection','exclusion');
CREATE TYPE change_type AS ENUM ('CREATE', 'UPDATE', 'DELETE');

CREATE TABLE IF NOT EXISTS namespaces (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ NULL
);

CREATE TABLE IF NOT EXISTS relation_definitions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  namespace_id UUID REFERENCES namespaces(id) ON DELETE CASCADE,
  relation_name VARCHAR(255) NOT NULL,
  UNIQUE (namespace_id, relation_name)
);

CREATE TABLE IF NOT EXISTS relation_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  relation_definition_id UUID REFERENCES relation_definitions(id) ON DELETE CASCADE,
  rule_type rule_type NOT NULL,
  target_namespace_id UUID NULL REFERENCES namespaces(id) ON DELETE SET NULL,
  target_relation_id UUID NULL REFERENCES relation_definitions(id) ON DELETE SET NULL,
  source_relation_id UUID NULL REFERENCES relation_definitions(id) ON DELETE SET NULL
);

-- NOTE:
CREATE TABLE IF NOT EXISTS relationships (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  namespace_id UUID NOT NULL REFERENCES namespaces(id) ON DELETE CASCADE,
  object_id VARCHAR(255) NOT NULL,
  relation_id UUID NOT NULL REFERENCES relation_definitions(id) ON DELETE RESTRICT,
  subject_namespace_id UUID NOT NULL REFERENCES namespaces(id) ON DELETE RESTRICT,
  subject_id  VARCHAR(255) NOT NULL, -- NOTE: What is this subject_id and where is it coming from?
  subject_relation_id UUID NULL REFERENCES relation_definitions(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ NULL,  -- soft delete
  UNIQUE (namespace_id, object_id, relation_id, subject_namespace_id, subject_id, subject_relation_id)
);

CREATE TABLE IF NOT EXISTS relationship_changes (
  change_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  relationship_id UUID NOT NULL REFERENCES relationships(id) ON DELETE NO ACTION,
  change_type change_type NOT NULL,
  namespace_id UUID,
  object_id VARCHAR(255),
  relation_id UUID,
  subject_namespace_id UUID,
  subject_id VARCHAR(255),
  subject_relation_id UUID,
  previous_data JSONB NULL,
  new_data JSONB NULL,
  change_timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP -- NOTE: This should be used as a zookie, which means I would need to fetch the latest changes by max time if needed to verify?
);

CREATE TABLE IF NOT EXISTS authorization_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  subject_id VARCHAR(255) NOT NULL,
  namespace_id UUID NOT NULL REFERENCES namespaces(id) ON DELETE NO ACTION,
  object_id VARCHAR(255) NOT NULL,
  relation_id UUID NOT NULL REFERENCES relation_definitions(id) ON DELETE NO ACTION,
  granted BOOLEAN NOT NULL,
  result_code VARCHAR(255) NOT NULL, -- `GRANTED`, `DENIED_NO_RELATIONSHIP`, etc
  context JSONB NULL -- Additonal context such as address, ip, request parameters, etc
);

CREATE INDEX idx_relationships_object ON relationships (namespace_id, object_id, relation_id);
CREATE INDEX idx_relationships_subject ON relationships (subject_namespace_id, subject_id);
CREATE INDEX idx_relationships_subject_with_relation ON relationships (subject_namespace_id, subject_id, subject_relation_id) WHERE subject_relation_id IS NOT NULL;
CREATE INDEX idx_relationships_deleted ON relationships (deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_relation_definitions_namespace ON relation_definitions (namespace_id);
CREATE INDEX idx_relation_rules_relation_def ON relation_rules (relation_definition_id);
CREATE INDEX idx_relationship_changes_timestamp ON relationship_changes (change_timestamp);
CREATE INDEX idx_relationship_changes_relationship_id ON relationship_changes (relationship_id);
CREATE INDEX idx_authorization_logs_namespace_id ON authorization_logs (namespace_id);
CREATE INDEX idx_authorization_logs_relation_id ON authorization_logs (relation_id);

CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  return NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_namespaces_timestamp
BEFORE UPDATE ON namespaces
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_relationship_definitions_timestamp
BEFORE UPDATE ON relation_definitions
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE OR REPLACE FUNCTION log_relationship_change()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO relationship_changes (relationship_id, change_type, namespace_id, object_id, relation_id, subject_namespace_id, subject_id, subject_relation_id, new_data)
    VALUES (NEW.relationship_id, 'CREATE', NEW.namespace_id, NEW.object_id, NEW.relation_id, NEW.subject_namespace_id, NEW.subject_id, NEW.subject_relation_id, to_jsonb(NEW));
  IF TG_OP = 'UPDATE' THEN
    INSERT INTO relationship_changes (relationship_id, change_type, namespace_id, object_id, relation_id, subject_namespace_id, subject_id, subject_relation_id, previous_data, new_data)
    VALUES (NEW.relationship_id, 'UPDATE', NEW.namespace_id, NEW.object_id, NEW.relation_id, NEW.subject_namespace_id, NEW.subject_id, NEW.subject_relation_id, to_jsonb(OLD), to_jsonb(NEW));
  IF TG_OP = 'DELETE' THEN
    INSERT INTO relationship_changes (relationship_id, change_type, namespace_id, object_id, relation_id, subject_namespace_id, subject_id, subject_relation_id, previous_data)
    VALUES (OLD.relationship_id, 'DELETE', OLD.namespace_id, OLD.object_id, OLD.relation_id, OLD.subject_namespace_id, OLD.subject_id, OLD.subject_relation_id, to_jsonb(OLD));
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER log_insert_relationship
AFTER INSERT ON relationships
FOR EACH ROW EXECUTE FUNCTION log_relationship_change();

CREATE TRIGGER log_update_relationship
BEFORE UPDATE ON relationships
FOR EACH ROW EXECUTE FUNCTION log_relationship_change();

CREATE TRIGGER log_delete_relationship
AFTER DELETE ON relationships
FOR EACH ROW EXECUTE FUNCTION log_relationship_change();
