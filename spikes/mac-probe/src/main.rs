//! Records what macOS delivers to a windowless, accessory Rune app: launch, links, reopen.
//! Every event is appended to ~/Library/Logs/switchboard-probe.log; run.sh reads it.

use std::io::Write;

use rune::{AppSpec, Cx, El, col};

#[derive(Default)]
struct Probe;

fn view(_: &Probe, _: &mut Cx<Probe>) -> El {
    col()
}

fn log(line: &str) {
    let Some(home) = std::env::var_os("HOME") else { return };
    let path = std::path::Path::new(&home).join("Library/Logs/switchboard-probe.log");
    if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{} {line}", std::process::id());
    }
}

fn main() {
    log(&format!("launch args={:?}", std::env::args().skip(1).collect::<Vec<_>>()));
    rune::App::new(AppSpec::new("Switchboard Probe", (320.0, 200.0), Probe::default, view))
        .windowless()
        .accessory()
        .on_open_url(|_, url, _| log(&format!("url {url}")))
        .on_reopen(|_, visible, _| {
            log(&format!("reopen visible={visible}"));
            true
        })
        .run();
}
