pub mod ama_config;
pub mod deserializer;
pub mod logger_config;

use std::fs;

pub use ama_config::*;
pub use deserializer::*;
pub use logger_config::*;

use once_cell::sync::Lazy;
use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
pub struct Config {
    pub logger: LoggerConfig,
    pub ama: AmaConfig,
}

pub static CONFIG: Lazy<Config> = Lazy::new(|| {
    let content = fs::read_to_string("Config.toml").expect("Failed to read config.toml");
    toml::from_str(&content).expect("Failed to parse config.toml")
});