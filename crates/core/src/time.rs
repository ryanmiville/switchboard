//! UTC timestamps as whole seconds since the Unix epoch, written as RFC 3339
//! (`2026-10-29T17:04:11Z`). Callers pass the current time in, so tests are deterministic.

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Timestamp(pub i64);

impl Timestamp {
    pub fn from_system(time: std::time::SystemTime) -> Self {
        Timestamp(time.duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64))
    }

    pub fn rfc3339(self) -> String {
        let days = self.0.div_euclid(86_400);
        let secs = self.0.rem_euclid(86_400);
        let (y, m, d) = civil_from_days(days);
        format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z", secs / 3600, secs / 60 % 60, secs % 60)
    }

    /// Parses `YYYY-MM-DDTHH:MM:SS`, optional fractional seconds, then `Z` or `±HH:MM`.
    pub fn parse(text: &str) -> Option<Self> {
        let b = text.as_bytes();
        if b.len() < 20
            || b[4] != b'-'
            || b[7] != b'-'
            || !matches!(b[10], b'T' | b't')
            || b[13] != b':'
            || b[16] != b':'
        {
            return None;
        }
        let n = |r: std::ops::Range<usize>| text.get(r)?.parse::<i64>().ok();
        let (y, mo, d, h, mi, s) = (n(0..4)?, n(5..7)?, n(8..10)?, n(11..13)?, n(14..16)?, n(17..19)?);
        let mut rest = &text[19..];
        if let Some(frac) = rest.strip_prefix('.') {
            rest = frac.trim_start_matches(|c: char| c.is_ascii_digit());
        }
        let offset = match rest {
            "Z" | "z" => 0,
            _ if rest.len() == 6 && rest.as_bytes()[3] == b':' => {
                let sign = match rest.as_bytes()[0] {
                    b'+' => 1,
                    b'-' => -1,
                    _ => return None,
                };
                sign * (rest[1..3].parse::<i64>().ok()? * 3600 + rest[4..6].parse::<i64>().ok()? * 60)
            }
            _ => return None,
        };
        Some(Timestamp(days_from_civil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + s - offset))
    }

    /// "now", "45s ago", "2m ago", "3h ago", "4d ago".
    pub fn ago(self, now: Timestamp) -> String {
        let s = (now.0 - self.0).max(0);
        match s {
            0..5 => "now".into(),
            5..60 => format!("{s}s ago"),
            60..3600 => format!("{}m ago", s / 60),
            3600..86_400 => format!("{}h ago", s / 3600),
            _ => format!("{}d ago", s / 86_400),
        }
    }
}

// Howard Hinnant's civil-calendar algorithms.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamps_round_trip_through_rfc3339() {
        for t in [0, 951_782_400, 1_761_757_451, 4_102_444_799] {
            let text = Timestamp(t).rfc3339();
            assert_eq!(Timestamp::parse(&text), Some(Timestamp(t)), "{text}");
        }
        assert_eq!(Timestamp(1_761_757_451).rfc3339(), "2025-10-29T17:04:11Z");
    }

    #[test]
    fn offsets_and_fractions_are_understood() {
        assert_eq!(
            Timestamp::parse("2025-10-29T19:04:11.250+02:00"),
            Timestamp::parse("2025-10-29T17:04:11Z")
        );
        assert_eq!(Timestamp::parse("yesterday"), None);
    }
}
