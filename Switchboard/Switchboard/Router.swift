import Foundation

struct Router {
    let config: Config
    
    func route(url: URL) -> String {
        let urlString = url.absoluteString.lowercased()
        
        for route in config.routes {
            if urlString.contains(route.contains.lowercased()) {
                return route.profile
            }
        }
        
        return config.defaultProfile
    }
}
