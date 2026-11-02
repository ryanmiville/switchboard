//! The tray icon, through Rune's tray (StatusNotifierItem over D-Bus). It appears where a tray
//! host runs (KDE, waybar, most bars; GNOME needs an extension).

use rune::{Tray, TrayEvent, TrayIcon, TrayItem, TraySpec};
use switchboard_core::identity;
use switchboard_core::platform::{MenuAction, MenuBar};

const ICON: &[u8] = include_bytes!("../../../assets/AppIcon/icon_32x32.png");

pub struct LinuxTray {
    _tray: Tray,
}

impl MenuBar for LinuxTray {
    fn install(on_action: Box<dyn Fn(MenuAction) + Send + Sync>) -> Result<Self, String> {
        let menu = vec![
            TrayItem::action("quick-switch", "Open Current Page…"),
            TrayItem::action("settings", "Settings…"),
            TrayItem::Separator,
            TrayItem::action("quit", format!("Quit {}", identity::APP_NAME)),
        ];
        let spec = TraySpec::new(identity::CLI_NAME, identity::APP_NAME, icon()?)
            .tooltip(identity::APP_NAME)
            .menu(menu);
        let tray = Tray::new(spec, move |event| match event {
            TrayEvent::Activate { .. } => on_action(MenuAction::OpenSettings),
            TrayEvent::Menu(id) if id == "quick-switch" => on_action(MenuAction::QuickSwitch),
            TrayEvent::Menu(id) if id == "settings" => on_action(MenuAction::OpenSettings),
            TrayEvent::Menu(id) if id == "quit" => on_action(MenuAction::Quit),
            _ => {}
        })
        .map_err(|e| e.to_string())?;
        Ok(LinuxTray { _tray: tray })
    }
}

fn icon() -> Result<TrayIcon, String> {
    let mut reader = png::Decoder::new(std::io::Cursor::new(ICON)).read_info().map_err(|e| e.to_string())?;
    let mut pixels = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut pixels).map_err(|e| e.to_string())?;
    pixels.truncate(info.buffer_size());
    if info.color_type != png::ColorType::Rgba {
        return Err("the tray icon must be an RGBA PNG".into());
    }
    Ok(TrayIcon::rgba(info.width, info.height, pixels))
}
