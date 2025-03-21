/*
 * DATABASE SCHEMA: Authorization Management System
 *
 * This schema defines the database structure for a comprehensive authorization management system
 * that implements relationship-based access control (ReBAC). The system tracks namespaces,
 * relation definitions, relationships between entities, and authorization decisions.
 *
 * File: schema.sql
 * Usage: Execute this script to create the initial database schema for the authorization system.
 */

-- Enable UUID generation capabilities
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define custom enumeration types for categorization
-- rule_type: Defines the types of relationship rules in the system
CREATE TYPE rule_type AS ENUM ('direct','computed_userset','tuple_to_userset','intersection','exclusion');
-- change_type: Specifies types of changes made to records for auditing purposes
CREATE TYPE change_type AS ENUM ('CREATE', 'UPDATE', 'DELETE');

-- Namespaces table: Organizes entities into logical groups
-- This table establishes separate domains or contexts for entity relationships
CREATE TABLE IF NOT EXISTS namespaces (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),  -- Unique identifier for the namespace
  name VARCHAR(255) NOT NULL UNIQUE,  -- Unique identifier for the namespace
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- When the namespace was created
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- When the namespace was last modified
  deleted_at TIMESTAMPTZ NULL  -- Supports soft deletion; NULL means active
);

-- Relation definitions table: Defines possible relations between entities
-- This table configures what types of relationships can exist between entities
CREATE TABLE IF NOT EXISTS relation_definitions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),  -- Unique identifier for the relation definition
  namespace_id UUID REFERENCES namespaces(id) ON DELETE CASCADE,  -- Associated namespace
  relation_name VARCHAR(255) NOT NULL,  -- Name of the relation (e.g., "owner", "viewer")
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- When the relation was created
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- When the relation was last modified
  deleted_at TIMESTAMPTZ NULL,  -- Supports soft deletion; NULL means active
  UNIQUE (namespace_id, relation_name)  -- Relation names must be unique within a namespace
);

-- Relation rules table: Defines rules for how relations are composed
-- This table defines how relations between entities are constructed and calculated
CREATE TABLE IF NOT EXISTS relation_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),  -- Unique identifier for the rule
  relation_definition_id UUID REFERENCES relation_definitions(id) ON DELETE CASCADE,  -- The relation this rule applies to
  rule_type rule_type NOT NULL,  -- Type of rule governing this relation
  target_namespace_id UUID NULL REFERENCES namespaces(id) ON DELETE RESTRICT,  -- Target namespace for the rule
  target_relation_id UUID NULL REFERENCES relation_definitions(id) ON DELETE SET NULL,  -- Target relation for the rule
  source_relation_id UUID NULL REFERENCES relation_definitions(id) ON DELETE SET NULL,  -- Source relation for the rule
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- When the rule was created
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- When the rule was last modified
  deleted_at TIMESTAMPTZ NULL  -- Supports soft deletion; NULL means active
);

-- Relationships table: Stores actual relationships between entities
-- This table records the concrete relationships between objects and subjects
CREATE TABLE IF NOT EXISTS relationships (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),  -- Unique identifier for the relationship
  namespace_id UUID NOT NULL REFERENCES namespaces(id) ON DELETE CASCADE,  -- Namespace containing the relationship
  object_id VARCHAR(255) NOT NULL,  -- The entity being accessed
  relation_id UUID NOT NULL REFERENCES relation_definitions(id) ON DELETE RESTRICT,  -- The relation type
  subject_namespace_id UUID NOT NULL REFERENCES namespaces(id) ON DELETE RESTRICT,  -- Namespace of the subject
  subject_id VARCHAR(255) NOT NULL,  -- The entity requesting access
  subject_relation_id UUID NULL REFERENCES relation_definitions(id) ON DELETE SET NULL,  -- For userset relationships
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- When the relationship was created
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- When the relationship was last modified
  deleted_at TIMESTAMPTZ NULL,  -- Supports soft deletion; NULL means active
  UNIQUE (namespace_id, object_id, relation_id, subject_namespace_id, subject_id, subject_relation_id)
);

-- Change log table: Records all changes to the system for auditing purposes
-- This table maintains a comprehensive audit trail of all modifications
CREATE TABLE IF NOT EXISTS change_log (
  version BIGSERIAL PRIMARY KEY,  -- Incremental version number
  change_type VARCHAR(50) NOT NULL,  -- Type of change made
  entity_type VARCHAR(50) NOT NULL,  -- Type of entity changed
  entity_id UUID NOT NULL,  -- ID of the changed entity
  operation VARCHAR(10) NOT NULL,  -- Operation performed (INSERT, UPDATE, DELETE)
  details JSONB NULL,  -- JSON details of the change
  user_id UUID NULL,  -- User who made the change, if available
  transaction_id UUID NULL,  -- Transaction identifier
  timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP  -- When the change occurred
);

