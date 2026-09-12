import Foundation

enum APIConfig {
    private static let baseURLKey = "gasai.apiBaseURL"
    private static let mockKey = "gasai.demoMode"
    private static let tokenKey = "gasai.apiToken"

    /// Info.plist içindeki API_BASE_URL veya uygulama Ayarlar ekranından girilen adres kullanılır.
    static var baseURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = normalizedURL(raw) { return url }
        if let raw = UserDefaults.standard.string(forKey: baseURLKey),
           let url = normalizedURL(raw) { return url }
        return nil
    }

    static var baseURLString: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: baseURLKey) }
    }

    /// İlk kurulumda demo açık gelir; gerçek backend URL girildikten sonra kapatılabilir.
    static var useMockAI: Bool {
        get {
            if UserDefaults.standard.object(forKey: mockKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: mockKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: mockKey) }
    }

    static var apiToken: String {
        get { KeychainStore.string(for: tokenKey) ?? "" }
        set { KeychainStore.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: tokenKey) }
    }

    static var isBackendConfigured: Bool { baseURL != nil }

    static func validateBackendURL(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return "Geçerli bir backend adresi gir."
        }
        if scheme == "https" { return nil }
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) {
            return nil
        }
        return "Üretim backend adresi HTTPS olmalı. HTTP yalnızca localhost geliştirme için kabul edilir."
    }

    private static func normalizedURL(_ raw: String) -> URL? {
        guard validateBackendURL(raw) == nil else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: value)
    }
}
