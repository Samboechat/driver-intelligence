import Foundation

/// Container compartilhado entre o app e a extensão de widgets.
/// AltStore/SideStore renomeiam o App Group na instalação e gravam o novo
/// identificador em `ALTAppGroups` no Info.plist — por isso a resolução dinâmica.
enum AppGroup {
    static let defaultIdentifier = "group.com.driverpro.roi"

    static var identifier: String {
        if let groups = hostInfo?["ALTAppGroups"] as? [String], let first = groups.first {
            return first
        }
        return defaultIdentifier
    }

    private static var hostInfo: [String: Any]? {
        var url = Bundle.main.bundleURL
        if url.pathExtension == "appex" {
            url = url.deletingLastPathComponent().deletingLastPathComponent()
        }
        if let bundle = Bundle(url: url), let info = bundle.infoDictionary {
            return info
        }
        return Bundle.main.infoDictionary
    }

    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}