-- Authorization logs table: Records access decisions
-- This table keeps a history of authorization decisions for auditing and analysis
CREATE TABLE IF NOT EXISTS authorization_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),  -- Unique identifier for the log entry
  timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- When the authorization was processed
  subject_id VARCHAR(255) NOT NULL,  -- Entity requesting access
  namespace_id UUID NOT NULL REFERENCES namespaces(id) ON DELETE NO ACTION,  -- Namespace of the object
  object_id VARCHAR(255) NOT NULL,  -- Entity being accessed
  relation_id UUID NOT NULL REFERENCES relation_definitions(id) ON DELETE NO ACTION,  -- Requested relation
  granted BOOLEAN NOT NULL,  -- Whether access was granted
  result_code VARCHAR(255) NOT NULL,  -- Reason code for decision
  context JSONB NULL  -- Additional request context information
);

-- Indexes to optimize query performance
CREATE INDEX idx_relationships_object ON relationships (namespace_id, object_id, relation_id);
CREATE INDEX idx_relationships_subject ON relationships (subject_namespace_id, subject_id);
CREATE INDEX idx_relationships_subject_with_relation ON relationships (subject_namespace_id, subject_id, subject_relation_id) WHERE subject_relation_id IS NOT NULL;
CREATE INDEX idx_relationships_deleted ON relationships (deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_relation_definitions_namespace ON relation_definitions (namespace_id);
CREATE INDEX idx_relation_rules_relation_def ON relation_rules (relation_definition_id);
CREATE INDEX idx_change_log_entity_type ON change_log (entity_type);
CREATE INDEX idx_change_log_entity_id ON change_log (entity_id);
CREATE INDEX idx_authorization_logs_namespace_id ON authorization_logs (namespace_id);
CREATE INDEX idx_authorization_logs_relation_id ON authorization_logs (relation_id);

-- Function to automatically update timestamp on record modification
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  return NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers to maintain updated_at timestamps
CREATE TRIGGER update_namespaces_timestamp
BEFORE UPDATE ON namespaces
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_relationship_definitions_timestamp
BEFORE UPDATE ON relation_definitions
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_relationships_timestamp
BEFORE UPDATE ON relationships
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Function to log changes to tables for auditing purposes
CREATE OR REPLACE FUNCTION log_change()
RETURNS TRIGGER AS $$
DECLARE
  current_user_id UUID;
  current_transaction_id UUID;
BEGIN
  BEGIN
    current_user_id := current_setting('heimdall.user_id')::UUID;
  EXCEPTION WHEN OTHERS THEN
    current_user_id := NULL;
  END;

  BEGIN
    current_transaction_id := current_setting('heimdall.transaction_id')::UUID;
  EXCEPTION WHEN OTHERS THEN
    current_transaction_id := NULL;
  END;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO change_log (change_type, entity_type, entity_id, operation, details, user_id, transaction_id)
    VALUES (TG_TABLE_NAME || '_insert', TG_TABLE_NAME, NEW.id, 'INSERT', to_jsonb(NEW), current_user_id, current_transaction_id);
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO change_log (change_type, entity_type, entity_id, operation, details, user_id, transaction_id)
    VALUES (TG_TABLE_NAME || '_update', TG_TABLE_NAME, NEW.id, 'UPDATE', jsonb_build_object('previous', to_jsonb(OLD), 'new', to_jsonb(NEW)), current_user_id, current_transaction_id);
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO change_log (change_type, entity_type, entity_id, operation, details, user_id, transaction_id)
    VALUES (TG_TABLE_NAME || '_delete', TG_TABLE_NAME, OLD.id, 'INSERT', to_jsonb(OLD), current_user_id, current_transaction_id);
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Triggers to log all changes to key tables
CREATE TRIGGER log_relationship_change
AFTER INSERT OR UPDATE OR DELETE ON relationships
FOR EACH ROW EXECUTE FUNCTION log_change();

CREATE TRIGGER log_namespace_change
AFTER INSERT OR UPDATE OR DELETE ON namespaces
FOR EACH ROW EXECUTE FUNCTION log_change();

CREATE TRIGGER log_relation_definition_change
AFTER INSERT OR UPDATE OR DELETE ON relation_definitions
FOR EACH ROW EXECUTE FUNCTION log_change();

CREATE TRIGGER log_relation_rule_change
AFTER INSERT OR UPDATE OR DELETE ON relation_rules
FOR EACH ROW EXECUTE FUNCTION log_change();
