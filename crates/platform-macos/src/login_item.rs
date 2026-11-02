//! Launch at login through `SMAppService.mainApp`, which registers the app bundle the process runs
//! from. It needs the packaged app: run from `cargo run`, macOS reports it as not found.

#![allow(unsafe_code, reason = "ServiceManagement calls through objc2; each block says why it is sound")]

use objc2_service_management::{SMAppService, SMAppServiceStatus};
use switchboard_core::platform::{LoginItem, LoginStatus};

pub struct MacLoginItem;

impl MacLoginItem {
    fn read() -> Result<LoginStatus, String> {
        // SAFETY: mainAppService and status take no arguments and retain nothing of the caller's.
        let status = unsafe { SMAppService::mainAppService().status() };
        match status {
            SMAppServiceStatus::NotRegistered | SMAppServiceStatus::NotFound => Ok(LoginStatus::Disabled),
            SMAppServiceStatus::Enabled => Ok(LoginStatus::Enabled),
            SMAppServiceStatus::RequiresApproval => Ok(LoginStatus::RequiresApproval),
            _ => Err("macOS reported an unknown login item status.".into()),
        }
    }
}

impl LoginItem for MacLoginItem {
    fn status(&self) -> Result<LoginStatus, String> {
        objc2::rc::autoreleasepool(|_| Self::read())
    }

    fn set_enabled(&self, enabled: bool) -> Result<LoginStatus, String> {
        objc2::rc::autoreleasepool(|_| {
            let current = Self::read()?;
            // SAFETY: the service object is owned here; errors come back as owned NSError values.
            let service = unsafe { SMAppService::mainAppService() };
            // A change the person made in System Settings is respected, never re-registered.
            if enabled && current == LoginStatus::Disabled {
                // SAFETY: a synchronous call on the owned service; the error is returned owned.
                unsafe { service.registerAndReturnError() }.map_err(|e| e.to_string())?;
            } else if !enabled && current != LoginStatus::Disabled {
                // SAFETY: as above.
                unsafe { service.unregisterAndReturnError() }.map_err(|e| e.to_string())?;
            }
            Self::read()
        })
    }

    fn open_settings(&self) {
        // SAFETY: asks macOS to open its Login Items settings; takes no arguments.
        unsafe { SMAppService::openSystemSettingsLoginItems() };
    }
}
