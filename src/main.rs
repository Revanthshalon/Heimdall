use heimdall::config::AppConfig;

#[tokio::main]
async fn main() {
    // NOTE: Initializing Application Configuration right at the start, so that I can use the
    // configuration values for setting up tracing if needed.
    let app_config = AppConfig::default();
    // TODO: Initialize Tracing
    if let Err(_e) = heimdall::start_service(app_config).await {
        // TODO: handle error for better context
        todo!()
    }
}
