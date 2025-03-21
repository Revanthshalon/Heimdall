use crate::config::AppConfig;

#[derive(Debug)]
pub struct AppState {}

impl AppState {
    pub fn new(_app_config: AppConfig) -> Self {
        Self {}
    }
}
