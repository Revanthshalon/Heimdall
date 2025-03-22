-- =================================================================================================
-- Creation Date: 2025-03-20 17:27:24.000000
-- Author: Revanth Shalon Raj
-- Description: Database schema for authorization service inspired by Zanzibar
-- Version: 1.0
-- =================================================================================================
-- This schema implements a Google Zanzibar-inspired authorization model, which is a globally
-- distributed and consistent system for storing and evaluating access control relationships.
-- Google Zanzibar powers permissions for many Google products like Google Drive, YouTube, etc.
-- All timestamps are stored in UTC timezone.

-- Extensions necesary for the project
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";     -- For generating UUIDs
CREATE EXTENSION IF NOT EXISTS "btree_gist";    -- For indexing jsonb fields
CREATE EXTENSION IF NOT EXISTS "pg_partman";    -- For partitioning tables
CREATE EXTENSION IF NOT EXISTS "ltree";         -- For storing hierarchical data

-- Define types for the database
-- `rule_type` - Defines different rule types that enable complex permission modeling similar to Google Zanzibar's concepts
CREATE TYPE rule_type AS ENUM (
    'direct',                -- Direct assignment (user X has permission Y on object Z)
    'union',                 -- Combines multiple usersets with OR logic
    'intersection',          -- Combines multiple userset with AND logic
    'exclusion',             -- Removes a subset from userset (Set 1 - Set 2)
    'tuple-to-userset'       -- References another object's relation (object#relation)
);

-- `operation_type` - Used for auditing and tracking changes to permission relationships
CREATE TYPE operation_type AS ENUM (
    'create',                -- Records when new permissions are granted
    'update',                -- Records when existing permissions are modified
    'delete'                 -- Records when permissions are revoked
);

-- =================================================================================================
-- Core Configuration Tables
-- =================================================================================================

-- Namespaces define object types in the system
-- Each namespace represents a different resource type (like documents, folders, projects)
-- Fields:
--   id: Short identifier for the namespace (e.g., 'document', 'folder')
--   name: Human-readable name for the namespace
--   description: Optional detailed description of what this namespace represents
--   created_at: When this namespace was first defined
--   updated_at: When this namespace was last modified
CREATE TABLE IF NOT EXISTS namespaces (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Relations define the types of permissions available for each namespace
-- Example: For a 'document' namespace, relations might include 'viewer', 'editor', 'owner'
-- Fields:
--   id: Unique identifier for the relation
--   namespace_id: Which namespace this relation belongs to
--   name: The permission name (e.g., 'viewer', 'editor')
--   description: Optional description explaining what this permission allows
--   created_at: When this relation was created
--   updated_at: When this relation was last updated
--   deleted_at: Soft delete support - when this relation was deprecated
CREATE TABLE IF NOT EXISTS relations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id VARCHAR(64) NOT NULL REFERENCES namespaces(id) ON DELETE RESTRICT,
    name VARCHAR(64) NOT NULL,
    description TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL,
    UNIQUE (namespace_id, name)
);

-- Relation rules define how permissions are computed and inherited
-- These rules implement the complex permission logic of Zanzibar
-- Fields:
--   id: Unique identifier for this rule
--   namespace_id: The namespace this rule applies to
--   relation_name: Which permission/relation this rule defines
--   rule_type: The type of rule (direct, union, intersection, etc.)
--   ttu_object_namespace: Target namespace for permission checking (for tuple-to-userset)
--   ttu_relation: Target relation to check in that namespace (for tuple-to-userset)
--   child_relations: Array of relation names combined in this rule (for union, intersection, exclusion)
--   expression: Textual representation of complex rules (e.g., "viewer + editor - blocked")
--   priority: Determines order of rule evaluation when multiple rules apply
--   created_at: When this rule was created
--   updated_at: When this rule was last updated
--   deleted_at: Soft delete support - when this rule was deprecated
CREATE TABLE IF NOT EXISTS relation_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id VARCHAR(64) NOT NULL REFERENCES namespaces(id) ON DELETE RESTRICT,
    relation_name VARCHAR(64) NOT NULL,
    rule_type rule_type NOT NULL,

    -- For `tuple-to-userset` rule_type
    ttu_object_namespace VARCHAR(64) NULL,
    ttu_relation VARCHAR(64) NULL,

    -- For `union`, `intersection`, `exclusion` rule_types
    child_relations JSONB NULL,

    -- Rule expression in zanibar syntax
    expression TEXT NULL,

    -- Rule precedence (lower numbers are evaluated first)
    priority INT NOT NULL DEFAULT 100,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL,

    FOREIGN KEY (namespace_id, relation_name) REFERENCES relations(namespace_id, name) ON DELETE RESTRICT,
    UNIQUE (namespace_id, relation_name, priority)
);

