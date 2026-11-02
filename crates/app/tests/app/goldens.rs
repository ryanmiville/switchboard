//! Golden images of every scene, light and dark, rendered by the app binary's own `--snap` (the
//! renderer that ships). They run on Linux only, where CI renders on Mesa's software Vulkan;
//! pixels differ by GPU and OS. `UPDATE_GOLDENS=1` rewrites them; look at every changed image
//! before committing it. A miss writes the actual render to `target/golden-actual/`, which CI
//! uploads.

use std::path::{Path, PathBuf};

use switchboard_app::scenes::SCENES;

const BIN: &str = env!("CARGO_BIN_EXE_switchboard-rs-app");

fn dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/golden")
}

fn actual_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../target/golden-actual")
}

#[expect(clippy::disallowed_methods, reason = "goldens render through the real binary")]
fn snap(scene: &str, theme: &str, out: &Path) -> Result<(), String> {
    let output = std::process::Command::new(BIN)
        .args(["--snap", &out.to_string_lossy(), "--scene", scene, "--theme", theme, "--scale", "1"])
        .output()
        .map_err(|e| e.to_string())?;
    if output.status.success() && out.exists() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).into_owned())
    }
}

fn read_png(path: &Path) -> (u32, u32, Vec<u8>) {
    let decoder = png::Decoder::new(std::io::BufReader::new(std::fs::File::open(path).unwrap()));
    let mut reader = decoder.read_info().unwrap();
    let mut pixels = vec![0; reader.output_buffer_size()];
    let info = reader.next_frame(&mut pixels).unwrap();
    pixels.truncate(info.buffer_size());
    (info.width, info.height, pixels)
}

/// The number of pixels that differ by more than 12 levels in any channel. Drivers differ in the
/// last bit of blending and glyph coverage; a layout or colour change moves far more.
fn differing(a: &[u8], b: &[u8]) -> usize {
    a.chunks(4)
        .zip(b.chunks(4))
        .filter(|(x, y)| x.iter().zip(y.iter()).any(|(p, q)| p.abs_diff(*q) > 12))
        .count()
}

#[test]
#[cfg_attr(not(target_os = "linux"), ignore = "goldens are checked on Linux")]
fn golden_every_scene_in_light_and_dark() {
    #[expect(clippy::disallowed_methods, reason = "the test's own switch")]
    let update = std::env::var_os("UPDATE_GOLDENS").is_some();
    let scratch = tempfile::tempdir().unwrap();
    let mut misses = Vec::new();
    for (scene, _) in SCENES {
        for theme in ["light", "dark"] {
            let name = format!("{scene}-{theme}.png");
            let out = scratch.path().join(&name);
            if let Err(e) = snap(scene, theme, &out) {
                misses.push(format!("{name}: render failed: {e}"));
                continue;
            }
            let golden = dir().join(&name);
            if update {
                std::fs::create_dir_all(dir()).unwrap();
                std::fs::copy(&out, &golden).unwrap();
                continue;
            }
            let keep = |why: String, misses: &mut Vec<String>| {
                std::fs::create_dir_all(actual_dir()).unwrap();
                let actual = actual_dir().join(&name);
                std::fs::copy(&out, &actual).unwrap();
                misses.push(format!("{why}; actual render at {}", actual.display()));
            };
            if !golden.exists() {
                keep(format!("{name} has no golden; run with UPDATE_GOLDENS=1"), &mut misses);
                continue;
            }
            let (w, h, want) = read_png(&golden);
            let (aw, ah, got) = read_png(&out);
            if (w, h) != (aw, ah) {
                keep(format!("{name}: size {aw}x{ah}, golden {w}x{h}"), &mut misses);
                continue;
            }
            let diff = differing(&got, &want);
            let limit = (w * h) as usize / 500;
            if diff > limit {
                keep(format!("{name}: {diff} pixels differ (limit {limit})"), &mut misses);
            }
        }
    }
    assert!(misses.is_empty(), "{}", misses.join("\n"));
}
