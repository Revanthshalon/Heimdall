# Heimdall Database Schema Documentation

## Overview

This document describes the database schema for Heimdall, a comprehensive authorization management system that implements relationship-based access control (ReBAC) following the Zanzibar model. This schema provides the foundation for fine-grained authorization decisions based on relationships between entities.

## Zanzibar-style Authorization

Zanzibar is Google's consistent, global authorization system that supports the principle of "relationships as permissions." It allows complex access control scenarios through flexible relationship declarations between objects and subjects, supporting:

- Direct relationships (user-to-resource)
- Group-based access patterns
- Nested group memberships
- Computed relationships
- Intersection and exclusion rules

## Schema Components

### Core Tables

#### 1. Namespaces (`namespaces`)
Organizes entities into logical domains for isolation and organization.
- `id`: Unique identifier
- `name`: Human-readable namespace name
- Timestamps for lifecycle management

#### 2. Relation Definitions (`relation_definitions`)
Defines the possible relationships between entities within a namespace.
- `id`: Unique identifier
- `namespace_id`: The namespace this relation belongs to
- `relation_name`: The name of the relation (e.g., "owner", "editor", "viewer")

#### 3. Relation Rules (`relation_rules`)
Defines how relations are composed and computed, supporting complex relationship patterns.
- `id`: Unique identifier
- `relation_definition_id`: The relation this rule applies to
- `rule_type`: Type of rule (direct, computed_userset, tuple_to_userset, intersection, exclusion)
- Various relation references for composition rules

#### 4. Relationships (`relationships`)
Stores actual relationship tuples between objects and subjects.
- `namespace_id` & `object_id`: Identify the resource
- `relation_id`: The type of relationship
- `subject_namespace_id` & `subject_id`: Identify the subject
- `subject_relation_id`: For userset-to-userset relationships

### Audit and Logging

#### 1. Change Log (`change_log`)
Records all system changes for audit purposes.
- `version`: Sequential change identifier
- `change_type`, `entity_type`, `operation`: Classification data
- `details`: JSON representation of changes
- User attribution and timestamps

#### 2. Authorization Logs (`authorization_logs`)
Records access decisions for auditing and analysis.
- Decision details including subject, object, relation
- Whether access was granted
- Contextual information

## Using This Schema for Zanzibar-style Authorization

### Basic Authorization Flow

1. **Setup Relations**
   - Create namespaces for your application domains
   - Define relation types within those namespaces
   - Establish relation rules for complex permission structures

2. **Store Relationships**
   - Add relationship tuples to establish who has what access
   - Example: (document:123, viewer, user:bob)

3. **Check Permissions**
   - Query the relationships table with appropriate filters
   - For complex permissions, traverse relation rules
   - Record authorization decisions in logs

### Key Usage Patterns

#### Direct Assignment
```sql
-- Grant "admin" access to user "alice" for organization "org1"
INSERT INTO relationships (namespace_id, object_id, relation_id, subject_namespace_id, subject_id)
VALUES
  ((SELECT id FROM namespaces WHERE name = 'organization'),
   'org1',
   (SELECT id FROM relation_definitions WHERE relation_name = 'admin'),
   (SELECT id FROM namespaces WHERE name = 'user'),
   'alice');
```

#### Group-based Access
```sql
-- First, add user to group
INSERT INTO relationships (namespace_id, object_id, relation_id, subject_namespace_id, subject_id)
VALUES
  ((SELECT id FROM namespaces WHERE name = 'group'),
   'engineering',
   (SELECT id FROM relation_definitions WHERE relation_name = 'member'),
   (SELECT id FROM namespaces WHERE name = 'user'),
   'bob');

-- Then, grant access to the group
INSERT INTO relationships (namespace_id, object_id, relation_id, subject_namespace_id, subject_id, subject_relation_id)
VALUES
  ((SELECT id FROM namespaces WHERE name = 'document'),
   'doc123',
   (SELECT id FROM relation_definitions WHERE relation_name = 'editor'),
   (SELECT id FROM namespaces WHERE name = 'group'),
   'engineering',
   (SELECT id FROM relation_definitions WHERE relation_name = 'member'));
```

#### Permission Checking
```sql
-- Check if user "alice" has "viewer" access to "doc123"
SELECT EXISTS (
  SELECT 1 FROM relationships
  WHERE namespace_id = (SELECT id FROM namespaces WHERE name = 'document')
  AND object_id = 'doc123'
  AND relation_id = (SELECT id FROM relation_definitions WHERE relation_name = 'viewer')
  AND subject_namespace_id = (SELECT id FROM namespaces WHERE name = 'user')
  AND subject_id = 'alice'
  AND deleted_at IS NULL
);
```

### Advanced Usage

#### Hierarchical Permissions
You can define relation rules where one permission implies another:

```sql
-- Define a rule that "admin" implies "editor"
INSERT INTO relation_rules (relation_definition_id, rule_type, target_relation_id)
VALUES (
  (SELECT id FROM relation_definitions WHERE relation_name = 'editor'), -- editor relation
  'computed_userset', -- rule type
  (SELECT id FROM relation_definitions WHERE relation_name = 'admin') -- source relation
);
```

#### Access Control Lists
You can model traditional ACLs by using an intermediary object:

```sql
-- Create an ACL for document "doc123"
INSERT INTO relationships (namespace_id, object_id, relation_id, subject_namespace_id, subject_id)
VALUES
  ((SELECT id FROM namespaces WHERE name = 'document'),
   'doc123',
   (SELECT id FROM relation_definitions WHERE relation_name = 'acl'),
   (SELECT id FROM namespaces WHERE name = 'acl'),
   'acl_for_doc123');

-- Add users to the ACL
INSERT INTO relationships (namespace_id, object_id, relation_id, subject_namespace_id, subject_id)
VALUES
  ((SELECT id FROM namespaces WHERE name = 'acl'),
   'acl_for_doc123',
   (SELECT id FROM relation_definitions WHERE relation_name = 'viewer'),
   (SELECT id FROM namespaces WHERE name = 'user'),
   'charlie');
```

## Schema Benefits

1. **Flexibility**: Models any permission structure or access control pattern
2. **Performance**: Optimized with appropriate indexes for permission checks
3. **Auditability**: Comprehensive audit trail of all changes and access decisions
4. **Scalability**: Designed for high-throughput authorization systems
5. **Consistency**: Tracks relationships with clear boundaries and rules

## Implementation Considerations

- Utilize database transactions to ensure consistency when updating related records
- Consider caching frequent permission checks for performance
- Implement appropriate application-level logic for more complex permission checks
- Use the auditing features to meet compliance requirements
- Consider replication for high availability and performance
