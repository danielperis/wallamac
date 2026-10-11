import SwiftUI
import AppKit
import UniformTypeIdentifiers

let wallaTeal = Color(red: 0.075, green: 0.757, blue: 0.675)
let wallaDeep = Color(red: 0.03, green: 0.33, blue: 0.38)
let wallaInk = Color(red: 0.05, green: 0.12, blue: 0.15)

// MARK: - Entrada

@main
struct Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            MainActor.assumeIsolated { IconRenderer.render(to: args[i + 1]) }
            return
        }
        WallaMacApp.main()
    }
}

struct WallaMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("WallaMac") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 720)
                .task { model.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Ficha") {
                Button("Volver a analizar") { model.refresh() }.keyboardShortcut("r")
                Button("Exportar imagen para el anuncio…") { model.exportCard() }.keyboardShortcut("e")
                Button("Copiar ficha técnica") { model.copyPlainSpecs() }.keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Estado

enum SerialMode: String, CaseIterable, Identifiable {
    case visible, partial, hidden
    var id: String { rawValue }
    var label: String {
        switch self { case .visible: "Visible"; case .partial: "Parcial"; case .hidden: "Oculto" }
    }
    var symbol: String {
        switch self { case .visible: "eye"; case .partial: "eye.trianglebadge.exclamationmark"; case .hidden: "eye.slash" }
    }
}

func maskSerial(_ s: String, _ mode: SerialMode) -> String {
    guard !s.isEmpty else { return "—" }
    switch mode {
    case .visible: return s
    case .hidden: return String(repeating: "•", count: max(s.count, 10))
    case .partial:
        guard s.count > 5 else { return String(repeating: "•", count: s.count) }
        return String(s.prefix(2)) + String(repeating: "•", count: s.count - 5) + String(s.suffix(3))
    }
}

enum Section: String, CaseIterable, Identifiable {
    case specs, listing, checklist
    var id: String { rawValue }
    var title: String {
        switch self { case .specs: "Ficha técnica"; case .listing: "Crear anuncio"; case .checklist: "Antes de vender" }
    }
    var symbol: String {
        switch self { case .specs: "cpu"; case .listing: "tag"; case .checklist: "checklist" }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var specs: MacSpecs?
    @Published var loading = false
    @Published var section: Section = .specs
    @Published var toast: String?
    @AppStorage("serialMode") var serialModeRaw = SerialMode.partial.rawValue
    @AppStorage("cardSerialMode") var cardSerialModeRaw = SerialMode.partial.rawValue

    var cardSerialMode: SerialMode {
        get { SerialMode(rawValue: cardSerialModeRaw) ?? .partial }
        set { cardSerialModeRaw = newValue.rawValue; objectWillChange.send() }
    }

    var serialMode: SerialMode {
        get { SerialMode(rawValue: serialModeRaw) ?? .partial }
        set { serialModeRaw = newValue.rawValue; objectWillChange.send() }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let s = SpecsLoader.load()
            await MainActor.run {
                withAnimation(.spring(duration: 0.6)) {
                    self.specs = s
                    self.loading = false
                }
            }
        }
    }

    func copy(_ text: String, _ message: String = "Copiado al portapapeles") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash(message)
    }

    func flash(_ message: String) {
        withAnimation(.spring) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeOut) { if self.toast == message { self.toast = nil } }
        }
    }

    func copyPlainSpecs() {
        guard let s = specs else { return }
        copy(ListingBuilder.plainSpecs(s, serialMode: serialMode), "Ficha técnica copiada")
    }

    func exportCard() {
        guard let s = specs else { return }
        let renderer = ImageRenderer(content: SpecCardView(specs: s, serialMode: cardSerialMode))
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "WallaMac - \(s.compactTitle).png"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? png.write(to: url)
            Task { @MainActor in
                self.flash("Imagen guardada")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}

// MARK: - Raíz

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 260)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                if let s = model.specs {
                    Group {
                        switch model.section {
                        case .specs: SpecsView(specs: s)
                        case .listing: ListingView(specs: s)
                        case .checklist: ChecklistView(specs: s)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    ScanningView()
                }
            }
            .overlay(alignment: .bottom) { ToastView() }
            .toolbar {
                ToolbarItemGroup {
                    Button { model.refresh() } label: { Label("Volver a analizar", systemImage: "arrow.clockwise") }
                        .disabled(model.loading)
                    Button { model.copyPlainSpecs() } label: { Label("Copiar ficha", systemImage: "doc.on.doc") }
                        .disabled(model.specs == nil)
                    Button { model.exportCard() } label: { Label("Exportar imagen", systemImage: "photo.badge.arrow.down") }
                        .disabled(model.specs == nil)
                }
            }
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppGlyph(size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("WallaMac").font(.system(size: 17, weight: .heavy, design: .rounded))
                    Text("Vende tu Mac con datos").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)

            List(selection: Binding(get: { model.section }, set: { if let v = $0 { model.section = v } })) {
                ForEach(Section.allCases) { sec in
                    Label(sec.title, systemImage: sec.symbol).tag(sec)
                }
            }
            .listStyle(.sidebar)

            if let s = model.specs {
                ReadinessMini(specs: s).padding(12)
            }
        }
    }
}

