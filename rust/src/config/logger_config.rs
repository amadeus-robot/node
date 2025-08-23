use once_cell::sync::Lazy;
use serde::Deserialize;

use crate::*;

#[derive(Debug, Deserialize, Clone)]
pub struct LoggerConfig {
    #[serde(deserialize_with = "deserialize_truncate")]
    pub truncate: Option<usize>, // None = infinity
}

// pub AMACONFIG : AmaConfig= CONFIG.
pub static LOGGERCONFIG: Lazy<LoggerConfig> = Lazy::new(|| CONFIG.logger.clone());