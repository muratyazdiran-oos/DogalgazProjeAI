import SwiftUI
import Foundation
import RoomPlan
import simd

struct RoomPlanScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: (RoomScanSnapshot) -> Void
    @State private var isScanning = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                GasUI.background.ignoresSafeArea()
                if RoomCaptureSession.isSupported {
                    RoomCaptureRepresentable(isScanning: $isScanning) { result in
                        switch result {
                        case .success(let room): onComplete(RoomScanConverter.snapshot(from: room)); dismiss()
                        case .failure(let error): errorMessage = error.localizedDescription
                        }
                    }.ignoresSafeArea(edges: .bottom)
                    VStack {
                        scannerHeader
                        Spacer()
                        scannerGuide
                        scannerControls
                    }.padding()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 48)).foregroundStyle(GasUI.blue)
                        Text("LiDAR gerekli").font(.title2.bold())
                        Text("Bu cihaz RoomPlan oda taramasını desteklemiyor. Video analizi ve manuel ölçüm kullanılabilir.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }.padding(30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .alert("Tarama Hatası", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Tamam", role: .cancel) { }
            } message: { Text(errorMessage ?? "Bilinmeyen hata") }
        }
    }

    private var scannerHeader: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle()) }
            Spacer()
            VStack(spacing: 2) { Text("LiDAR ile Tarama").font(.headline); Text(isScanning ? "CANLI" : "İŞLENİYOR").font(.caption2.bold()).foregroundStyle(isScanning ? GasUI.green : .orange) }
            Spacer()
            Image(systemName: "questionmark").frame(width: 42, height: 42).background(.ultraThinMaterial, in: Circle())
        }
    }

    private var scannerGuide: some View {
        VStack(spacing: 5) {
            Image(systemName: "viewfinder").font(.title2).foregroundStyle(GasUI.green)
            Text("Odayı yavaşça tarayın").font(.headline)
            Text("Duvar, kapı ve pencereleri kadrajda tutun").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var scannerControls: some View {
        Button { isScanning = false } label: {
            ZStack {
                Circle().fill(Color.white).frame(width: 76, height: 76)
                Circle().fill(GasUI.blue).frame(width: 60, height: 60)
                Image(systemName: "checkmark").font(.title2.bold()).foregroundStyle(.white)
            }
        }.padding(.top, 12).disabled(!isScanning)
    }
}

@objc(DogalgazRoomCaptureCoordinator)
final class RoomCaptureCoordinator: NSObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate {
    weak var captureView: RoomCaptureView?
    var didRequestStop = false
    private let completion: (Result<CapturedRoom, Error>) -> Void
    init(completion: @escaping (Result<CapturedRoom, Error>) -> Void) { self.completion = completion; super.init() }
    required init?(coder: NSCoder) { self.completion = { _ in }; super.init() }
    func encode(with coder: NSCoder) {}
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) { if let error { completion(.failure(error)) } }
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { error == nil }
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) { if let error { completion(.failure(error)); return }; completion(.success(processedResult)) }
}

private struct RoomCaptureRepresentable: UIViewRepresentable {
    @Binding var isScanning: Bool
    let completion: (Result<CapturedRoom, Error>) -> Void
    func makeCoordinator() -> RoomCaptureCoordinator { RoomCaptureCoordinator(completion: completion) }
    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero); view.captureSession.delegate = context.coordinator; view.delegate = context.coordinator; context.coordinator.captureView = view
        var configuration = RoomCaptureSession.Configuration(); configuration.isCoachingEnabled = true; view.captureSession.run(configuration: configuration); return view
    }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) { if !isScanning && !context.coordinator.didRequestStop { context.coordinator.didRequestStop = true; uiView.captureSession.stop() } }
    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: RoomCaptureCoordinator) { uiView.captureSession.stop() }
}

enum RoomScanConverter {
    static func snapshot(from room: CapturedRoom) -> RoomScanSnapshot {
        let walls = room.walls.map { wall in
            let t = wall.transform
            return MeasuredWall(centerX: Double(t.columns.3.x), centerZ: Double(t.columns.3.z), lengthMeters: Double(wall.dimensions.x), heightMeters: Double(wall.dimensions.y), yawRadians: Double(atan2(t.columns.0.z, t.columns.0.x)))
        }
        let openings: [MeasuredOpening] = room.doors.map { makeOpening($0, kind: .door) } + room.windows.map { makeOpening($0, kind: .window) } + room.openings.map { makeOpening($0, kind: .opening) }
        let extents = bounds(for: walls), maxHeight = walls.map(\.heightMeters).max() ?? 2.6
        return RoomScanSnapshot(widthMeters: max(extents.maxX-extents.minX,0.1), depthMeters: max(extents.maxZ-extents.minZ,0.1), heightMeters: maxHeight, minX: extents.minX, maxX: extents.maxX, minZ: extents.minZ, maxZ: extents.maxZ, walls: walls, openings: openings, capturedAt: .now)
    }
    private static func makeOpening(_ surface: CapturedRoom.Surface, kind: MeasuredOpening.Kind) -> MeasuredOpening {
        let t=surface.transform
        return MeasuredOpening(kind: kind, centerX: Double(t.columns.3.x), centerZ: Double(t.columns.3.z), widthMeters: Double(surface.dimensions.x), heightMeters: Double(surface.dimensions.y), yawRadians: Double(atan2(t.columns.0.z,t.columns.0.x)), bottomMeters: max(0,Double(t.columns.3.y)-Double(surface.dimensions.y)/2))
    }
    private static func bounds(for walls:[MeasuredWall])->(minX:Double,maxX:Double,minZ:Double,maxZ:Double){
        guard !walls.isEmpty else{return(0,1,0,1)}; var xs:[Double]=[],zs:[Double]=[]
        for wall in walls { let half=wall.lengthMeters/2,dx=cos(wall.yawRadians)*half,dz=sin(wall.yawRadians)*half; xs += [wall.centerX-dx,wall.centerX+dx]; zs += [wall.centerZ-dz,wall.centerZ+dz] }
        return(xs.min() ?? 0,xs.max() ?? 1,zs.min() ?? 0,zs.max() ?? 1)
    }
}