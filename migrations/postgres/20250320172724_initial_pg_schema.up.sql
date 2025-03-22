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

CREATE TABLE IF NOT EXISTS relationship_tuples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id VARCHAR(64) NOT NULL,
    object_id UUID NOT NULL, -- the object whose permissions are being set (e.g., document_id)
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

CREATE TABLE IF NOT EXISTS zookies (
    token VARCHAR(255) PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version BIGINT NOT NULL,
    transaction_id UUID NOT NULL,
    shard_id INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    expired_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP + INTERVAL '7 days'
);

CREATE INDEX IF NOT EXISTS idx_zookies_version ON zookies (version);
CREATE INDEX IF NOT EXISTS idx_zookies_expires ON zookies (expired_at);
