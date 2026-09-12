import SwiftUI

struct APISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = APIConfig.baseURLString
    @State private var demoMode = APIConfig.useMockAI
    @State private var apiToken = APIConfig.apiToken
    @State private var message: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("AI bağlantısı") {
                    TextField("https://api.ornek.com", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("API erişim tokenı (opsiyonel)", text: $apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Demo verisi kullan", isOn: $demoMode)
                }
                Section {
                    Text("Gerçek video analizi için kendi backend sunucunun HTTPS adresini gir ve demo modunu kapat. Gemini API anahtarını iPhone uygulamasına koyma; backend .env içinde tut. APP_API_TOKEN kullanırsan aynı tokenı burada güvenli anahtarlıkta saklayabilirsin.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if isTesting { ProgressView() } else { Label("Bağlantıyı Test Et", systemImage: "network") }
                    }
                    .disabled(isTesting || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("AI Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !demoMode, let validationMessage = APIConfig.validateBackendURL(trimmed) {
                            message = validationMessage
                            return
                        }
                        APIConfig.baseURLString = trimmed
                        APIConfig.apiToken = apiToken
                        APIConfig.useMockAI = demoMode
                        dismiss()
                    }
                }
            }
        }
    }

    @MainActor
    private func testConnection() async {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationMessage = APIConfig.validateBackendURL(raw) {
            message = validationMessage
            return
        }
        guard let root = URL(string: raw) else {
            message = "Geçerli bir backend adresi gir."
            return
        }
        isTesting = true
        defer { isTesting = false }
        do {
            var request = URLRequest(url: root.appendingPathComponent("health"))
            request.timeoutInterval = 15
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: configuration)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                message = "Sunucuya ulaşıldı ancak health kontrolü başarısız."
                return
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let model = object["model"] as? String {
                message = "Bağlantı başarılı • \(model)"
            } else {
                message = "Bağlantı başarılı."
            }
        } catch {
            message = "Bağlantı kurulamadı: \(error.localizedDescription)"
        }
    }

}
