//! The menu-bar icon: an `NSStatusItem` with a menu, built through objc2 because Rune's tray
//! doesn't cover macOS. The menu's target forwards each choice to the app's callback.

#![allow(unsafe_code, reason = "AppKit calls through objc2; each block says why it is sound")]

use objc2::rc::Retained;
use objc2::runtime::{AnyObject, NSObjectProtocol, Sel};
use objc2::{AnyThread, DefinedClass, MainThreadOnly, define_class, msg_send, sel};
use objc2_app_kit::{NSImage, NSMenu, NSMenuItem, NSStatusBar, NSStatusItem};
use objc2_foundation::{MainThreadMarker, NSData, NSObject, NSSize, NSString};
use switchboard_core::identity;
use switchboard_core::platform::{MenuAction, MenuBar};

/// A template image, so it follows the menu bar's light or dark appearance.
const ICON_PDF: &[u8] = include_bytes!("../../../assets/MenuBarIcon.pdf");
const ICON_POINTS: f64 = 18.0;

type Callback = Box<dyn Fn(MenuAction) + Send + Sync>;

pub struct TargetIvars {
    on_action: Callback,
}

define_class!(
    // SAFETY: NSObject has no subclassing requirements, and the class adds no Drop of its own.
    #[unsafe(super = NSObject)]
    #[thread_kind = MainThreadOnly]
    #[ivars = TargetIvars]
    struct Target;

    // SAFETY: NSObjectProtocol has no requirements beyond NSObject's.
    unsafe impl NSObjectProtocol for Target {}

    impl Target {
        // SAFETY: the selector takes one object argument and returns nothing, as declared.
        #[unsafe(method(quickSwitch:))]
        fn quick_switch(&self, _sender: &AnyObject) {
            (self.ivars().on_action)(MenuAction::QuickSwitch);
        }

        // SAFETY: as above.
        #[unsafe(method(openSettings:))]
        fn open_settings(&self, _sender: &AnyObject) {
            (self.ivars().on_action)(MenuAction::OpenSettings);
        }

        // SAFETY: as above.
        #[unsafe(method(quit:))]
        fn quit(&self, _sender: &AnyObject) {
            (self.ivars().on_action)(MenuAction::Quit);
        }
    }
);

impl Target {
    fn new(on_action: Callback, mtm: MainThreadMarker) -> Retained<Self> {
        let this = Self::alloc(mtm).set_ivars(TargetIvars { on_action });
        // SAFETY: NSObject's designated initialiser, called once on a fresh allocation.
        unsafe { msg_send![super(this), init] }
    }
}

/// The icon and its menu. Dropping it removes the icon from the menu bar.
pub struct MacMenuBar {
    item: Retained<NSStatusItem>,
    _menu: Retained<NSMenu>,
    _target: Retained<Target>,
}

impl Drop for MacMenuBar {
    fn drop(&mut self) {
        NSStatusBar::systemStatusBar().removeStatusItem(&self.item);
    }
}

impl MenuBar for MacMenuBar {
    fn install(on_action: Callback) -> Result<Self, String> {
        let mtm = MainThreadMarker::new().ok_or("the menu-bar icon must be installed on the main thread")?;
        let target = Target::new(on_action, mtm);
        let menu = NSMenu::initWithTitle(NSMenu::alloc(mtm), &NSString::from_str(identity::APP_NAME));
        add(&menu, &target, "Open Current Page…", sel!(quickSwitch:), "", mtm);
        add(&menu, &target, "Settings…", sel!(openSettings:), ",", mtm);
        menu.addItem(&NSMenuItem::separatorItem(mtm));
        add(&menu, &target, &format!("Quit {}", identity::APP_NAME), sel!(quit:), "q", mtm);

        // NSVariableStatusItemLength: as wide as the icon.
        let item = NSStatusBar::systemStatusBar().statusItemWithLength(-1.0);
        let button = item.button(mtm).ok_or("the menu-bar icon has no button")?;
        let image = icon()?;
        button.setImage(Some(&image));
        button.setToolTip(Some(&NSString::from_str(identity::APP_NAME)));
        item.setMenu(Some(&menu));
        Ok(MacMenuBar { item, _menu: menu, _target: target })
    }
}

fn icon() -> Result<Retained<NSImage>, String> {
    let data = NSData::with_bytes(ICON_PDF);
    let image =
        NSImage::initWithData(NSImage::alloc(), &data).ok_or("the menu-bar icon couldn't be decoded")?;
    image.setSize(NSSize::new(ICON_POINTS, ICON_POINTS));
    image.setTemplate(true);
    image.setAccessibilityDescription(Some(&NSString::from_str(identity::APP_NAME)));
    Ok(image)
}

fn add(menu: &NSMenu, target: &Target, title: &str, action: Sel, key: &str, mtm: MainThreadMarker) {
    // SAFETY: a fresh item with a selector the target implements and a plain key equivalent.
    let item = unsafe {
        NSMenuItem::initWithTitle_action_keyEquivalent(
            NSMenuItem::alloc(mtm),
            &NSString::from_str(title),
            Some(action),
            &NSString::from_str(key),
        )
    };
    // SAFETY: the target lives as long as the menu bar, which owns both it and the menu.
    unsafe { item.setTarget(Some(target)) };
    menu.addItem(&item);
}

/// Activates the app so a window it opens comes in front of the app that was active.
pub fn bring_to_front() {
    if let Some(mtm) = MainThreadMarker::new() {
        objc2_app_kit::NSApplication::sharedApplication(mtm).activate();
    }
}
