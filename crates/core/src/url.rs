//! Just enough URL parsing for routing. A link is kept as the exact string it arrived as: matching
//! runs on it and launching passes it on unchanged. Only the scheme and host are read out of it.
//! (A full URL library would re-serialise the link, changing case, escapes and trailing slashes.)

/// The parts of a link routing needs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Link<'a> {
    pub scheme: &'a str,
    /// The host as written, without brackets for IPv6 and without user info or port. `None` when
    /// the link has no `//` authority; empty when the authority is empty (`file:///tmp`).
    pub host: Option<&'a str>,
    /// Everything after the authority, up to the query or fragment.
    pub path: &'a str,
}

/// Parses `text` as an absolute URL, or returns `None` when it isn't one: no scheme, whitespace or
/// control characters, or a port that isn't a number.
pub fn parse(text: &str) -> Option<Link<'_>> {
    if text.is_empty() || text.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return None;
    }
    let colon = text.find(':')?;
    let scheme = &text[..colon];
    let mut chars = scheme.chars();
    if !chars.next().is_some_and(|c| c.is_ascii_alphabetic())
        || !chars.all(|c| c.is_ascii_alphanumeric() || "+-.".contains(c))
    {
        return None;
    }
    let rest = &text[colon + 1..];
    let end_of = |s: &str| s.find(['?', '#']).unwrap_or(s.len());
    let Some(after) = rest.strip_prefix("//") else {
        return Some(Link { scheme, host: None, path: &rest[..end_of(rest)] });
    };
    let authority_end = after.find(['/', '?', '#']).unwrap_or(after.len());
    let authority = &after[..authority_end];
    let tail = &after[authority_end..];
    let host_port = authority.rsplit_once('@').map_or(authority, |(_, h)| h);
    let host = if let Some(bracketed) = host_port.strip_prefix('[') {
        let close = bracketed.find(']')?;
        let port = &bracketed[close + 1..];
        if !(port.is_empty() || port.strip_prefix(':').is_some_and(|p| p.chars().all(|c| c.is_ascii_digit())))
        {
            return None;
        }
        &bracketed[..close]
    } else {
        match host_port.split_once(':') {
            Some((host, port)) if port.chars().all(|c| c.is_ascii_digit()) => host,
            Some(_) => return None,
            None => host_port,
        }
    };
    Some(Link { scheme, host: Some(host), path: &tail[..end_of(tail)] })
}

/// The lowercased host of a web link.
pub fn web_host(text: &str) -> Option<String> {
    let link = parse(text)?;
    let web = matches!(link.scheme.to_ascii_lowercase().as_str(), "http" | "https");
    link.host.filter(|h| web && !h.is_empty()).map(str::to_lowercase)
}

/// A complete `http` or `https` link with a host.
pub fn is_web(text: &str) -> bool {
    web_host(text).is_some()
}

/// A `file:` link to an absolute local path.
pub fn is_local_file(text: &str) -> bool {
    parse(text).is_some_and(|l| {
        l.scheme.eq_ignore_ascii_case("file")
            && l.host.is_some_and(|h| h.is_empty() || h.eq_ignore_ascii_case("localhost"))
            && l.path.starts_with('/')
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_host_drops_user_info_port_and_brackets_but_keeps_its_case() {
        assert_eq!(parse("https://me:pw@Example.COM:8443/a?b#c").unwrap().host, Some("Example.COM"));
        assert_eq!(parse("http://[::1]:80/x").unwrap().host, Some("::1"));
        assert_eq!(parse("https://example.com./").unwrap().host, Some("example.com."));
    }

    #[test]
    fn web_links_need_an_http_scheme_and_a_host() {
        assert!(is_web("HTTPS://github.com"));
        assert!(!is_web("https:///path"));
        assert!(!is_web("mailto:me@example.com"));
        assert!(!is_web("github.com"));
        assert!(!is_web("https://exa mple.com"));
        assert!(!is_web("https://example.com:http/"));
    }

    #[test]
    fn local_files_need_an_absolute_path_on_this_machine() {
        assert!(is_local_file("file:///tmp/a.html"));
        assert!(is_local_file("file://localhost/tmp/a.html"));
        assert!(!is_local_file("file://server/share/a.html"));
    }

    #[test]
    fn the_path_stops_at_the_query_and_fragment() {
        assert_eq!(parse("https://a.com/p/q?x=1#f").unwrap().path, "/p/q");
    }
}