struct ToastView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let t = model.toast {
            Label(t, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(wallaTeal.opacity(0.5)))
                .foregroundStyle(wallaTeal)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Pantalla de análisis

struct ScanningView: View {
    @State private var step = 0
    @State private var spin = false
    private let steps = ["Identificando el modelo…", "Contando núcleos del procesador…", "Midiendo la memoria…",
                         "Comprobando la salud del SSD…", "Preguntando a la batería cómo está…", "Preparando tu ficha…"]
    private let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(wallaTeal.opacity(0.15), lineWidth: 10).frame(width: 130, height: 130)
                Circle().trim(from: 0, to: 0.28)
                    .stroke(AngularGradient(colors: [wallaTeal.opacity(0), wallaTeal], center: .center), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                AppGlyph(size: 70)
            }
            Text("Analizando tu Mac").font(.system(size: 26, weight: .bold, design: .rounded))
            Text(steps[step % steps.count])
                .font(.callout).foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .id(step)
                .transition(.push(from: .bottom))
        }
        .onAppear { spin = true }
        .onReceive(timer) { _ in withAnimation(.easeInOut) { step += 1 } }
    }
}

// MARK: - Ficha técnica

struct SpecsView: View {
    let specs: MacSpecs
    @EnvironmentObject var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 330), spacing: 18, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HeroView(specs: specs)
                if specs.activationLock == true { ActivationBanner() }
                LazyVGrid(columns: columns, spacing: 18) {
                    CPUCard(specs: specs)
                    MemoryCard(specs: specs)
                    StorageCard(specs: specs)
                    GPUCard(specs: specs)
                    BatteryCard(battery: specs.battery)
                    SerialCard(specs: specs)
                    SystemCard(specs: specs)
                }
            }
            .padding(24)
        }
    }
}

struct HeroView: View {
    let specs: MacSpecs
    @State private var appear = false

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [wallaTeal, wallaDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geo in
                Circle().fill(.white.opacity(0.08)).frame(width: 360).offset(x: geo.size.width - 260, y: -140)
                Circle().fill(.white.opacity(0.06)).frame(width: 220).offset(x: geo.size.width - 120, y: 90)
            }
            HStack(spacing: 28) {
                Image(systemName: specs.deviceSymbol)
                    .font(.system(size: 92, weight: .thin))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                    .scaleEffect(appear ? 1 : 0.6)
                    .opacity(appear ? 1 : 0)
                    .frame(width: 140)
                VStack(alignment: .leading, spacing: 8) {
                    if let y = specs.year {
                        Text("AÑO \(y)")
                            .font(.caption.weight(.heavy)).tracking(1.5)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    Text(specs.marketingName)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Text([specs.modelIdentifier, specs.modelNumber].compactMap { $0 }.joined(separator: "  ·  "))
                        .font(.callout.monospaced()).opacity(0.8)
                    HStack(spacing: 8) {
                        Pill(icon: "cpu", text: specs.chipShort)
                        Pill(icon: "memorychip", text: specs.ramLabel)
                        Pill(icon: "internaldrive", text: specs.diskMarketing)
                        if let g = specs.primaryGPU?.cores { Pill(icon: "square.grid.3x3.fill", text: "GPU \(g)c") }
                    }
                    .padding(.top, 6)
                }
                .foregroundStyle(.white)
                Spacer()
            }
            .padding(28)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: wallaTeal.opacity(0.35), radius: 24, y: 12)
        .onAppear { withAnimation(.spring(duration: 0.8, bounce: 0.4).delay(0.1)) { appear = true } }
    }
}

struct Pill: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.white.opacity(0.18), in: Capsule())
    }
}

