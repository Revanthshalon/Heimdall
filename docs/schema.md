# Google Zanzibar Authorization Service Schema Documentation

This document outlines the database schema for implementing a Google Zanzibar-style authorization service. Google Zanzibar is a global authorization system that provides unified access control for services with flexible relationship-based permissions.

## Custom Types

### rule_type
Defines the different types of rules that can be used in relation definitions:
- `direct`: Direct assignments (e.g., user X is a member of group Y)
- `computed_userset`: Computed relationships (e.g., all editors are also viewers)
- `tuple_to_userset`: Relationships through another relation (e.g., members of parent folder can access child folders)
- `intersection`: Requires membership in multiple sets (e.g., must be both a team member AND approved reviewer)
- `exclusion`: Explicitly denies access (e.g., everyone except blocked users)

### change_type
Tracks the type of changes made to relationships:
- `CREATE`: New relationship created
- `UPDATE`: Existing relationship modified
- `DELETE`: Relationship removed

## Tables

### namespaces
Defines the top-level objects that can contain relationships.

**Purpose**: Organizes objects into logical collections (e.g., documents, folders, organizations).

**Example Values**:
```
| id                                   | name       | created_at                  | updated_at                  | deleted_at |
|--------------------------------------|------------|----------------------------|----------------------------|------------|
| a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d | documents  | 2023-01-15T10:30:00.000Z   | 2023-01-15T10:30:00.000Z   | NULL       |
| b2c3d4e5-f6a7-5b6c-9d0e-1f2a3b4c5d6e | folders    | 2023-01-15T10:35:00.000Z   | 2023-01-15T10:35:00.000Z   | NULL       |
| c3d4e5f6-a7b8-6c7d-0e1f-2a3b4c5d6e7f | users      | 2023-01-15T10:40:00.000Z   | 2023-01-15T10:40:00.000Z   | NULL       |
```

### relation_definitions
Defines the types of relationships that can exist between objects.

**Purpose**: Specifies possible relationships like "viewer", "editor", "owner", "member", etc.

**Example Values**:
```
| id                                   | namespace_id                          | relation_name |
|--------------------------------------|---------------------------------------|---------------|
| d4e5f6a7-b8c9-7d0e-1f2a-3b4c5d6e7f8g | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d  | viewer        |
| e5f6a7b8-c9d0-8e1f-2a3b-4c5d6e7f8g9h | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d  | editor        |
| f6a7b8c9-d0e1-9f2a-3b4c-5d6e7f8g9h0i | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d  | owner         |
| a7b8c9d0-e1f2-0a3b-4c5d-6e7f8g9h0i1j | b2c3d4e5-f6a7-5b6c-9d0e-1f2a3b4c5d6e  | member        |
```

### relation_rules
Defines how relations can be composed and inherited.

**Purpose**: Implements complex permission patterns like inheritance, computation, and combination of permissions.

**Example Values**:
```
| id                                   | relation_definition_id                | rule_type          | target_namespace_id                    | target_relation_id                     | source_relation_id                     |
|--------------------------------------|---------------------------------------|--------------------|-----------------------------------------|----------------------------------------|----------------------------------------|
| b8c9d0e1-f2a3-1b4c-5d6e-7f8g9h0i1j2k | e5f6a7b8-c9d0-8e1f-2a3b-4c5d6e7f8g9h  | computed_userset   | NULL                                    | d4e5f6a7-b8c9-7d0e-1f2a-3b4c5d6e7f8g   | NULL                                   |
| c9d0e1f2-a3b4-2c5d-6e7f-8g9h0i1j2k3l | a7b8c9d0-e1f2-0a3b-4c5d-6e7f8g9h0i1j  | tuple_to_userset   | b2c3d4e5-f6a7-5b6c-9d0e-1f2a3b4c5d6e   | a7b8c9d0-e1f2-0a3b-4c5d-6e7f8g9h0i1j   | NULL                                   |
```
*This example shows: 1) editors also have viewer permissions and 2) members of a folder can access its contents*

### relationships
Stores the actual relationships between objects and subjects.

**Purpose**: Records who has what permissions on which objects, forming the core of the authorization data.

