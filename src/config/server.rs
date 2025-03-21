use std::net::{IpAddr, Ipv4Addr};

use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct ServerConfig {
    pub ip: IpAddr,
    pub port: u16,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            ip: IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)),
            port: 3000,
        }
    }
}
