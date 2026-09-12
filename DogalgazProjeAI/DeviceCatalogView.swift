import SwiftUI
import UniformTypeIdentifiers

struct DeviceCatalogView: View {
    @State private var showImporter = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Text("AI kombi/ocak marka-model adaylarını bu katalogla eşleştirir. GasLine kod/ad alanları yalnız doğrulanmış bir eşleme dosyasından gelmelidir.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Katalog JSON İçe Aktar") { showImporter = true }
                Button("GasLine Eşleme Şablonunu Dışa Aktar") {
                    do { shareURL = try DeviceCatalog.exportTemplate(); showShare = true }
                    catch { message = error.localizedDescription }
                }
            }
            Section("Kombi kataloğu • \(DeviceCatalog.models(for: .boiler).count)") {
                ForEach(DeviceCatalog.models(for: .boiler)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayName).font(.headline)
                        HStack {
                            if let kw = item.nominalPowerKW { Text(String(format: "%.1f kW", kw)) }
                            if let gl = item.gasLineName { Text("GasLine: \(gl)") }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Cihaz Kataloğu")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let count = try DeviceCatalog.importModels(from: Data(contentsOf: url))
                message = "\(count) cihaz kaydı içe aktarıldı."
            } catch { message = error.localizedDescription }
        }
        .sheet(isPresented: $showShare) { if let shareURL { ShareSheet(items: [shareURL]) } }
        .alert("Cihaz Kataloğu", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("Tamam", role: .cancel) {} } message: { Text(message ?? "") }
    }
}