struct ActivationBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill").font(.title).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Buscar mi Mac está activado").font(.headline).foregroundStyle(.white)
                Text("El bloqueo de activación impedirá que el comprador use el Mac. Desactívalo antes de venderlo.")
                    .font(.callout).foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            Button("Abrir Ajustes de iCloud") { openAppleIDSettings() }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.red)
        }
        .padding(16)
        .background(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

func openAppleIDSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings") {
        NSWorkspace.shared.open(url)
    }
}

// MARK: Tarjetas

struct Card<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = wallaTeal
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(.headline)
                Spacer()
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 262, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.07)))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

struct Row: View {
    let label: String
    let value: String
    var note: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).fontWeight(.medium).multilineTextAlignment(.trailing).textSelection(.enabled)
                if let note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .font(.callout)
    }
}

struct BigValue: View {
    let value: String
    let caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CPUCard: View {
    let specs: MacSpecs
    var body: some View {
        Card(title: "Procesador", icon: "cpu", tint: .indigo) {
            BigValue(value: specs.chipShort, caption: specs.isAppleSilicon ? "Apple Silicon · \(specs.processNode ?? "")" : specs.cpuBrand)
            if let p = specs.pCores, let e = specs.eCores {
                CoreBar(p: p, e: e)
            }
            Row(label: "Núcleos CPU", value: "\(specs.totalCores)")
            if let p = specs.pCores, let e = specs.eCores { Row(label: "Rendimiento + eficiencia", value: "\(p) + \(e)") }
            if let sp = specs.cpuSpeed { Row(label: "Velocidad", value: sp) }
            if let l2 = specs.l2 { Row(label: "Caché L2", value: l2) }
            if let l3 = specs.l3 { Row(label: "Caché L3", value: l3) }
            if let n = specs.neuralCores { Row(label: "Neural Engine", value: "\(n) núcleos") }
            Row(label: "Arquitectura", value: specs.isAppleSilicon ? "ARM64 (Apple Silicon)" : "x86-64 (Intel)")
        }
    }
}

struct CoreBar: View {
    let p: Int
    let e: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<p, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(Color.indigo.gradient).frame(height: 18) }
            ForEach(0..<e, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(Color.indigo.opacity(0.35)).frame(height: 18) }
        }
        .help("\(p) núcleos de rendimiento · \(e) de eficiencia")
    }
}

struct MemoryCard: View {
    let specs: MacSpecs
    var body: some View {
        Card(title: "Memoria RAM", icon: "memorychip", tint: .pink) {
            BigValue(value: specs.ramLabel, caption: specs.isAppleSilicon ? "Memoria unificada" : "Memoria del sistema")
            Row(label: "Tipo", value: specs.ramType ?? "—")
            Row(label: "Velocidad", value: specs.ramSpeed ?? "—", note: specs.ramSpeedIsSpec && specs.ramSpeed != nil ? "según especificación del chip" : nil)
            if let bw = specs.ramBandwidth { Row(label: "Ancho de banda", value: bw) }
            if let m = specs.ramManufacturer { Row(label: "Fabricante", value: m) }
        }
    }
}

struct StorageCard: View {
    let specs: MacSpecs
    var body: some View {
        Card(title: "Almacenamiento", icon: "internaldrive", tint: .orange) {
            BigValue(value: "\(specs.diskMarketing) \(specs.diskSSD ? "SSD" : "HDD")",
                     caption: "\(fmtBytes(specs.diskBytes)) reales · \(fmtBytes(specs.diskFree)) libres")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.orange.opacity(0.15))
                    Capsule().fill(Color.orange.gradient).frame(width: geo.size.width * specs.diskUsedFraction)
                }
            }
            .frame(height: 10)
            Row(label: "Estado SMART", value: smartES(specs.diskSMART))
            if let m = specs.diskModel { Row(label: "Unidad", value: m) }
            if let p = specs.diskProtocol { Row(label: "Conexión", value: p) }
        }
    }
}

func smartES(_ s: String?) -> String {
    switch s {
    case "Verified": return "✓ Verificado"
    case "Failing": return "✗ Fallando"
    case nil, "Not Supported": return "No disponible"
    default: return s ?? "—"
    }
}

func fmtBytes(_ b: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .decimal
    return f.string(fromByteCount: b)
}

