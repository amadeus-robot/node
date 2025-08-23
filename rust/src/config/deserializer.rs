use serde::{Deserialize, Deserializer};

pub fn deserialize_truncate<'de, D>(deserializer: D) -> Result<Option<usize>, D::Error>
where
    D: Deserializer<'de>,
{
    let n = isize::deserialize(deserializer)?;
    if n < 0 {
        Ok(None)
    } else {
        Ok(Some(n as usize))
    }
}