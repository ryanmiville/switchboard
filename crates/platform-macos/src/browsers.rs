//! Chromium browsers as macOS app bundles. A browser is identified by its bundle identifier; its
//! profiles live in a folder under `~/Library/Application Support` that each browser names its own
//! way, so the table below lists them rather than deriving them.

use std::path::{Component, Path, PathBuf};

use switchboard_core::Home;
use switchboard_core::platform::{self, BrowserInfo, Browsers, Family};

/// Bundle identifiers, the family each belongs to, and its user-data folder under
/// `~/Library/Application Support`.
pub const BUNDLES: &[(&str, Family, &str)] = &[
    ("com.google.Chrome", Family::Chrome, "Google/Chrome"),
    ("com.google.Chrome.beta", Family::ChromeBeta, "Google/Chrome Beta"),
    ("com.google.Chrome.dev", Family::ChromeDev, "Google/Chrome Dev"),
    ("com.google.Chrome.canary", Family::ChromeCanary, "Google/Chrome Canary"),
    ("org.chromium.Chromium", Family::Chromium, "Chromium"),
    ("com.brave.Browser", Family::Brave, "BraveSoftware/Brave-Browser"),
    ("com.microsoft.edgemac", Family::Edge, "Microsoft Edge"),
    ("com.microsoft.edgemac.Beta", Family::EdgeBeta, "Microsoft Edge Beta"),
    ("com.microsoft.edgemac.Dev", Family::EdgeDev, "Microsoft Edge Dev"),
    ("com.microsoft.edgemac.Canary", Family::EdgeCanary, "Microsoft Edge Canary"),
    ("com.operasoftware.Opera", Family::Opera, "com.operasoftware.Opera"),
    ("com.operasoftware.OperaNext", Family::OperaBeta, "com.operasoftware.OperaNext"),
    ("com.operasoftware.OperaDeveloper", Family::OperaDeveloper, "com.operasoftware.OperaDeveloper"),
    ("com.opera.Opera", Family::Opera, "com.operasoftware.Opera"),
    ("com.opera.OperaBeta", Family::OperaBeta, "com.operasoftware.OperaNext"),
    ("com.opera.OperaDeveloper", Family::OperaDeveloper, "com.operasoftware.OperaDeveloper"),
    ("com.vivaldi.Vivaldi", Family::Vivaldi, "Vivaldi"),
    ("company.thebrowser.Browser", Family::Arc, "Arc/User Data"),
    ("com.keksbay.Arc", Family::Arc, "Arc/User Data"),
    ("net.imput.helium", Family::Helium, "net.imput.helium"),
];

pub fn bundle(id: &str) -> Option<&'static (&'static str, Family, &'static str)> {
    BUNDLES.iter().find(|(b, _, _)| *b == id)
}

#[derive(Clone, Debug)]
pub struct MacBrowsers {
    home: Home,
    app_dirs: Vec<PathBuf>,
}

impl MacBrowsers {
    /// Browsers found in `app_dirs` (the binaries pass `/Applications` and `~/Applications`).
    pub fn new(home: Home, app_dirs: Vec<PathBuf>) -> Self {
        MacBrowsers { home, app_dirs }
    }
}

impl Browsers for MacBrowsers {
    fn installed(&self) -> Vec<BrowserInfo> {
        let mut found: Vec<BrowserInfo> = Vec::new();
        for dir in &self.app_dirs {
            let Ok(entries) = std::fs::read_dir(dir) else { continue };
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().is_some_and(|e| e == "app")
                    && let Some(info) = self.at(&path.to_string_lossy())
                    && !found.iter().any(|b| b.locator == info.locator)
                {
                    found.push(info);
                }
            }
        }
        platform::sort(&mut found);
        found
    }

    fn at(&self, locator: &str) -> Option<BrowserInfo> {
        let path = standardized(Path::new(locator));
        let plist = plist::Value::from_file(path.join("Contents/Info.plist")).ok()?;
        let dict = plist.as_dictionary()?;
        let text = |key: &str| dict.get(key).and_then(|v| v.as_string()).map(str::to_owned);
        let id = text("CFBundleIdentifier")?;
        let (_, family, data) = bundle(&id)?;
        let name = platform::file_stem(&path.to_string_lossy());
        let mut aliases: Vec<String> = ["CFBundleDisplayName", "CFBundleName"]
            .iter()
            .filter_map(|k| text(k))
            .filter(|a| *a != name)
            .collect();
        aliases.dedup();
        Some(BrowserInfo {
            locator: path.to_string_lossy().into_owned(),
            name,
            id,
            family: *family,
            aliases,
            executable: path.join("Contents/MacOS").join(text("CFBundleExecutable")?),
            args: Vec::new(),
            user_data: self.home.join("Library/Application Support").join(data),
        })
    }
}

/// Removes `.`, `..` and trailing slashes without touching the disk.
fn standardized(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}
