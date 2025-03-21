use database::DatabaseConfig;
use serde::{Deserialize, Serialize};
use server::ServerConfig;

mod database;
mod server;

#[derive(Debug, Serialize, Deserialize)]
pub struct AppConfig {
    pub database_config: DatabaseConfig,
    pub server_config: ServerConfig,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            database_config: DatabaseConfig::default(),
            server_config: ServerConfig::default(),
        }
    }
}
