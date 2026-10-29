import Foundation

struct Router {
    let config: Config

    static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    static func isLocalFileURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "file" && ["", "localhost"].contains(url.host?.lowercased() ?? "")
            && url.path.hasPrefix("/")
    }

    func route(url: URL) -> Destination {
        decision(url: url).destination
    }

    func decision(url: URL) -> (destination: Destination, route: Route?) {
        let urlString = url.absoluteString.lowercased()

        for route in config.routes where Self.matches(route, url: url, urlString: urlString) {
            return (Destination(browser: route.browser ?? config.browser, profile: route.profile), route)
        }

        return (Destination(browser: config.browser, profile: config.defaultProfile), nil)
    }

    static func matches(_ route: Route, url: URL) -> Bool {
        matches(route, url: url, urlString: url.absoluteString.lowercased())
    }

    private static func matches(_ route: Route, url: URL, urlString: String) -> Bool {
        let value = route.value.lowercased()
        guard !value.isEmpty else { return false }
        return switch route.condition {
        case .contains: urlString.contains(value)
        case .exact: urlString == value
        case .domain:
            isWebURL(url)
                && ((url.host?.lowercased() == value)
                    || (url.host?.lowercased().hasSuffix("." + value) == true))
        }
    }
}