struct GPUCard: View {
    let specs: MacSpecs
    var body: some View {
        Card(title: "Tarjeta gráfica", icon: "square.grid.3x3.topleft.filled", tint: .purple) {
            if let g = specs.primaryGPU {
                BigValue(value: g.cores.map { "\($0) núcleos" } ?? g.model, caption: g.model)
            }
            ForEach(specs.gpus) { g in
                if specs.gpus.count > 1 { Row(label: g.integrated ? "Integrada" : "Dedicada", value: g.model) }
                if let v = g.vram { Row(label: "VRAM", value: v) }
                if let m = g.metal { Row(label: "API gráfica", value: m) }
            }
            if let d = specs.builtInDisplay {
                Row(label: "Pantalla", value: [d.kind, d.pixels?.replacingOccurrences(of: " x ", with: "×")].compactMap { $0 }.joined(separator: " · "))
            }
            let ext = specs.displays.filter { !$0.builtIn }
            if !ext.isEmpty {
                Row(label: "Monitores conectados", value: ext.map(\.name).joined(separator: ", "))
            }
        }
    }
}

struct BatteryCard: View {
    let battery: BatteryInfo?
    var body: some View {
        Card(title: "Batería", icon: "battery.100percent", tint: .green) {
            if let b = battery {
                HStack(spacing: 18) {
                    Gauge(percent: Double(b.healthPercent ?? 0) / 100, color: healthColor(b.healthPercent),
                          label: b.healthPercent.map { "\($0)%" } ?? "—", caption: "capacidad")
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 8) {
                        Row(label: "Estado", value: b.conditionES)
                        Row(label: "Ciclos", value: b.cycleCount.map { "\($0) / \(b.designCycles ?? 1000)" } ?? "—")
                        if let c = b.chargePercent { Row(label: "Carga actual", value: "\(c)%\(b.isCharging ? " ⚡︎" : "")") }
                    }
                }
                if let d = b.designCapacity, let m = b.maxCapacity {
                    Row(label: "Capacidad", value: "\(m) mAh de \(d) mAh originales")
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "powerplug.fill").font(.system(size: 40)).foregroundStyle(.green.gradient)
                    Text("Sin batería").font(.title3.bold())
                    Text("Es un Mac de sobremesa: funciona conectado a la corriente, así que no hay batería que se desgaste. Un punto a favor en el anuncio.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

func healthColor(_ p: Int?) -> Color {
    guard let p else { return .gray }
    return p >= 85 ? .green : p >= 75 ? .orange : .red
}

struct Gauge: View {
    let percent: Double
    let color: Color
    let label: String
    let caption: String
    @State private var shown = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 10)
            Circle().trim(from: 0, to: shown)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.2).delay(0.2)) { shown = percent } }
    }
}

struct SerialCard: View {
    let specs: MacSpecs
    @EnvironmentObject var model: AppModel
    @State private var peeking = false

    var body: some View {
        Card(title: "Número de serie", icon: "barcode", tint: .teal) {
            let mode = peeking ? .visible : model.serialMode
            Text(maskSerial(specs.serial, mode))
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .tracking(2)
                .blur(radius: mode == .hidden ? 6 : 0)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 40, pressing: { p in
                    withAnimation(.easeOut(duration: 0.15)) { peeking = p }
                }, perform: {})
                .help("Mantén pulsado para ver el número completo")
                .animation(.spring, value: model.serialMode)

            Picker("", selection: Binding(get: { model.serialMode }, set: { model.serialMode = $0 })) {
                ForEach(SerialMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Se aplica también al texto del anuncio. La imagen tiene su propio ajuste en «Crear anuncio». Mantén pulsado para echar un vistazo.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button { model.copy(specs.serial, "Nº de serie copiado") } label: { Label("Copiar", systemImage: "doc.on.doc") }
                Spacer()
                Button {
                    model.copy(specs.serial, "Nº de serie copiado · pégalo en la web de Apple")
                    NSWorkspace.shared.open(URL(string: "https://checkcoverage.apple.com/es/es/")!)
                } label: { Label("Comprobar cobertura", systemImage: "checkmark.shield") }
            }
            .controlSize(.small)
        }
    }
}

struct SystemCard: View {
    let specs: MacSpecs
    var body: some View {
        Card(title: "Sistema y seguridad", icon: "apple.logo", tint: .gray) {
            BigValue(value: "macOS \(specs.macOSName)", caption: "Versión \(specs.macOSVersion) (\(specs.macOSBuild))")
            Row(label: "Bloqueo de activación", value: specs.activationLock == nil ? "—" : specs.activationLock! ? "⚠︎ Activado" : "✓ Desactivado")
            Row(label: "FileVault", value: specs.fileVault == nil ? "—" : specs.fileVault! ? "Activado" : "Desactivado")
            Row(label: "Identificador", value: specs.modelIdentifier)
            if let n = specs.modelNumber { Row(label: "Referencia", value: n) }
        }
    }
}

// MARK: - Anuncio

