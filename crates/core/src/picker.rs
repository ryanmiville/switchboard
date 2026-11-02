//! The Quick Switch picker's settings in `config.json`.

use serde::{Deserialize, Deserializer, Serialize};

use crate::config::Destination;

/// A global shortcut as Rune writes it, such as `ctrl+alt+space` or `cmd+shift+l`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Shortcut(String);

impl Shortcut {
    pub fn new(text: impl Into<String>) -> Self {
        Shortcut(text.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for Shortcut {
    fn default() -> Self {
        Shortcut("ctrl+alt+space".into())
    }
}

impl<'de> Deserialize<'de> for Shortcut {
    /// A string, or the Swift app's `{keyCode, modifiers, key}` with Carbon modifier bits.
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Form {
            Text(String),
            Carbon {
                modifiers: u32,
                key: String,
                #[serde(rename = "keyCode")]
                _key_code: u32,
            },
        }
        Ok(match Form::deserialize(deserializer)? {
            Form::Text(text) => Shortcut(text),
            Form::Carbon { modifiers, key, .. } => {
                let mut parts: Vec<&str> = Vec::new();
                for (bit, name) in [(0x1000, "ctrl"), (0x0800, "alt"), (0x0200, "shift"), (0x0100, "cmd")] {
                    if modifiers & bit != 0 {
                        parts.push(name);
                    }
                }
                let key = match key.as_str() {
                    "←" => "left".to_owned(),
                    "→" => "right".to_owned(),
                    "↑" => "up".to_owned(),
                    "↓" => "down".to_owned(),
                    other => other.to_lowercase(),
                };
                Shortcut(format!("{}+{key}", parts.join("+")))
            }
        })
    }
}

/// A pinned destination with the label the picker shows.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Favorite {
    pub browser: String,
    pub profile: String,
    pub name: String,
}

impl Favorite {
    pub fn destination(&self) -> Destination {
        Destination { browser: self.browser.clone(), profile: self.profile.clone() }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PickerSettings {
    #[serde(default)]
    pub shortcut: Shortcut,
    #[serde(default)]
    pub favorites: Vec<Favorite>,
    /// The destinations the picker shows. Omitted shows everything; empty shows nothing.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub destinations: Option<Vec<Destination>>,
}

impl PickerSettings {
    pub fn includes(&self, destination: &Destination) -> bool {
        self.destinations.as_ref().is_none_or(|d| d.contains(destination))
    }
}
