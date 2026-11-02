//! Failures with a stable code and exit status, shared by the CLI's text and JSON output.
//! Not-found and ambiguous failures list the candidates to choose from and never change anything.

use serde::Serialize;

use crate::config::Condition;
use crate::store::StoreError;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Code {
    InvalidArgument,
    WouldShadow,
    VerificationFailed,
    HistoryDisabled,
    HistoryUnreadable,
    ProfilesUnreadable,
    WriteFailed,
    ProfileNotFound,
    AmbiguousProfile,
    BrowserNotFound,
    AmbiguousBrowser,
    RuleNotFound,
    HistoryEntryNotFound,
    AmbiguousHistoryEntry,
    InheritingRules,
    AgentNotFound,
    ConfigUnreadable,
    ConfigInvalid,
    Conflict,
}

impl Code {
    /// 1 failed, 2 bad command line, 3 not found or ambiguous, 4 config unreadable or invalid,
    /// 5 conflict.
    pub fn exit_code(self) -> u8 {
        use Code::*;
        match self {
            InvalidArgument => 2,
            ProfileNotFound
            | AmbiguousProfile
            | BrowserNotFound
            | AmbiguousBrowser
            | RuleNotFound
            | HistoryEntryNotFound
            | AmbiguousHistoryEntry
            | InheritingRules
            | AgentNotFound => 3,
            ConfigUnreadable | ConfigInvalid => 4,
            Conflict => 5,
            WouldShadow | VerificationFailed | HistoryDisabled | HistoryUnreadable | ProfilesUnreadable
            | WriteFailed => 1,
        }
    }
}

/// One choice in a not-found or ambiguous answer. Only the fields that apply are present.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Candidate {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub index: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub condition: Option<Condition>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub browser: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub browser_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub browser_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
    /// A command that resolves the problem for this candidate.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub suggestion: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct OpError {
    pub code: Code,
    pub message: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub candidates: Vec<Candidate>,
}

impl OpError {
    pub fn new(code: Code, message: impl Into<String>) -> Self {
        OpError { code, message: message.into(), candidates: Vec::new() }
    }

    pub fn with(mut self, candidates: Vec<Candidate>) -> Self {
        self.candidates = candidates;
        self
    }

    pub fn invalid(message: impl Into<String>) -> Self {
        OpError::new(Code::InvalidArgument, message)
    }
}

impl From<StoreError> for OpError {
    fn from(error: StoreError) -> Self {
        let code = match error {
            StoreError::Unreadable(_) => Code::ConfigUnreadable,
            StoreError::Invalid { .. } => Code::ConfigInvalid,
            StoreError::Conflict => {
                return OpError::new(
                    Code::Conflict,
                    "The configuration changed while this command ran. Nothing was written. Run it again.",
                );
            }
            StoreError::WriteFailed(_) => Code::WriteFailed,
        };
        OpError::new(code, error.to_string())
    }
}

impl std::fmt::Display for OpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for OpError {}