enum Condition: String, CaseIterable, Identifiable {
    case nuevo = "Como nuevo", muyBueno = "Muy buen estado", bueno = "Buen estado", aceptable = "Aceptable"
    var id: String { rawValue }
}

struct ListingView: View {
    let specs: MacSpecs
    @EnvironmentObject var model: AppModel

    @AppStorage("cond") private var condRaw = Condition.muyBueno.rawValue
    @AppStorage("box") private var box = true
    @AppStorage("charger") private var charger = true
    @AppStorage("invoice") private var invoice = false
    @AppStorage("price") private var price = ""
    @AppStorage("negotiable") private var negotiable = false
    @AppStorage("shipping") private var shipping = true
    @AppStorage("extras") private var extras = ""
    @State private var text = ""
    @State private var edited = false

    private var options: ListingOptions {
        ListingOptions(condition: Condition(rawValue: condRaw) ?? .muyBueno, box: box, charger: charger, invoice: invoice,
                       price: price, negotiable: negotiable, shipping: shipping, extras: extras, serialMode: model.serialMode)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                SwiftUI.Section("Estado") {
                    Picker("Estado estético", selection: $condRaw) {
                        ForEach(Condition.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                }
                SwiftUI.Section("Qué incluye") {
                    Toggle("Caja original", isOn: $box)
                    Toggle(specs.battery == nil ? "Cable de corriente original" : "Cargador original", isOn: $charger)
                    Toggle("Factura de compra", isOn: $invoice)
                    TextField("Otros (funda, ratón…)", text: $extras)
                }
                SwiftUI.Section("Precio y entrega") {
                    TextField("Precio (€)", text: $price)
                    Toggle("Precio negociable", isOn: $negotiable)
                    Toggle("Hago envíos", isOn: $shipping)
                }
                SwiftUI.Section("Imagen para el anuncio") {
                    Picker("Nº de serie en la imagen", selection: Binding(get: { model.cardSerialMode }, set: { model.cardSerialMode = $0 })) {
                        ForEach(SerialMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    SpecCardView(specs: specs, serialMode: model.cardSerialMode)
                        .animation(.easeInOut, value: model.cardSerialMode)
                        .scaleEffect(0.42, anchor: .topLeading)
                        .frame(width: 540 * 0.42, height: 675 * 0.42, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity)
                    Button { model.exportCard() } label: { Label("Exportar PNG (1080×1350)", systemImage: "square.and.arrow.down") }
                        .frame(maxWidth: .infinity)
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Tu anuncio").font(.system(size: 26, weight: .bold, design: .rounded))
                VStack(alignment: .leading, spacing: 6) {
                    Text("TÍTULO").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    HStack {
                        Text(ListingBuilder.title(specs)).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Spacer()
                        Button { model.copy(ListingBuilder.title(specs), "Título copiado") } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("DESCRIPCIÓN").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Spacer()
                        if edited {
                            Button("Restablecer") { regenerate() }.buttonStyle(.link).font(.caption)
                        }
                        Text("\(text.count) caracteres").font(.caption).foregroundStyle(.tertiary)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .onChange(of: text) { _, new in edited = new != ListingBuilder.description(specs, options) }
                }
                HStack {
                    Button {
                        model.copy(ListingBuilder.title(specs) + "\n\n" + text, "Anuncio copiado")
                    } label: {
                        Label("Copiar anuncio completo", systemImage: "doc.on.clipboard.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(wallaTeal).controlSize(.large)
                    Button { model.copy(text, "Descripción copiada") } label: { Text("Solo descripción") }
                        .controlSize(.large)
                }
            }
            .padding(24)
        }
        .onAppear(perform: regenerate)
        .onChange(of: options) { _, _ in regenerate() }
    }

    private func regenerate() {
        text = ListingBuilder.description(specs, options)
        edited = false
    }
}

struct ListingOptions: Equatable {
    var condition: Condition
    var box: Bool
    var charger: Bool
    var invoice: Bool
    var price: String
    var negotiable: Bool
    var shipping: Bool
    var extras: String
    var serialMode: SerialMode
}

enum ListingBuilder {
    static func title(_ s: MacSpecs) -> String {
        var parts = [s.marketingName.replacingOccurrences(of: #"\s*\(.*\)"#, with: "", options: .regularExpression)]
        if let y = s.year { parts[0] += " \(y)" }
        if s.isAppleSilicon { parts.append(s.chipShort) }
        parts.append("\(s.ramLabel) RAM")
        parts.append("\(s.diskMarketing) SSD")
        return parts.joined(separator: " · ")
    }

    static func specLines(_ s: MacSpecs, serialMode: SerialMode) -> [String] {
        var l: [String] = []
        if s.isAppleSilicon {
            l.append("• Procesador: \(s.chip) · CPU de \(s.cpuCoresDescription)")
        } else {
            l.append("• Procesador: \(s.chip) · \(s.cpuCoresDescription)")
        }
        if let g = s.primaryGPU {
            let cores = g.cores.map { "GPU de \($0) núcleos" } ?? g.model
            l.append("• Gráfica: \(cores)\(g.vram.map { " · \($0)" } ?? "")\(g.metal.map { " · \($0)" } ?? "")")
        }
        var ram = "• Memoria: \(s.ramLabel)\(s.ramType.map { " \($0)" } ?? "")\(s.isAppleSilicon ? " unificada" : "")"
        let extra = [s.ramSpeed, s.ramBandwidth].compactMap { $0 }
        if !extra.isEmpty { ram += " (\(extra.joined(separator: " · ")))" }
        l.append(ram)
        l.append("• Almacenamiento: SSD de \(s.diskMarketing)\(s.diskSMART == "Verified" ? " (salud SMART verificada)" : "")")
        if let d = s.builtInDisplay, let k = d.kind {
            l.append("• Pantalla: \(k)\(d.pixels.map { " · \($0.replacingOccurrences(of: " x ", with: "×"))" } ?? "")")
        }
        if let b = s.battery {
            var bl = "• Batería: \(b.healthPercent.map { "\($0) % de capacidad" } ?? "—")"
            if let c = b.cycleCount { bl += " · \(c) ciclos" }
            bl += " · estado \(b.conditionES.lowercased())"
            l.append(bl)
        }
        l.append("• Sistema: macOS \(s.macOSName) \(s.macOSVersion)")
        l.append("• Modelo: \(s.modelIdentifier)\(s.modelNumber.map { " · Ref. \($0)" } ?? "")")
        if serialMode != .hidden, !s.serial.isEmpty {
            l.append("• Nº de serie: \(maskSerial(s.serial, serialMode))")
        }
        return l
    }

    static func description(_ s: MacSpecs, _ o: ListingOptions) -> String {
        var out = "Vendo \(s.marketingName) en \(o.condition.rawValue.lowercased()).\n\n"
        out += "⚙️ ESPECIFICACIONES\n" + specLines(s, serialMode: o.serialMode).joined(separator: "\n") + "\n"

        var inc: [String] = []
        if o.box { inc.append("Caja original") }
        if o.charger { inc.append(s.battery == nil ? "Cable de corriente original" : "Cargador original") }
        if o.invoice { inc.append("Factura de compra") }
        let ex = o.extras.trimmingCharacters(in: .whitespaces)
        if !ex.isEmpty { inc.append(ex.prefix(1).uppercased() + ex.dropFirst()) }
        if !inc.isEmpty { out += "\n📦 INCLUYE\n" + inc.map { "• \($0)" }.joined(separator: "\n") + "\n" }

        if s.battery == nil {
            out += "\n🔌 Equipo de sobremesa: sin batería que se desgaste.\n"
        } else if let h = s.battery?.healthPercent, h >= 90 {
            out += "\n🔋 Batería en muy buen estado (\(h) %).\n"
        }
        if s.activationLock == false {
            out += "✅ Sin bloqueo de activación: listo para que lo configures con tu cuenta.\n"
        }
        if o.serialMode != .visible {
            out += "🔎 Te enseño el número de serie completo para que compruebes el modelo y la garantía en la web de Apple.\n"
        }
        let p = o.price.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty {
            out += "\n💶 \(p.hasSuffix("€") ? p : p + " €")\(o.negotiable ? " (negociable)" : "")\n"
        } else if o.negotiable {
            out += "\n💶 Precio negociable\n"
        }
        out += o.shipping ? "🚚 Envío disponible o entrega en mano.\n" : "🤝 Solo entrega en mano.\n"
        out += "\nFicha técnica generada con WallaMac."
        return out
    }

    static func plainSpecs(_ s: MacSpecs, serialMode: SerialMode) -> String {
        title(s) + "\n" + specLines(s, serialMode: serialMode).joined(separator: "\n")
    }
}

// MARK: - Imagen exportable (540×675 pt → 1080×1350 px)

struct SpecCardView: View {
    let specs: MacSpecs
    let serialMode: SerialMode

    var body: some View {
        ZStack {
            LinearGradient(colors: [wallaDeep, wallaInk], startPoint: .top, endPoint: .bottom)
            Circle().fill(wallaTeal.opacity(0.35)).frame(width: 420).blur(radius: 90).offset(x: 180, y: -260)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    Image(systemName: specs.deviceSymbol)
                        .font(.system(size: 64, weight: .thin))
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(specs.marketingName)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .lineLimit(2).minimumScaleFactor(0.6)
                        Text([specs.year.map { "Año \($0)" }, specs.modelIdentifier].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 14, weight: .medium)).opacity(0.7)
                    }
                    .foregroundStyle(.white)
                }
                .padding(.bottom, 26)

                let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: cols, spacing: 12) {
                    Tile(icon: "cpu", label: "Procesador", value: specs.chipShort, sub: specs.cpuCoresDescription.replacingOccurrences(of: " rendimiento", with: "P").replacingOccurrences(of: " eficiencia", with: "E"))
                    Tile(icon: "square.grid.3x3.topleft.filled", label: "Gráfica",
                         value: specs.primaryGPU?.cores.map { "\($0) núcleos" } ?? (specs.primaryGPU?.model ?? "—"),
                         sub: specs.primaryGPU?.metal ?? (specs.primaryGPU?.vram ?? ""))
                    Tile(icon: "memorychip", label: "Memoria", value: specs.ramLabel,
                         sub: [specs.ramType, specs.ramSpeed].compactMap { $0 }.joined(separator: " · "))
                    Tile(icon: "internaldrive", label: "Almacenamiento", value: "\(specs.diskMarketing) SSD",
                         sub: specs.diskSMART == "Verified" ? "Salud SMART verificada" : "")
                    if let b = specs.battery {
                        Tile(icon: "battery.100percent", label: "Batería", value: b.healthPercent.map { "\($0) %" } ?? "—",
                             sub: "\(b.cycleCount.map { "\($0) ciclos · " } ?? "")\(b.conditionES)")
                    } else {
                        Tile(icon: "powerplug.fill", label: "Alimentación", value: "Sobremesa", sub: "Sin batería que desgastar")
                    }
                    Tile(icon: "apple.logo", label: "Sistema", value: "macOS \(specs.macOSName)", sub: specs.macOSVersion)
                }

                let highlights = [specs.neuralCores.map { "Neural Engine \($0) núcleos" }, specs.ramBandwidth.map { "\($0) de ancho de banda" },
                                  specs.processNode.map { "Chip de \($0)" }, specs.builtInDisplay?.kind].compactMap { $0 }
                if !highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(highlights, id: \.self) { h in
                            Label(h, systemImage: "sparkle").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.top, 22)
                }

                Spacer(minLength: 16)

                HStack {
                    if serialMode != .hidden {
                        Label(maskSerial(specs.serial, serialMode), systemImage: "barcode")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    Spacer()
                    if specs.activationLock == false {
                        Label("Sin bloqueo de activación", systemImage: "lock.open.fill").font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 14)

                HStack(spacing: 8) {
                    AppGlyph(size: 22)
                    Text("Ficha verificada con WallaMac").font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text(Date.now.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "es_ES"))))
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding(34)
        }
        .frame(width: 540, height: 675)
    }

    struct Tile: View {
        let icon: String
        let label: String
        let value: String
        let sub: String
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label(label.uppercased(), systemImage: icon)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(wallaTeal)
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(sub.isEmpty ? " " : sub).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1)))
        }
    }
}

