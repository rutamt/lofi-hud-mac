import AppKit

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

/// Checks GitHub Releases for a newer version. The app is ad-hoc signed, so it never installs
/// anything itself; it just points you at the release page.
enum Updater {
    struct Release: Equatable {
        let version: String
        let page: URL
        let dmg: URL?
    }

    /// `owner/repo`, from Info.plist so forks can point elsewhere.
    static var repo: String {
        Bundle.main.object(forInfoDictionaryKey: "LoFiHUDGitHubRepo") as? String ?? "rutamt/lofi-hud-mac"
    }

    private static let lastCheckKey = "LastUpdateCheck"

    /// At most once a day for automatic checks.
    static var isAutoCheckDue: Bool {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        return Date().timeIntervalSince1970 - last > 24 * 3600
    }

    /// Completion runs on main with the newer release, nil if up to date, or an error.
    static func check(completion: @escaping (Result<Release?, Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LoFiHUD/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<Release?, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                result = .success(nil)  // no releases published yet
            } else if let data, let release = parse(data) {
                result = .success(isNewer(release.version, than: AppInfo.version) ? release : nil)
            } else {
                result = .failure(URLError(.cannotParseResponse))
            }
            DispatchQueue.main.async {
                if case .success = result {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
                }
                if case .failure(let e) = result {
                    Log.app.notice("Update check failed: \(e.localizedDescription, privacy: .public)")
                }
                completion(result)
            }
        }.resume()
    }

    static func parse(_ data: Data) -> Release? {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Payload: Decodable { let tag_name: String; let html_url: URL; let assets: [Asset]? }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let version = p.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let dmg = p.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }?.browser_download_url
        return Release(version: version, page: p.html_url, dmg: dmg)
    }

    /// Numeric dotted comparison: "2.10.0" > "2.9.1".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func presentAvailable(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "LoFi HUD \(release.version) is available"
        alert.informativeText = """
            You have \(AppInfo.version). Download the DMG, quit LoFi HUD, and drag the new app into \
            Applications to replace it. Your settings are kept.
            """
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.dmg ?? release.page)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(release.page)
        default: break
        }
    }
}
