import SwiftUI
import UniformTypeIdentifiers

struct DeviceCatalogView: View {
    @State private var showImporter = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var message: String?

    var body: some View {
        ZStack {
            GasUI.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    catalogHeader
                    ForEach(DeviceCatalog.models(for: .boiler)) { item in
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14).fill(GasUI.blue.opacity(0.14))
                                Image(systemName: "flame.fill").font(.title2).foregroundStyle(GasUI.blue)
                            }.frame(width: 54, height: 54)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.displayName).font(.headline)
                                HStack(spacing: 10) {
                                    if let kw = item.nominalPowerKW { Label(String(format: "%.1f kW", kw), systemImage: "bolt.fill") }
                                    if let gl = item.gasLineName { Text("GasLine • \(gl)") }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(GasUI.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                }.padding()
            }
        }
        .navigationTitle("Cihaz Kataloğu")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
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

    private var catalogHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Akıllı Cihaz Kataloğu").font(.title3.bold())
                    Text("\(DeviceCatalog.models(for: .boiler).count) kombi modeli").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "cpu.fill").font(.title2).foregroundStyle(GasUI.green)
            }
            Text("AI marka-model adaylarını katalogla eşleştirir. GasLine alanları yalnız doğrulanmış eşleme dosyasından gelir.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button { showImporter = true } label: { Label("JSON İçe Aktar", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent)
                Button {
                    do { shareURL = try DeviceCatalog.exportTemplate(); showShare = true }
                    catch { message = error.localizedDescription }
                } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(GasUI.card, in: RoundedRectangle(cornerRadius: 22))
    }
}