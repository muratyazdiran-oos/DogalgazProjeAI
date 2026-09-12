import SwiftUI

struct ManualRoomMeasureView: View {
    @Environment(\.dismiss) private var dismiss
    let existingScan: RoomScanSnapshot?
    let onComplete: (RoomScanSnapshot) -> Void

    @State private var widthText: String
    @State private var depthText: String
    @State private var heightText: String
    @State private var validationMessage: String?

    init(existingScan: RoomScanSnapshot?, onComplete: @escaping (RoomScanSnapshot) -> Void) {
        self.existingScan = existingScan
        self.onComplete = onComplete
        _widthText = State(initialValue: existingScan.map { Self.format($0.widthMeters) } ?? "")
        _depthText = State(initialValue: existingScan.map { Self.format($0.depthMeters) } ?? "")
        _heightText = State(initialValue: existingScan.map { Self.format($0.heightMeters) } ?? "2,60")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Oda ölçüleri") {
                    measurementField("Genişlik", text: $widthText)
                    measurementField("Derinlik", text: $depthText)
                    measurementField("Tavan yüksekliği", text: $heightText)
                }
                Section {
                    Text("Duvarları metreyle ölçün. Uygulama dikdörtgen oda planını gerçek ölçekte oluşturur ve AI boru güzergâhının metrajını bu ölçeğe göre yeniden hesaplar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Manuel Ölçü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Planı Oluştur", action: save) }
            }
            .alert("Ölçüleri Kontrol Edin", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text(validationMessage ?? "Geçersiz ölçü")
            }
        }
    }

    private func measurementField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0,00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text("m").foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let width = parse(widthText), let depth = parse(depthText), let height = parse(heightText),
              (0.5...50).contains(width), (0.5...50).contains(depth), (1.8...10).contains(height) else {
            validationMessage = "Genişlik ve derinlik 0,5–50 m; yükseklik 1,8–10 m arasında olmalıdır."
            return
        }
        onComplete(.rectangular(widthMeters: width, depthMeters: depth, heightMeters: height))
        dismiss()
    }

    private func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }
}
