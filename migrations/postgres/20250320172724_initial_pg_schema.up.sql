-- =================================================================================================
-- Creation Date: 2025-03-20 17:27:24.000000
-- Author: Revanth Shalon Raj
-- Description: Database schema for authorization service inspired by Zanzibar
-- Version: 1.0
-- =================================================================================================

-- Extensions necesary for the project
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";     -- For generating UUIDs
CREATE EXTENSION IF NOT EXISTS "btree_gist";    -- For indexing jsonb fields
CREATE EXTENSION IF NOT EXISTS "pg_partman";    -- For partitioning tables
CREATE EXTENSION IF NOT EXISTS "ltree";         -- For storing hierarchical data

-- Define types for the database
-- `rule_type` for defining the different rules types that the authorization service supports
CREATE TYPE rule_type AS ENUM (
    'direct',                                   -- Direct assignment  (user X has permission Y on object Z)
    'union',                                    -- Combines multiple usersets with OR logic
    'intersection',                             -- Combines multiple userset with AND logic
    'exclusion',                                -- Removes a subset from userset (Set 1 - Set 2)
    'tuple-to-userset'                          -- References another object's relation (object#relation)
);

-- `operation_type` for defining log operation types
CREATE TYPE operation_type AS ENUM (
    'create',                                   -- Create operation
    'update',                                   -- Update operation
    'delete'                                    -- Delete operation
);

-- =================================================================================================
-- Core Configuration Tables
-- =================================================================================================

-- Namespaces define object types in the system
CREATE TABLE IF NOT EXISTS namespaces (
    id VARCHAR(64) PRIMARY KEY,             -- e.g, 'document', 'folder'
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS relations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id VARCHAR(64) NOT NULL REFERENCES namespaces(id) ON DELETE RESTRICT,
    name VARCHAR(64) NOT NULL,            -- e.g, 'viewer', 'editor'
    description TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    deleted_at TIMESTAMPTZ NULL,
    UNIQUE (namespace_id, name)            -- relations are scoped by namespace and should be unique to each namespace
);

CREATE TABLE IF NOT EXISTS relation_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    namespace_id VARCHAR(64) NOT NULL REFERENCES namespaces(id) ON DELETE RESTRICT,
    relation_name VARCHAR(64) NOT NULL,
    rule_type rule_type NOT NULL,

    -- For `tuple-to-userset` rule_type
    ttu_object_namespace VARCHAR(64) NULL,
    ttu_relation VARCHAR(64) NULL,

    -- For `union`, `intersection`, `exclusion` rule_types
    child_relations JSONB NULL, -- Array of relation names

    -- Rule expression in zanibar syntax
    expression TEXT NULL, -- e.g, "viewer + editor - blocked"

    -- Rule precedence (lower numbers are evaluated first)
    priority INT NOT NULL DEFAULT 100,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ NULL,

    FOREIGN KEY (namespace_id, relation_name) REFERENCES relations(namespace_id, name) ON DELETE RESTRICT,  -- relation_name should be a valid relation in the namespace
    UNIQUE (namespace_id, relation_name, priority) -- Each relation can have only one rule with a given priority
);
