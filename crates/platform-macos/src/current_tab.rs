//! The focused browser's current tab, read with an Apple Event like AppleScript's
//! `URL of active tab of window 1`. The first read asks the person to allow Automation for that
//! browser. Ported from the Swift app's `CurrentTabReader`.

use objc2::rc::Retained;
use objc2_app_kit::{NSApplicationActivationOptions, NSRunningApplication, NSWorkspace};
use objc2_foundation::{NSAppleEventDescriptor, NSAppleEventSendOptions, NSString, NSURL};
use switchboard_core::platform::{BrowserInfo, CurrentTab, Frontmost, TabError};

use crate::browsers::bundle;

const fn code(s: &[u8; 4]) -> u32 {
    u32::from_be_bytes(*s)
}

const CORE_SUITE: u32 = code(b"core");
const GET_DATA: u32 = code(b"getd");
const DIRECT_OBJECT: u32 = code(b"----");
const ERROR_NUMBER: u32 = code(b"errn");
const DESIRED_CLASS: u32 = code(b"want");
const KEY_FORM: u32 = code(b"form");
const KEY_DATA: u32 = code(b"seld");
const CONTAINER: u32 = code(b"from");
const WINDOW: u32 = code(b"cwin");
/// Arc's window class.
const ARC_WINDOW: u32 = code(b"WiND");
const PROPERTY: u32 = code(b"prop");
const ABSOLUTE_POSITION: u32 = code(b"indx");
const ACTIVE_TAB: u32 = code(b"acTa");
const URL: u32 = code(b"URL ");
const OBJECT_SPECIFIER: u32 = code(b"obj ");
const AUTO_GENERATE_RETURN_ID: i16 = -1;
const ANY_TRANSACTION_ID: i32 = 0;
/// Seconds to wait for the browser, which may be showing the permission prompt.
const TIMEOUT: f64 = 3.0;

pub struct MacCurrentTab;

impl CurrentTab for MacCurrentTab {
    fn frontmost(&self) -> Option<Frontmost> {
        let app = NSWorkspace::sharedWorkspace().frontmostApplication()?;
        Some(Frontmost { id: app.bundleIdentifier()?.to_string(), pid: app.processIdentifier() })
    }

    fn read(&self, app: &Frontmost) -> Result<String, TabError> {
        if app.pid <= 0 || bundle(&app.id).is_none() {
            return Err(TabError::UnsupportedBrowser);
        }
        objc2::rc::autoreleasepool(|_| {
            let event = read_event(app);
            let options = NSAppleEventSendOptions::WaitForReply | NSAppleEventSendOptions::CanInteract;
            let reply =
                event.sendEventWithOptions_timeout_error(options, TIMEOUT).map_err(|e| failure(e.code()))?;
            if let Some(number) = reply.paramDescriptorForKeyword(ERROR_NUMBER) {
                let code = number.int32Value();
                if code != 0 {
                    return Err(failure(code as isize));
                }
            }
            let link = reply
                .paramDescriptorForKeyword(DIRECT_OBJECT)
                .and_then(|d| d.stringValue())
                .map(|s| s.to_string());
            let link = link.filter(|l| !l.is_empty()).ok_or(TabError::NoTab)?;
            if !switchboard_core::url::is_web(&link) {
                return Err(TabError::NotWeb);
            }
            Ok(link)
        })
    }

    fn activate(&self, browser: &BrowserInfo) {
        let apps =
            NSRunningApplication::runningApplicationsWithBundleIdentifier(&NSString::from_str(&browser.id));
        if let Some(app) = apps.firstObject() {
            app.activateWithOptions(NSApplicationActivationOptions::empty());
        }
    }

    fn open_automation_settings(&self) {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation";
        if let Some(url) = NSURL::URLWithString(&NSString::from_str(link)) {
            NSWorkspace::sharedWorkspace().openURL(&url);
        }
    }
}

fn failure(code: isize) -> TabError {
    match code {
        -1743 | -1744 => TabError::AutomationDenied,
        -1728 | -1719 => TabError::NoTab,
        _ => TabError::Unreadable,
    }
}

/// `get URL of active tab of window 1`, addressed to the process rather than the bundle id:
/// automation copies of a browser can share its bundle id.
fn read_event(app: &Frontmost) -> Retained<NSAppleEventDescriptor> {
    let arc = matches!(app.id.as_str(), "company.thebrowser.Browser" | "com.keksbay.Arc");
    // Windows are ordered front to back. An integer index, because Chrome rejects an absolute
    // ordinal enum with errAECoercionFail.
    let window = object(
        if arc { ARC_WINDOW } else { WINDOW },
        ABSOLUTE_POSITION,
        &NSAppleEventDescriptor::descriptorWithInt32(1),
        &NSAppleEventDescriptor::nullDescriptor(),
    );
    let tab =
        object(PROPERTY, PROPERTY, &NSAppleEventDescriptor::descriptorWithTypeCode(ACTIVE_TAB), &window);
    let url = object(PROPERTY, PROPERTY, &NSAppleEventDescriptor::descriptorWithTypeCode(URL), &tab);
    let target = NSAppleEventDescriptor::descriptorWithProcessIdentifier(app.pid);
    let event =
        NSAppleEventDescriptor::appleEventWithEventClass_eventID_targetDescriptor_returnID_transactionID(
            CORE_SUITE,
            GET_DATA,
            Some(&target),
            AUTO_GENERATE_RETURN_ID,
            ANY_TRANSACTION_ID,
        );
    event.setParamDescriptor_forKeyword(&url, DIRECT_OBJECT);
    event
}

/// An object specifier record: what to get (`want`), how it's addressed (`form`, `seld`), and
/// what it's inside (`from`).
fn object(
    class: u32,
    form: u32,
    key: &NSAppleEventDescriptor,
    container: &NSAppleEventDescriptor,
) -> Retained<NSAppleEventDescriptor> {
    let record = NSAppleEventDescriptor::recordDescriptor();
    record.setDescriptor_forKeyword(&NSAppleEventDescriptor::descriptorWithTypeCode(class), DESIRED_CLASS);
    record.setDescriptor_forKeyword(&NSAppleEventDescriptor::descriptorWithEnumCode(form), KEY_FORM);
    record.setDescriptor_forKeyword(key, KEY_DATA);
    record.setDescriptor_forKeyword(container, CONTAINER);
    record.coerceToDescriptorType(OBJECT_SPECIFIER).unwrap_or(record)
}
