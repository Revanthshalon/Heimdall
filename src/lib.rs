pub mod config;
mod dtos;
mod entities;
mod error;
mod handlers;
mod middlewares;
mod repositories;
mod routes;
mod services;
mod state;

use config::AppConfig;
use state::AppState;

pub async fn start_service(app_config: AppConfig) -> Result<(), String> {
    let _app_state = AppState::new(app_config);
    Ok(())
}