-- =================================================================================================
-- Core Permission Data Tables
-- =================================================================================================

-- Relationship tuples store the actual permission relationships in the system
-- Each tuple represents a specific permission granted to a subject for an object
-- Fields:
--   id: Unique identifier for this permission relationship
--   namespace_id: Which namespace the object belongs to
--   object_id: The specific object being accessed
--   relation: The permission type being granted
--   subject_type: The type of entity receiving permission (user, group, etc.)
--   subject_id: The specific entity receiving permission
--   userset_namespace: For tuple-to-userset rules, which namespace to check
--   userset_relation: For tuple-to-userset rules, which relation to check
--   created_at: When this permission was granted
--   updated_at: When this permission was last modified
--   zookie_token: Consistency token for distributed validation
CREATE TABLE IF NOT EXISTS relationship_tuples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id VARCHAR(64) NOT NULL,
    object_id VARCHAR(255) NOT NULL, -- the object whose permissions are being set (e.g., document_id)
    relation VARCHAR(64) NOT NULL, -- the permission being granted (e.g., 'viewer')

    -- Subject can be a user or object (group, role, etc.)
    subject_type VARCHAR(64) NOT NULL, -- 'user', 'group', 'role', etc.
    subject_id VARCHAR(255) NOT NULL, -- the ID of the subject (e.g., user_id)

    -- Optional fields for additional context
    userset_namespace VARCHAR(64) NULL, -- for tuple-to-userset rules
    userset_relation VARCHAR(64) NULL, -- for tuple-to-userset rules

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    zookie_token VARCHAR(255) NOT NULL, -- Consistency token for this relationship

    -- Enforce foreign key constraints
    FOREIGN KEY (namespace_id, relation) REFERENCES relations(namespace_id, name) ON DELETE RESTRICT,

    -- Unique constraints to prevent duplicates
    UNIQUE (namespace_id, object_id, relation, subject_type, subject_id, COALESCE(userset_namespace, ''), COALESCE(userset_relation, ''))
) PARTITION BY LIST (namespace_id);

-- Creating indices for common access patterns
CREATE INDEX IF NOT EXISTS idx_tuples_object ON relationship_tuples (namespace_id, object_id, relation);
CREATE INDEX IF NOT EXISTS idx_tuples_subject ON relationship_tuples (subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_tuples_userset ON relationship_tuples (userset_namespace, userset_relation) WHERE userset_namespace IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tuples_zookie ON relationship_tuples (zookie_token);

-- =================================================================================================
-- Consistency Management Tables
-- =================================================================================================

-- Zookies manage consistency tokens for distributed permission validation
-- Each zookie represents a specific version of a permission relationship
-- Fields:
--   token: Unique identifier for this consistency token
--   timestamp: When this token was created
--   version: Sequential version number for this token
--   transaction_id: Which transaction created this token
--   shard_id: Which database shard contains this token
--   created_at: When this token was first generated
--   expired_at: When this token will no longer be valid
CREATE TABLE IF NOT EXISTS zookies (
    token VARCHAR(255) PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL,
    transaction_id UUID NOT NULL,
    shard_id INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expired_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP + INTERVAL '7 days'
);

CREATE INDEX IF NOT EXISTS idx_zookies_version ON zookies (version);
CREATE INDEX IF NOT EXISTS idx_zookies_expires ON zookies (expired_at);

-- Transaction log records all changes to permission relationships for consistency and auditability
-- Fields:
--   id: Unique identifier for this transaction record
--   timestamp: When this transaction occurred
--   version_number: Sequential version number for this transaction
--   operation: Type of operation (create, update, delete)
--   namespace_id: Which namespace was affected
--   object_id: Which object was affected
--   relation: Which permission type was affected
--   subject_type: What type of subject was involved
--   subject_id: Which specific subject was involved
--   userset_namespace: For tuple-to-userset operations, which namespace to check
--   userset_relation: For tuple-to-userset operations, which relation to check
--   zookie_token: Consistency token for this transaction
--   payload: Complete data associated with this transaction
--   status: Current state of this transaction (pending, committed, etc.)
CREATE TABLE IF NOT EXISTS transaction_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version_number BIGINT NOT NULL,
    operation operation_type NOT NULL,

    namespace_id VARCHAR(64) NOT NULL,
    object_id VARCHAR(255) NOT NULL,
    relation VARCHAR(64) NOT NULL,
    subject_type VARCHAR(64) NOT NULL,
    subject_id VARCHAR(255) NOT NULL,
    userset_namespace VARCHAR(64) NULL,
    userset_relation VARCHAR(64) NULL,

    -- Metadata
    zookie_token VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'COMMITTED' CHECK (status IN ('PENDING', 'COMMITTED', 'FAILED', 'REPLICATED'))
);