// MARK: - Antes de vender

enum CheckStatus { case ok, warn, fail, manual }

struct CheckItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    var status: CheckStatus
    var action: (String, () -> Void)? = nil
}

func autoChecks(_ s: MacSpecs) -> [CheckItem] {
    var items: [CheckItem] = []
    if let al = s.activationLock {
        items.append(CheckItem(id: "al", title: "Bloqueo de activación desactivado",
                               detail: al ? "Buscar mi Mac sigue activo. El comprador no podrá usar el Mac hasta que lo desactives." : "Buscar mi Mac está desactivado.",
                               status: al ? .fail : .ok, action: al ? ("Abrir Ajustes", openAppleIDSettings) : nil))
    }
    items.append(CheckItem(id: "smart", title: "Disco en buen estado",
                           detail: s.diskSMART == "Verified" ? "El SSD supera la comprobación SMART." : "No se ha podido verificar la salud del disco.",
                           status: s.diskSMART == "Verified" ? .ok : .warn))
    if let b = s.battery, let h = b.healthPercent {
        items.append(CheckItem(id: "bat", title: "Batería por encima del 80 %",
                               detail: "Capacidad máxima del \(h) % con \(b.cycleCount ?? 0) ciclos.",
                               status: h >= 80 ? .ok : h >= 70 ? .warn : .fail))
    }
    return items
}

