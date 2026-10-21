import Foundation

struct Router {
    let config: Config

    static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    func route(url: URL) -> String {
        decision(url: url).profile
    }

    func decision(url: URL) -> (profile: String, route: Route?) {
        let urlString = url.absoluteString.lowercased()

        for route in config.routes {
            let value = route.value.lowercased()
            guard !value.isEmpty else { continue }
            let matches =
                switch route.condition {
                case .contains: urlString.contains(value)
                case .exact: urlString == value
                case .domain:
                    Self.isWebURL(url)
                        && ((url.host?.lowercased() == value)
                            || (url.host?.lowercased().hasSuffix("." + value) == true))
                }
            if matches {
                return (route.profile, route)
            }
        }

        return (config.defaultProfile, nil)
    }
}
