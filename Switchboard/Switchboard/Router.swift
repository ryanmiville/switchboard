import Foundation

struct Router {
    let config: Config
    
    func route(url: URL) -> String {
        let urlString = url.absoluteString.lowercased()
        
        for route in config.routes {
            let value = route.value.lowercased()
            let matches = switch route.condition {
                case .contains: urlString.contains(value)
                case .exact: urlString == value
            }
            if matches {
                return route.profile
            }
        }
        
        return config.defaultProfile
    }
}