let manualChecks: [CheckItem] = [
    CheckItem(id: "backup", title: "Haz una copia de seguridad", detail: "Con Time Machine o copiando tus archivos a otro disco o a la nube.", status: .manual),
    CheckItem(id: "icloud", title: "Cierra sesión de tu cuenta de Apple", detail: "Ajustes del Sistema › tu nombre › Cerrar sesión.", status: .manual, action: ("Abrir", openAppleIDSettings)),
    CheckItem(id: "imessage", title: "Cierra sesión en Mensajes y FaceTime", detail: "En los ajustes de cada app.", status: .manual),
    CheckItem(id: "bt", title: "Desvincula tus dispositivos Bluetooth", detail: "Teclado, ratón o AirPods, si te los quedas.", status: .manual),
    CheckItem(id: "erase", title: "Borra contenidos y ajustes", detail: "Ajustes del Sistema › General › Transferir o restablecer. Hazlo al final.", status: .manual),
    CheckItem(id: "photos", title: "Límpialo y haz buenas fotos", detail: "Con luz natural. Incluye la imagen de WallaMac y una foto de \"Acerca de este Mac\".", status: .manual),
]

func readiness(_ s: MacSpecs) -> Double {
    let auto = autoChecks(s)
    let done = manualChecks.filter { UserDefaults.standard.bool(forKey: "check.\($0.id)") }.count
    let okAuto = auto.filter { $0.status == .ok }.count
    let total = auto.count + manualChecks.count
    return total == 0 ? 0 : Double(okAuto + done) / Double(total)
}

