use switchboard_core::OpError;

use super::Output;
use crate::session::Session;

/// The whole configuration as the app reads it, with its path and revision.
pub fn run(session: &Session<'_>) -> Result<Output, OpError> {
    let snapshot = session.load()?;
    let path = session.config_path.to_string_lossy().into_owned();
    let report = serde_json::json!({
        "path": path,
        "exists": snapshot.exists,
        "revision": snapshot.revision,
        "config": snapshot.config,
    });
    let text = format!(
        "{path}{}\n{}",
        if snapshot.exists { "" } else { " (not created yet; these are the defaults)" },
        String::from_utf8_lossy(&snapshot.config.encode())
    );
    Ok(Output::new(&report, text))
}
