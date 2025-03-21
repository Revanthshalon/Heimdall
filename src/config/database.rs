use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct DatabaseConfig {
    pub database_type: DatabaseType,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: Option<String>,
}

impl Default for DatabaseConfig {
    fn default() -> Self {
        Self {
            database_type: DatabaseType::default(),
            host: "localhost".into(),
            port: 5432,
            username: "development-user".into(),
            password: Some("development-password".into()),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Default)]
pub enum DatabaseType {
    Postgres,
    #[default]
    Sqllite,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ConnectionPoolConfig {
    pub min_connections: u32,
    pub max_connections: u32,
    pub max_lifetime_seconds: i64,
    pub connection_timeout_ms: i64,
    pub idle_timeout_ms: i64,
    pub test_before_aquire: bool,
    pub test_on_borrow: bool,
    pub max_connection_age_seconds: Option<i64>,
}

impl Default for ConnectionPoolConfig {
    fn default() -> Self {
        Self {
            min_connections: 30,
            max_connections: 100,
            max_lifetime_seconds: 150,
            connection_timeout_ms: 50,
            idle_timeout_ms: 300,
            test_before_aquire: false,
            test_on_borrow: false,
            max_connection_age_seconds: None,
        }
    }
}