struct ChecklistView: View {
    let specs: MacSpecs
    @State private var refresh = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 22) {
                    Gauge(percent: readiness(specs), color: wallaTeal, label: "\(Int(readiness(specs) * 100))%", caption: "listo")
                        .frame(width: 110, height: 110)
                        .id(refresh)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Antes de vender").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("WallaMac comprueba lo que puede automáticamente. El resto, márcalo tú.")
                            .foregroundStyle(.secondary)
                    }
                }
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(autoChecks(specs)) { CheckRow(item: $0, onToggle: {}) }
                    }
                } label: { Label("Comprobado por WallaMac", systemImage: "wand.and.stars").font(.headline) }
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(manualChecks) { CheckRow(item: $0, onToggle: { refresh += 1 }) }
                    }
                } label: { Label("Tu lista", systemImage: "person.fill.checkmark").font(.headline) }
            }
            .padding(28)
        }
    }
}

struct CheckRow: View {
    let item: CheckItem
    let onToggle: () -> Void
    @AppStorage private var done: Bool

    init(item: CheckItem, onToggle: @escaping () -> Void) {
        self.item = item
        self.onToggle = onToggle
        _done = AppStorage(wrappedValue: false, "check.\(item.id)")
    }

    var body: some View {
        HStack(spacing: 14) {
            icon.font(.title2).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.semibold)).strikethrough(item.status == .manual && done, color: .secondary)
                Text(item.detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let a = item.action { Button(a.0, action: a.1).controlSize(.small) }
        }
        .padding(.vertical, 10).padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.status == .manual else { return }
            withAnimation(.spring(duration: 0.3)) { done.toggle() }
            onToggle()
        }
    }

    @ViewBuilder private var icon: some View {
        switch item.status {
        case .ok: Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case .warn: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .fail: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .manual: Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? wallaTeal : .secondary)
        }
    }
}

struct ReadinessMini: View {
    let specs: MacSpecs
    @EnvironmentObject var model: AppModel
    var body: some View {
        let r = readiness(specs)
        Button { model.section = .checklist } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Listo para vender").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(Int(r * 100))%").font(.caption.weight(.bold)).foregroundStyle(wallaTeal)
                }
                ProgressView(value: r).tint(wallaTeal)
            }
            .padding(10)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icono

struct AppGlyph: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [wallaTeal, wallaDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "laptopcomputer")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: -size * 0.02)
            Image(systemName: "tag.fill")
                .font(.system(size: size * 0.24, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.2))
                .rotationEffect(.degrees(-20))
                .offset(x: size * 0.25, y: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

enum IconRenderer {
    @MainActor static func render(to path: String) {
        let view = ZStack {
            AppGlyph(size: 824).shadow(color: .black.opacity(0.3), radius: 20, y: 12)
        }
        .frame(width: 1024, height: 1024)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