**Example Values**:
```
| id                                   | namespace_id                          | object_id   | relation_id                            | subject_namespace_id                   | subject_id   | subject_relation_id                   | created_at                  | updated_at                  | deleted_at |
|--------------------------------------|---------------------------------------|-------------|----------------------------------------|----------------------------------------|--------------|---------------------------------------|----------------------------|----------------------------|------------|
| d0e1f2a3-b4c5-3d6e-7f8g-9h0i1j2k3l4m | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d  | doc123      | d4e5f6a7-b8c9-7d0e-1f2a-3b4c5d6e7f8g   | c3d4e5f6-a7b8-6c7d-0e1f-2a3b4c5d6e7f   | user456      | NULL                                  | 2023-01-20T14:25:00.000Z   | 2023-01-20T14:25:00.000Z   | NULL       |
| e1f2a3b4-c5d6-4e7f-8g9h-0i1j2k3l4m5n | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d  | doc123      | f6a7b8c9-d0e1-9f2a-3b4c-5d6e7f8g9h0i   | c3d4e5f6-a7b8-6c7d-0e1f-2a3b4c5d6e7f   | user789      | NULL                                  | 2023-01-20T14:30:00.000Z   | 2023-01-20T14:30:00.000Z   | NULL       |
| f2a3b4c5-d6e7-5f8g-9h0i-1j2k3l4m5n6o | b2c3d4e5-f6a7-5b6c-9d0e-1f2a3b4c5d6e  | folder456   | a7b8c9d0-e1f2-0a3b-4c5d-6e7f8g9h0i1j   | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d   | doc123       | NULL                                  | 2023-01-20T14:35:00.000Z   | 2023-01-20T14:35:00.000Z   | NULL       |
```
*This example shows: 1) user456 is a viewer of doc123, 2) user789 is an owner of doc123, and 3) doc123 is a member of folder456*

### relationship_changes
Tracks all changes made to relationships for auditing and synchronization.

**Purpose**: Provides an immutable log of all permission changes for auditing, versioning, and synchronizing distributed systems.

**Example Values**:
```
| change_id                            | relationship_id                       | change_type | namespace_id                          | object_id   | relation_id                            | subject_namespace_id                   | subject_id   | subject_relation_id | previous_data | new_data                             | change_timestamp             |
|--------------------------------------|---------------------------------------|-------------|---------------------------------------|-------------|----------------------------------------|----------------------------------------|--------------|---------------------|---------------|--------------------------------------|------------------------------|
| a3b4c5d6-e7f8-6g9h-0i1j-2k3l4m5n6o7p | d0e1f2a3-b4c5-3d6e-7f8g-9h0i1j2k3l4m  | CREATE      | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d  | doc123      | d4e5f6a7-b8c9-7d0e-1f2a-3b4c5d6e7f8g   | c3d4e5f6-a7b8-6c7d-0e1f-2a3b4c5d6e7f   | user456      | NULL                | NULL          | {"id":"d0e1f2a3-b4c5-...",...}      | 2023-01-20T14:25:00.000Z     |
| b4c5d6e7-f8g9-7h0i-1j2k-3l4m5n6o7p8q | d0e1f2a3-b4c5-3d6e-7f8g-9h0i1j2k3l4m  | DELETE      | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d  | doc123      | d4e5f6a7-b8c9-7d0e-1f2a-3b4c5d6e7f8g   | c3d4e5f6-a7b8-6c7d-0e1f-2a3b4c5d6e7f   | user456      | NULL                | {"id":"d0e1f2a3-b4c5-...",...} | NULL | 2023-02-15T09:45:00.000Z     |
```

### authorization_logs
Records every authorization check for auditing and analysis.

**Purpose**: Provides comprehensive logs of all permission checks, including successes and failures, for security auditing, debugging, and analytics.

**Example Values**:
```
| id                                   | timestamp                   | subject_id | namespace_id                          | object_id   | relation_id                            | granted | result_code               | context                                           |
|--------------------------------------|----------------------------|------------|---------------------------------------|-------------|----------------------------------------|---------|---------------------------|---------------------------------------------------|
| c5d6e7f8-g9h0-8i1j-2k3l-4m5n6o7p8q9r | 2023-02-10T15:45:30.000Z   | user456    | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d  | doc123      | d4e5f6a7-b8c9-7d0e-1f2a-3b4c5d6e7f8g   | true    | GRANTED                   | {"ip":"192.168.1.100","user_agent":"Mozilla/5.0"} |
| d6e7f8g9-h0i1-9j2k-3l4m-5n6o7p8q9r0s | 2023-02-10T15:50:45.000Z   | user123    | a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d  | doc123      | f6a7b8c9-d0e1-9f2a-3b4c-5d6e7f8g9h0i   | false   | DENIED_NO_RELATIONSHIP   | {"ip":"192.168.1.105","user_agent":"Chrome/98.0"} |
```

## Indices and Triggers

The schema includes various indices to optimize common query patterns and triggers to maintain data integrity:

- Indices on relationships to quickly look up objects and subjects
- Triggers to automatically update timestamps when records change
- Function to log all relationship changes for auditing purposes

This schema implements the core concepts of Google Zanzibar, providing a flexible and powerful authorization system that can handle complex permission models at scale.
