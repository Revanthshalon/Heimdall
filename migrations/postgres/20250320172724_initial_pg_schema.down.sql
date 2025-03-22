-- =================================================================================================
-- Reversion Date: 2025-03-20 17:27:24.000000
-- Author: Revanth Shalon Raj
-- Description: Reversion of database schema for authorization service inspired by Zanzibar
-- Version: 1.0
-- =================================================================================================

-- Drop triggers
DROP TRIGGER IF EXISTS log_permissions_cache_change ON permissions_cache;
DROP TRIGGER IF EXISTS log_auth_decisions_change ON auth_decisions;
DROP TRIGGER IF EXISTS log_replication_status_change ON replication_status;
DROP TRIGGER IF EXISTS log_transaction_log_change ON transaction_log;
DROP TRIGGER IF EXISTS log_zookies_change ON zookies;
DROP TRIGGER IF EXISTS log_relationship_tuples_change ON relationship_tuples;
DROP TRIGGER IF EXISTS log_relation_rules_change ON relation_rules;
DROP TRIGGER IF EXISTS log_relations_change ON relations;
DROP TRIGGER IF EXISTS log_namespaces_change ON namespaces;

DROP TRIGGER IF EXISTS update_relation_rules_timestamp ON relation_rules;
DROP TRIGGER IF EXISTS update_relations_timestamp ON relations;
DROP TRIGGER IF EXISTS update_namespaces_timestamp ON namespaces;

-- Drop functions
DROP FUNCTION IF EXISTS log_change();
DROP FUNCTION IF EXISTS cleanup_zookies();
DROP FUNCTION IF EXISTS update_timestamp();

-- Drop performance optimization tables
DROP TABLE IF EXISTS permissions_cache;

-- Drop monitoring and auditing tables
DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS auth_decisions;

-- Drop consistency management tables
DROP TABLE IF EXISTS replication_status;
DROP TABLE IF EXISTS transaction_log;
DROP TABLE IF EXISTS zookies;

-- Drop core permission data tables
DROP TABLE IF EXISTS relationship_tuples;

-- Drop core configuration tables
DROP TABLE IF EXISTS relation_rules;
DROP TABLE IF EXISTS relations;
DROP TABLE IF EXISTS namespaces;

-- Drop types
DROP TYPE IF EXISTS operation_type;
DROP TYPE IF EXISTS rule_type;

-- Drop extensions
DROP EXTENSION IF EXISTS "ltree";
DROP EXTENSION IF EXISTS "pg_partman";
DROP EXTENSION IF EXISTS "btree_gist";
DROP EXTENSION IF EXISTS "uuid-ossp";