CREATE INDEX IF NOT EXISTS idx_transaction_log_version ON transaction_log (version_number);
CREATE INDEX IF NOT EXISTS idx_transaction_log_status ON transaction_log (status, version_number);
CREATE INDEX IF NOT EXISTS idx_transaction_log_namespace_object ON transaction_log (namespace_id, object_id);

-- Replication status tracks the state of database nodes in a distributed system
-- Fields:
--   node_id: Unique identifier for this database node
--   last_applied_version: Latest transaction version applied on this node
--   last_applied_timestamp: When the latest transaction was applied
--   heartbeat_at: Last time this node reported its status
--   is_primary: Whether this node is the primary writer
--   status: Current operational status of this node
--   sync_lag_ms: How far behind this node is from the primary (in milliseconds)
CREATE TABLE IF NOT EXISTS replication_status (
    node_id VARCHAR(64) PRIMARY KEY,
    last_applied_version BIGINT NOT NULL,
    last_applied_timestamp TIMESTAMPTZ NOT NULL,
    heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'DEGRADED')),
    sync_lag_ms INT NULL
);

-- =================================================================================================
-- Monitoring and Auditing Tables
-- =================================================================================================

-- Auth decisions records each permission check for monitoring and auditing
-- Fields:
--   id: Unique identifier for this permission check
--   timestamp: When this permission check occurred
--   request_id: Identifier linking related permission checks in a single request
--   subject_type: What type of subject was checked
--   subject_id: Which specific subject was checked
--   namespace_id: Which namespace was checked
--   object_id: Which object was checked
--   relation: Which permission type was checked
--   permitted: Whether access was granted
--   cached: Whether the result came from cache
--   latency_ms: How long the permission check took
--   evaluation_path: Record of which rules were evaluated
--   zookie_token: Consistency token used for this check
--   waited_for_consistency: Whether the check had to wait for consistency
--   consistency_wait_ms: How long the check waited for consistency
CREATE TABLE IF NOT EXISTS auth_decisions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Request Details
    request_id UUID NOT NULL,
    subject_type VARCHAR(64) NOT NULL,
    subject_id VARCHAR(255) NOT NULL,
    namespace_id VARCHAR(64) NOT NULL,
    object_id VARCHAR(255) NOT NULL,
    relation VARCHAR(64) NOT NULL,

    -- Decision Details
    permitted BOOLEAN NOT NULL,
    cached BOOLEAN NOT NULL DEFAULT FALSE,

    -- Performance Metrics
    latency_ms INT NOT NULL,
    evaluation_path JSONB NOT NULL,

    -- Consistency Info
    zookie_token VARCHAR(255) NULL,
    waited_for_consistency BOOLEAN NOT NULL DEFAULT FALSE,
    consistency_wait_ms INT NULL
);

