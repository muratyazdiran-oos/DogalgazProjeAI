import SwiftUI

struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProjectAnalysis
    @State private var selectedPipeID: UUID?
    @State private var selectedDeviceID: UUID?
    @State private var undoStack: [ProjectAnalysis] = []
    @State private var redoStack: [ProjectAnalysis] = []
    @State private var gestureStart: ProjectAnalysis?
    @State private var showDeviceInspector = false
    let roomScan: RoomScanSnapshot?
    let onSave: (ProjectAnalysis) -> Void

    init(analysis: ProjectAnalysis, roomScan: RoomScanSnapshot?, onSave: @escaping (ProjectAnalysis) -> Void) {
        _draft = State(initialValue: analysis)
        self.roomScan = roomScan
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Cihazı veya seçili borunun uçlarını sürükleyin. Bir boruya dokunarak çapını değiştirin.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GeometryReader { geometry in
                    ZStack {
                        ProjectCanvasView(analysis: draft, showsDevices: false)
                        deviceHandles(in: geometry.size)
                        pipeHandles(in: geometry.size)
                    }
                    .coordinateSpace(name: "editorCanvas")
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        selectedPipeID = nearestPipe(to: location, size: geometry.size)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(.quaternary) }

                if let index = selectedPipeIndex {
                    HStack {
                        Label("Boru çapı", systemImage: "arrow.left.and.right.circle")
                        Spacer()
                        Picker("Boru çapı", selection: Binding(get: { draft.pipes[index].diameterMM }, set: { setDiameter($0, at: index) })) {
                            ForEach([15, 18, 22, 28, 35, 42, 54], id: \.self) { Text("Ø\($0)").tag($0) }
                        }.pickerStyle(.menu)
                    }.padding(.horizontal)
                } else {
                    Text("Çap değiştirmek için turuncu boruya dokunun")
                        .font(.caption).foregroundStyle(.secondary)
                }
                editorControls
            }
            .padding()
            .navigationTitle("Projeyi Düzelt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        refreshSummary()
                        onSave(draft)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDeviceInspector) {
                if let index = selectedDeviceIndex {
                    DeviceInspectorView(device: draft.devices[index]) { updated in
                        checkpoint()
                        if let liveIndex = draft.devices.firstIndex(where: { $0.id == updated.id }) {
                            draft.devices[liveIndex] = updated
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func deviceHandles(in size: CGSize) -> some View {
        ForEach(draft.devices.indices, id: \.self) { index in
            let device = draft.devices[index]
            VStack(spacing: 2) {
                Image(systemName: device.type.symbol)
                    .font(.title3).padding(7).background(.blue, in: Circle()).foregroundStyle(.white)
                Text(device.label).font(.caption2.bold())
            }
            .position(x: device.position.x * size.width, y: device.position.y * size.height)
            .overlay { Circle().stroke(selectedDeviceID == device.id ? .yellow : .clear, lineWidth: 3).frame(width: 46, height: 46) }
            .onTapGesture { selectedDeviceID = device.id; selectedPipeID = nil }
            .gesture(DragGesture(coordinateSpace: .named("editorCanvas")).onChanged { value in
                beginGesture(); draft.devices[index].position = normalized(value.location, size: size)
            }.onEnded { _ in
                snapDeviceToNetwork(at: index)
                endGesture()
            })
        }
    }

    @ViewBuilder private func pipeHandles(in size: CGSize) -> some View {
        if let index = selectedPipeIndex {
            endpoint(index: index, isStart: true, size: size)
            endpoint(index: index, isStart: false, size: size)
        }
    }

    private func endpoint(index: Int, isStart: Bool, size: CGSize) -> some View {
        let point = isStart ? draft.pipes[index].start : draft.pipes[index].end
        return Circle().fill(.white).stroke(.orange, lineWidth: 4).frame(width: 26, height: 26)
            .position(x: point.x * size.width, y: point.y * size.height)
            .gesture(DragGesture(coordinateSpace: .named("editorCanvas")).onChanged { value in
                beginGesture()
                let updated = normalized(value.location, size: size)
                if isStart { draft.pipes[index].start = updated } else { draft.pipes[index].end = updated }
                recalculateLength(at: index)
            }.onEnded { _ in
                finalizePipeEndpoint(index: index, isStart: isStart)
                endGesture()
            })
    }

    private var editorControls: some View {
        HStack {
            Button(action: undo) { Image(systemName: "arrow.uturn.backward") }.disabled(undoStack.isEmpty)
            Button(action: redo) { Image(systemName: "arrow.uturn.forward") }.disabled(redoStack.isEmpty)
            Spacer()
            Button { showDeviceInspector = true } label: { Label("Cihaz Bilgisi", systemImage: "info.circle") }
                .disabled(selectedDeviceID == nil)
            Menu {
                ForEach(GasDeviceType.allCases, id: \.self) { type in Button(type.title) { addDevice(type) } }
                Button("Boru Bölümü") { addPipe() }
            } label: { Label("Ekle", systemImage: "plus.circle") }
            Button(role: .destructive, action: deleteSelection) { Label("Sil", systemImage: "trash") }
                .disabled(selectedPipeID == nil && selectedDeviceID == nil)
        }.buttonStyle(.bordered)
    }

    private var selectedPipeIndex: Int? {
        guard let id = selectedPipeID else { return nil }
        return draft.pipes.firstIndex { $0.id == id }
    }

    private var selectedDeviceIndex: Int? {
        guard let id = selectedDeviceID else { return nil }
        return draft.devices.firstIndex { $0.id == id }
    }

    private func normalized(_ point: CGPoint, size: CGSize) -> Point2D {
        Point2D(x: min(max(point.x / size.width, 0.02), 0.98), y: min(max(point.y / size.height, 0.02), 0.98))
    }

    private func checkpoint() { undoStack.append(draft); redoStack.removeAll() }
    private func beginGesture() { if gestureStart == nil { gestureStart = draft } }
    private func endGesture() { if let before = gestureStart, before != draft { undoStack.append(before); redoStack.removeAll() }; gestureStart = nil }
    private func undo() { guard let previous = undoStack.popLast() else { return }; redoStack.append(draft); draft = previous }
    private func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(draft); draft = next }
    private func setDiameter(_ value: Int, at index: Int) { guard draft.pipes[index].diameterMM != value else { return }; checkpoint(); draft.pipes[index].diameterMM = value }
    private func addDevice(_ type: GasDeviceType) { checkpoint(); let item = GasDevice(id: UUID(), type: type, position: .init(x: 0.5, y: 0.5), label: type.title, capacityKW: nil); draft.devices.append(item); selectedDeviceID = item.id; selectedPipeID = nil }
    private func addPipe() { checkpoint(); let item = PipeSegment(id: UUID(), start: .init(x: 0.3, y: 0.5), end: .init(x: 0.7, y: 0.5), diameterMM: 22, lengthMeters: 0); draft.pipes.append(item); selectedPipeID = item.id; selectedDeviceID = nil; recalculateLength(at: draft.pipes.count - 1) }
    private func deleteSelection() { checkpoint(); if let id = selectedPipeID { draft.pipes.removeAll { $0.id == id } }; if let id = selectedDeviceID { draft.devices.removeAll { $0.id == id } }; selectedPipeID = nil; selectedDeviceID = nil }

    private func recalculateLength(at index: Int) {
        guard let scan = roomScan else { return }
        let pipe = draft.pipes[index]
        let dx = ((pipe.end.x - pipe.start.x) / 0.84) * scan.widthMeters
        let dy = ((pipe.end.y - pipe.start.y) / 0.84) * scan.depthMeters
        draft.pipes[index].lengthMeters = hypot(dx, dy)
    }

    private func snapDeviceToNetwork(at index: Int) {
        guard draft.devices.indices.contains(index), !draft.pipes.isEmpty else { return }
        let point = draft.devices[index].position
        let candidates = draft.pipes.flatMap { [$0.start, $0.end] }
        guard let nearest = candidates.min(by: { pointDistance(point, $0) < pointDistance(point, $1) }),
              pointDistance(point, nearest) <= 0.06 else { return }
        draft.devices[index].position = nearest
    }

    private func finalizePipeEndpoint(index: Int, isStart: Bool) {
        guard draft.pipes.indices.contains(index) else { return }
        var point = isStart ? draft.pipes[index].start : draft.pipes[index].end

        // Önce mevcut düğüm uçlarına yapıştır.
        let endpointCandidates = draft.pipes.indices
            .filter { $0 != index }
            .flatMap { [draft.pipes[$0].start, draft.pipes[$0].end] }
        if let nearest = endpointCandidates.min(by: { pointDistance(point, $0) < pointDistance(point, $1) }),
           pointDistance(point, nearest) <= 0.04 {
            point = nearest
            setPipeEndpoint(index: index, isStart: isStart, point: point)
            recalculateLength(at: index)
            return
        }

        // Bir branşman başka bir segmentin ortasına bırakıldıysa ana segmenti o noktadan ikiye böl.
        var best: (pipeIndex: Int, point: Point2D, distance: Double, t: Double)?
        for otherIndex in draft.pipes.indices where otherIndex != index {
            let other = draft.pipes[otherIndex]
            let candidate = closestPointWithParameter(point, other.start, other.end)
            guard candidate.t > 0.08, candidate.t < 0.92, candidate.distance <= 0.035 else { continue }
            if best == nil || candidate.distance < best!.distance {
                best = (otherIndex, candidate.point, candidate.distance, candidate.t)
            }
        }

        if let best {
            let other = draft.pipes[best.pipeIndex]
            let oldEnd = other.end
            let oldLength = other.lengthMeters
            let geometricTotal = max(pointDistance(other.start, oldEnd), 0.000001)
            let firstRatio = pointDistance(other.start, best.point) / geometricTotal
            let secondRatio = pointDistance(best.point, oldEnd) / geometricTotal

            draft.pipes[best.pipeIndex].end = best.point
            if roomScan != nil {
                recalculateLength(at: best.pipeIndex)
            } else if oldLength > 0 {
                draft.pipes[best.pipeIndex].lengthMeters = oldLength * firstRatio
            }

            var second = PipeSegment(
                id: UUID(),
                start: best.point,
                end: oldEnd,
                diameterMM: other.diameterMM,
                lengthMeters: oldLength > 0 ? oldLength * secondRatio : 0
            )
            draft.pipes.append(second)
            if roomScan != nil {
                recalculateLength(at: draft.pipes.count - 1)
                second = draft.pipes[draft.pipes.count - 1]
                draft.pipes[draft.pipes.count - 1] = second
            }
            point = best.point
        }

        setPipeEndpoint(index: index, isStart: isStart, point: point)
        recalculateLength(at: index)
    }

    private func setPipeEndpoint(index: Int, isStart: Bool, point: Point2D) {
        if isStart { draft.pipes[index].start = point } else { draft.pipes[index].end = point }
    }

    private func closestPointWithParameter(_ p: Point2D, _ a: Point2D, _ b: Point2D) -> (point: Point2D, distance: Double, t: Double) {
        let vx = b.x - a.x, vy = b.y - a.y
        let wx = p.x - a.x, wy = p.y - a.y
        let vv = vx * vx + vy * vy
        guard vv > 0 else { return (a, pointDistance(p, a), 0) }
        let t = min(1, max(0, (wx * vx + wy * vy) / vv))
        let q = Point2D(x: a.x + t * vx, y: a.y + t * vy)
        return (q, pointDistance(p, q), t)
    }

    private func pointDistance(_ a: Point2D, _ b: Point2D) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func refreshSummary() {
        draft.materialSummary = HydraulicCalculator.estimateMaterialSummary(draft)
        draft.notes.removeAll { $0.hasPrefix("Manuel düzeltme:") }
        draft.notes.insert("Manuel düzeltme: Cihaz konumları, boru güzergâhı ve çapları kullanıcı tarafından kontrol edilip kaydedildi.", at: 0)
    }

    private func nearestPipe(to point: CGPoint, size: CGSize) -> UUID? {
        draft.pipes.map { pipe in
            let a = CGPoint(x: pipe.start.x * size.width, y: pipe.start.y * size.height)
            let b = CGPoint(x: pipe.end.x * size.width, y: pipe.end.y * size.height)
            return (pipe.id, distance(point, toSegmentFrom: a, to: b))
        }.filter { $0.1 < 32 }.min { $0.1 < $1.1 }?.0
    }

    private func distance(_ p: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