CREATE INDEX IF NOT EXISTS idx_auth_decisions_request ON auth_decisions (request_id);
CREATE INDEX IF NOT EXISTS idx_auth_decisions_subject ON auth_decisions (subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_auth_decisions_object ON auth_decisions (namespace_id, object_id);
CREATE INDEX IF NOT EXISTS idx_auth_decisions_timestamp ON auth_decisions (timestamp);

-- Audit log records all administrative and security-relevant actions in the system
-- Fields:
--   id: Unique identifier for this audit entry
--   timestamp: When this action occurred
--   actor: Who performed the action
--   action: What type of action was performed
--   resource_type: What type of resource was affected
--   resource_id: Which specific resource was affected
--   details: Complete data about the action
--   trace_id: Identifier for tracing this action across system components
--   client_ip: IP address of the client that initiated the action
--   client_info: Additional client context information
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor VARCHAR(255) NOT NULL,
    action VARCHAR(64) NOT NULL,
    resource_type  VARCHAR(64) NOT NULL,
    resource_id VARCHAR(255) NOT NULL,
    details JSONB NOT NULL,
    trace_id UUID NULL,
    client_ip INET NULL,
    client_info JSONB NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log (timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_log (actor);
CREATE INDEX IF NOT EXISTS idx_audit_resource ON audit_log (resource_type, resource_id);

-- =================================================================================================
-- Performance Optimization Tables
-- =================================================================================================

-- Permissions cache stores pre-computed permission check results for fast access
-- Fields:
--   id: Unique identifier for this cache entry
--   namespace_id: Which namespace was checked
--   object_id: Which object was checked
--   relation: Which permission type was checked
--   subject_type: What type of subject was checked
--   subject_id: Which specific subject was checked
--   permitted: Whether access was granted
--   computed_at: When this permission check was originally computed
--   valid_until: When this cache entry expires
--   max_zookie_version: Latest consistency token version used in computing this result
--   cache_key: Hash key for quick lookup of this cache entry
CREATE TABLE IF NOT EXISTS permissions_cache (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id VARCHAR(64) NOT NULL,
    object_id VARCHAR(255) NOT NULL,
    relation VARCHAR(64) NOT NULL,
    subject_type VARCHAR(64) NOT NULL,
    subject_id VARCHAR(255) NOT NULL,
    permitted BOOLEAN NOT NULL,
    computed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMPTZ NOT NULL,
    max_zookie_version BIGINT NOT NULL,
    cache_key VARCHAR(255) NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_permissions_cache_lookup ON permissions_cache (namespace_id, object_id, relation, subject_type, subject_id);
CREATE INDEX IF NOT EXISTS idx_permissions_cache_expiry ON permissions_cache (valid_until);
CREATE INDEX IF NOT EXISTS idx_cache_zookie ON permissions_cache (max_zookie_version);

-- =================================================================================================
-- Functions & Procedures
-- =================================================================================================

-- Function: update_timestamp
-- Automatically updates the 'updated_at' timestamp field to the current time
-- Used by triggers to maintain accurate last-modified timestamps
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: update_namespaces_timestamp
-- Automatically updates the timestamp when a namespace record is modified
CREATE TRIGGER update_namespaces_timestamp
BEFORE UPDATE ON namespaces
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Trigger: update_relations_timestamp
-- Automatically updates the timestamp when a relation record is modified
CREATE TRIGGER update_relations_timestamp
BEFORE UPDATE ON relations
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Trigger: update_relation_rules_timestamp
-- Automatically updates the timestamp when a relation rule is modified
CREATE TRIGGER update_relation_rules_timestamp
BEFORE UPDATE ON relation_rules
FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Function: cleanup_zookies
-- Removes expired consistency tokens and cache entries to maintain database performance
-- Returns the total number of records removed across both tables
CREATE OR REPLACE FUNCTION cleanup_zookies() RETURNS INTEGER AS $$
DECLARE
    zookies_removed INTEGER;
    cache_removed INTEGER;
BEGIN
    -- Remove expired zookies
    DELETE FROM zookies
    WHERE expired_at < CURRENT_TIMESTAMP
    RETURNING COUNT(*) INTO zookies_removed;

    -- Remove expired cache entries
    DELETE FROM permissions_cache
    WHERE valid_until < CURRENT_TIMESTAMP
    RETURNING COUNT(*) INTO cache_removed;

    RETURN zookies_removed + cache_removed;
END;
$$ LANGUAGE plpgsql;

-- Function: log_change
-- Records all data changes to the audit_log table for compliance and security tracking
-- Captures contextual information including the actor, trace ID, and client details
CREATE OR REPLACE FUNCTION log_change()
RETURNS TRIGGER AS $$
DECLARE
    current_actor VARCHAR(255);
    current_trace_id UUID;
    current_client_ip INET;
    current_client_info JSONB;
BEGIN
    BEGIN
        current_actor := current_setting('heimdall.actor');
    EXCEPTION WHEN OTHERS THEN
        current_actor := 'system';
    END;

    BEGIN
        current_trace_id := current_setting('heimdall.trace_id')::UUID;
    EXCEPTION WHEN OTHERS THEN
        current_trace_id := NULL;
    END;

    BEGIN
        current_client_ip := current_setting('heimdall.client_ip')::INET;
    EXCEPTION WHEN OTHERS THEN
        current_client_ip := NULL;
    END;

    BEGIN
        current_client_info := current_setting('heimdall.client_info')::JSONB;
    EXCEPTION WHEN OTHERS THEN
        current_client_info := NULL;
    END;

    INSERT INTO audit_log (
        actor,
        action,
        resource_type,
        resource_id,
        details,
        trace_id,
        client_ip,
        client_info
    ) VALUES (
        current_actor,
        TG_OP,
        TG_TABLE_NAME,
        CASE
            WHEN TG_OP = 'DELETE' THEN OLD.id
            ELSE NEW.id::TEXT
        END,
        CASE
            WHEN TG_OP = 'INSERT' THEN to_jsonb(NEW)
            WHEN TG_OP = 'UPDATE' THEN jsonb_build_object('previous', to_jsonb(OLD), 'new', to_jsonb(NEW))
            WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD)
        END,
        current_trace_id,
        current_client_ip,
        current_client_info
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Trigger: log_namespaces_change
-- Records all changes to namespace definitions in the audit log
CREATE TRIGGER log_namespaces_change
AFTER INSERT OR UPDATE OR DELETE ON namespaces
FOR EACH ROW EXECUTE FUNCTION log_change();

-- Trigger: log_relations_change
-- Records all changes to relation definitions in the audit log
CREATE TRIGGER log_relations_change
AFTER INSERT OR UPDATE OR DELETE ON relations
FOR EACH ROW EXECUTE FUNCTION log_change();

-- Trigger: log_relation_rules_change
-- Records all changes to relation rules in the audit log
CREATE TRIGGER log_relation_rules_change
AFTER INSERT OR UPDATE OR DELETE ON relation_rules
FOR EACH ROW EXECUTE FUNCTION log_change();

-- Trigger: log_relationship_tuples_change
-- Records all permission relationship changes in the audit log
CREATE TRIGGER log_relationship_tuples_change
AFTER INSERT OR UPDATE OR DELETE ON relationship_tuples
FOR EACH ROW EXECUTE FUNCTION log_change();

-- Trigger: log_zookies_change
-- Records all consistency token changes in the audit log
CREATE TRIGGER log_zookies_change
AFTER INSERT OR UPDATE OR DELETE ON zookies
FOR EACH ROW EXECUTE FUNCTION log_change();

-- Trigger: log_transaction_log_change
-- Records all transaction log changes in the audit log for meta-auditing
CREATE TRIGGER log_transaction_log_change
AFTER INSERT OR UPDATE OR DELETE ON transaction_log
FOR EACH ROW EXECUTE FUNCTION log_change();

-- Trigger: log_replication_status_change
-- Records all replication status changes for monitoring distributed system health
CREATE TRIGGER log_replication_status_change
AFTER INSERT OR UPDATE OR DELETE ON replication_status
FOR EACH ROW EXECUTE FUNCTION log_change();

-- Trigger: log_auth_decisions_change
-- Records all changes to authorization decision records for compliance tracking
CREATE TRIGGER log_auth_decisions_change
AFTER INSERT OR UPDATE OR DELETE ON auth_decisions
FOR EACH ROW EXECUTE FUNCTION log_change();

-- Trigger: log_permissions_cache_change
-- Records all changes to the permissions cache for debugging and auditing
CREATE TRIGGER log_permissions_cache_change
AFTER INSERT OR UPDATE OR DELETE ON permissions_cache
FOR EACH ROW EXECUTE FUNCTION log_change();
