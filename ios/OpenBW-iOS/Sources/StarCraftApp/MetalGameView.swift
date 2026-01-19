// MetalGameView.swift
// MetalKit-based game view that integrates with OpenBW game runner

import SwiftUI
import MetalKit
// OpenBWBridge types are available via bridging header

/// UIViewRepresentable wrapper for MTKView with OpenBW integration
struct MetalGameView: UIViewRepresentable {
    @ObservedObject var gameController: GameController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 24  // StarCraft's native frame rate
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.isMultipleTouchEnabled = true

        context.coordinator.mtkView = mtkView

        // Set up touch input manager
        context.coordinator.setupTouchInput(on: mtkView)

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Update view if needed
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalGameView
        weak var mtkView: MTKView?
        var touchInputManager: TouchInputManager?

        init(_ parent: MetalGameView) {
            self.parent = parent
        }

        func setupTouchInput(on view: UIView) {
            touchInputManager = TouchInputManager(gameController: parent.gameController)
            touchInputManager?.attachToView(view)

            // Handle selection box updates
            touchInputManager?.onSelectionBoxUpdate = { [weak self] rect in
                DispatchQueue.main.async {
                    self?.parent.gameController.selectionRect = rect
                }
            }

            // Handle context menu
            touchInputManager?.onShowContextMenu = { [weak self] location in
                DispatchQueue.main.async {
                    self?.parent.gameController.showContextMenu(at: location)
                }
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle resize
        }

        func draw(in view: MTKView) {
            guard let gameRunner = parent.gameController.gameRunner else { return }

            // Advance game state
            gameRunner.tick()

            // Render to view
            gameRunner.render(to: view)
        }
    }
}

/// Swift representation of unit info
struct UnitInfoModel: Identifiable {
    let id: Int
    let typeId: Int
    let typeName: String
    let owner: Int
    let x: Float
    let y: Float
    let health: Int
    let maxHealth: Int
    let shields: Int
    let maxShields: Int
    let energy: Int
    let maxEnergy: Int
    let isBuilding: Bool
    let isWorker: Bool
    let canAttack: Bool
    let canMove: Bool

    var healthPercent: Double {
        maxHealth > 0 ? Double(health) / Double(maxHealth) : 0
    }

    var shieldPercent: Double {
        maxShields > 0 ? Double(shields) / Double(maxShields) : 0
    }

    var energyPercent: Double {
        maxEnergy > 0 ? Double(energy) / Double(maxEnergy) : 0
    }
}

/// Pending command mode for RTS controls
enum CommandMode {
    case none
    case move
    case attack
    case patrol
}

/// Game controller that manages the OpenBW engine
class GameController: ObservableObject {
    @Published var isInitialized = false
    @Published var isRunning = false
    @Published var minerals: Int = 0
    @Published var gas: Int = 0
    @Published var supply: Int = 0
    @Published var supplyMax: Int = 0
    @Published var error: String?
    @Published var selectionRect: CGRect?
    @Published var showingContextMenu = false
    @Published var contextMenuLocation: CGPoint = .zero
    @Published var selectedUnits: [UnitInfoModel] = []
    @Published var commandMode: CommandMode = .none

    var gameRunner: OpenBWGameRunner?
    private let engine = OpenBWEngine.shared

    func initialize(assetPath: String) {
        do {
            try engine.initialize(withAssetPath: assetPath)
            gameRunner = engine.gameRunner
            isInitialized = true
            setupCallbacks()
        } catch let initError {
            error = initError.localizedDescription
        }
    }

    func startGame(mapPath: String, race: Int = 0, difficulty: Int = 1) {
        guard let runner = gameRunner else { return }

        do {
            try runner.startGame(withMap: mapPath, playerRace: Int32(race), aiDifficulty: Int32(difficulty))
            isRunning = true
        } catch let startError {
            error = startError.localizedDescription
        }
    }

    func pause() {
        gameRunner?.pause()
        isRunning = false
    }

    func resume() {
        gameRunner?.resume()
        isRunning = true
    }

    func stop() {
        gameRunner?.stop()
        isRunning = false
    }

    private func setupCallbacks() {
        gameRunner?.onFrameUpdate = { [weak self] frame, minerals, gas, supply, supplyMax in
            DispatchQueue.main.async {
                self?.minerals = Int(minerals)
                self?.gas = Int(gas)
                self?.supply = Int(supply)
                self?.supplyMax = Int(supplyMax)
                self?.updateSelectedUnits()
            }
        }
    }

    func updateSelectedUnits() {
        guard let runner = gameRunner,
              let infos = runner.getSelectedUnitsInfo() else {
            selectedUnits = []
            return
        }

        selectedUnits = infos.map { info in
            UnitInfoModel(
                id: Int(info.unitId),
                typeId: Int(info.typeId),
                typeName: info.typeName,
                owner: Int(info.owner),
                x: info.x,
                y: info.y,
                health: Int(info.health),
                maxHealth: Int(info.maxHealth),
                shields: Int(info.shields),
                maxShields: Int(info.maxShields),
                energy: Int(info.energy),
                maxEnergy: Int(info.maxEnergy),
                isBuilding: info.isBuilding,
                isWorker: info.isWorker,
                canAttack: info.canAttack,
                canMove: info.canMove
            )
        }
    }

    // MARK: - Camera Control

    func moveCamera(dx: CGFloat, dy: CGFloat) {
        guard let runner = gameRunner else { return }
        var x: Float = 0, y: Float = 0
        runner.getCameraX(&x, y: &y)
        runner.setCameraX(x + Float(dx), y: y + Float(dy))
    }

    func setZoom(_ zoom: CGFloat) {
        gameRunner?.setZoom(Float(zoom))
    }

    // MARK: - Touch Input

    func handleTap(at point: CGPoint, in viewSize: CGSize) {
        // TODO: Implement unit selection once Swift bridging is fixed
        // For now, touch handling is stubbed
        print("Tap at \(point)")
    }

    func handleDrag(from start: CGPoint, to end: CGPoint, in viewSize: CGSize) {
        // TODO: Implement box selection once Swift bridging is fixed
        print("Drag from \(start) to \(end)")
    }

    func showContextMenu(at location: CGPoint) {
        contextMenuLocation = location
        showingContextMenu = true
    }

    func hideContextMenu() {
        showingContextMenu = false
    }

    // MARK: - Unit Commands

    func moveSelectedUnits(to point: CGPoint) {
        guard let runner = gameRunner else { return }
        runner.moveSelectedTo(x: point.x, y: point.y)
        commandMode = .none
    }

    func attackMoveUnits(to point: CGPoint) {
        guard let runner = gameRunner else { return }
        runner.attackMoveTo(x: point.x, y: point.y)
        commandMode = .none
    }

    func stopSelectedUnits() {
        guard let runner = gameRunner else { return }
        runner.stopSelected()
    }

    func holdPosition() {
        guard let runner = gameRunner else { return }
        runner.holdPosition()
    }

    func patrolUnits(to point: CGPoint) {
        guard let runner = gameRunner else { return }
        runner.patrolTo(x: point.x, y: point.y)
        commandMode = .none
    }

    func centerCamera(on point: CGPoint) {
        guard let runner = gameRunner else { return }
        runner.setCameraX(Float(point.x), y: Float(point.y))
    }

    func handlePendingCommand(at point: CGPoint) {
        switch commandMode {
        case .none:
            break
        case .move:
            moveSelectedUnits(to: point)
        case .attack:
            attackMoveUnits(to: point)
        case .patrol:
            patrolUnits(to: point)
        }
    }

    func setCommandMode(_ mode: CommandMode) {
        commandMode = mode
    }

    func cancelCommandMode() {
        commandMode = .none
    }

    func getCurrentZoom() -> CGFloat {
        return CGFloat(gameRunner?.zoom() ?? 1.0)
    }
}

/// Complete game screen with HUD and touch overlays
struct GameScreen: View {
    @StateObject private var gameController = GameController()
    @State private var showingAssetPicker = true
    @State private var assetPath: String = ""

    var body: some View {
        ZStack {
            if gameController.isInitialized {
                // Game view
                MetalGameView(gameController: gameController)
                    .ignoresSafeArea()

                // Show Start Game button if not running
                if !gameController.isRunning && gameController.error == nil {
                    VStack {
                        Spacer()
                        Button("Start Game") {
                            // Try to start a game with a built-in map
                            gameController.startGame(mapPath: "maps/(2)Challenger.scm", race: 0, difficulty: 1)
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.title)
                        .padding()
                        Spacer()
                    }
                }

                // Selection box overlay
                if let rect = gameController.selectionRect {
                    SelectionBoxOverlay(rect: rect)
                }

                // Context menu overlay
                if gameController.showingContextMenu {
                    ContextMenuOverlay(
                        location: gameController.contextMenuLocation,
                        onCommand: { command in
                            handleContextMenuCommand(command)
                        },
                        onDismiss: {
                            gameController.hideContextMenu()
                        }
                    )
                }

                // HUD overlay
                VStack {
                    // Top bar
                    HStack {
                        ResourceDisplay(
                            minerals: gameController.minerals,
                            gas: gameController.gas,
                            supply: gameController.supply,
                            supplyMax: gameController.supplyMax
                        )
                        Spacer()
                        Button(gameController.isRunning ? "Pause" : "Resume") {
                            if gameController.isRunning {
                                gameController.pause()
                            } else {
                                gameController.resume()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()

                    Spacer()

                    // Bottom controls
                    HStack(alignment: .bottom, spacing: 8) {
                        MinimapView(gameController: gameController)
                            .frame(width: 150, height: 150)

                        // Unit info panel (center)
                        if !gameController.selectedUnits.isEmpty {
                            UnitInfoPanel(units: gameController.selectedUnits)
                                .frame(maxWidth: .infinity)
                        } else {
                            Spacer()
                        }

                        CommandPalette(gameController: gameController)
                            .frame(width: 200)
                    }
                    .padding()
                }
            } else {
                // Asset path input
                AssetPathInputView(
                    assetPath: $assetPath,
                    error: gameController.error,
                    onInitialize: {
                        gameController.initialize(assetPath: assetPath)
                    }
                )
            }
        }
        .onAppear {
            // Try default paths
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
            let bundlePath = Bundle.main.resourcePath ?? ""
            if hasRequiredMPQs(in: bundlePath) {
                assetPath = bundlePath
            } else {
                assetPath = documentsPath
            }
        }
    }

    private func hasRequiredMPQs(in path: String) -> Bool {
        guard !path.isEmpty,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return false
        }
        let lowercased = Set(contents.map { $0.lowercased() })
        let required = ["stardat.mpq", "broodat.mpq", "patch_rt.mpq"]
        return required.allSatisfy { lowercased.contains($0) }
    }

    private func handleContextMenuCommand(_ command: ContextMenuCommand) {
        gameController.hideContextMenu()

        switch command {
        case .move:
            gameController.moveSelectedUnits(to: gameController.contextMenuLocation)
        case .attack:
            gameController.attackMoveUnits(to: gameController.contextMenuLocation)
        case .patrol:
            // TODO: Implement patrol command
            break
        case .hold:
            // Issue hold position command
            break
        case .stop:
            // Issue stop command
            break
        }
    }
}

// MARK: - Selection Box Overlay

struct SelectionBoxOverlay: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .stroke(Color.green, lineWidth: 2)
            .background(Color.green.opacity(0.1))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Context Menu

enum ContextMenuCommand {
    case move
    case attack
    case patrol
    case hold
    case stop
}

struct ContextMenuOverlay: View {
    let location: CGPoint
    let onCommand: (ContextMenuCommand) -> Void
    let onDismiss: () -> Void

    private let menuRadius: CGFloat = 80
    private let buttonRadius: CGFloat = 30

    var body: some View {
        ZStack {
            // Dismiss area
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Radial menu
            ZStack {
                // Move - top
                ContextMenuButton(
                    icon: "arrow.right",
                    label: "Move",
                    angle: -.pi / 2,
                    radius: menuRadius
                ) {
                    onCommand(.move)
                }

                // Attack - right
                ContextMenuButton(
                    icon: "scope",
                    label: "Attack",
                    angle: 0,
                    radius: menuRadius
                ) {
                    onCommand(.attack)
                }

                // Patrol - bottom
                ContextMenuButton(
                    icon: "arrow.triangle.swap",
                    label: "Patrol",
                    angle: .pi / 2,
                    radius: menuRadius
                ) {
                    onCommand(.patrol)
                }

                // Hold - left
                ContextMenuButton(
                    icon: "hand.raised.fill",
                    label: "Hold",
                    angle: .pi,
                    radius: menuRadius
                ) {
                    onCommand(.hold)
                }

                // Stop - center
                Button(action: { onCommand(.stop) }) {
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "stop.fill")
                                .foregroundColor(.white)
                        )
                }
            }
            .position(location)
        }
    }
}

struct ContextMenuButton: View {
    let icon: String
    let label: String
    let angle: CGFloat
    let radius: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: icon)
                            .foregroundColor(.white)
                    )
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
        }
        .offset(
            x: cos(angle) * radius,
            y: sin(angle) * radius
        )
    }
}

// MARK: - Minimap with Touch Navigation

struct MinimapView: View {
    @ObservedObject var gameController: GameController
    @State private var minimapImage: UIImage?
    @State private var lastUpdateFrame: Int = -1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Minimap background
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        Rectangle()
                            .stroke(Color.gray, lineWidth: 2)
                    )

                // Actual minimap image
                if let image = minimapImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fill)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleMinimapTouch(at: value.location, in: geometry.size)
                    }
            )
            .onAppear {
                updateMinimap()
            }
            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                // Update minimap every 100ms if game is running
                if gameController.isRunning {
                    updateMinimap()
                }
            }
        }
    }

    private func updateMinimap() {
        guard let runner = gameController.gameRunner else { return }

        // Get minimap RGBA data
        var width: Int32 = 0
        var height: Int32 = 0

        guard let pixels = runner.getMinimapRGBA(&width, height: &height) else { return }
        defer { free(pixels) }

        let w = Int(width)
        let h = Int(height)
        guard w > 0 && h > 0 else { return }

        // Create UIImage from RGBA data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: UnsafeMutableRawPointer(pixels),
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return }

        guard let cgImage = context.makeImage() else { return }

        DispatchQueue.main.async {
            self.minimapImage = UIImage(cgImage: cgImage)
        }
    }

    private func handleMinimapTouch(at point: CGPoint, in size: CGSize) {
        guard let runner = gameController.gameRunner else { return }

        // Convert minimap coordinates to world coordinates
        let mapWidth = CGFloat(runner.mapWidth)
        let mapHeight = CGFloat(runner.mapHeight)

        let worldX = (point.x / size.width) * mapWidth
        let worldY = (point.y / size.height) * mapHeight

        runner.setCameraX(Float(worldX), y: Float(worldY))
    }
}

// MARK: - Command Palette

struct CommandPalette: View {
    @ObservedObject var gameController: GameController

    // Command definitions for 3x3 grid
    private let commands: [(icon: String, label: String, key: String)] = [
        ("arrow.right", "Move", "M"),
        ("scope", "Attack", "A"),
        ("hand.raised", "Hold", "H"),
        ("arrow.triangle.swap", "Patrol", "P"),
        ("stop.fill", "Stop", "S"),
        ("building.2", "Build", "B"),
        ("person.badge.plus", "Train", "T"),
        ("bolt.fill", "Ability", "Q"),
        ("gearshape", "Options", "O")
    ]

    var body: some View {
        VStack(spacing: 8) {
            // Show active command mode indicator
            if gameController.commandMode != .none {
                Text(commandModeText)
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(4)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                    CommandButton(
                        icon: command.icon,
                        label: command.label,
                        hotkey: command.key,
                        isActive: isCommandActive(index)
                    ) {
                        handleCommand(index)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }

    private var commandModeText: String {
        switch gameController.commandMode {
        case .none: return ""
        case .move: return "Click to Move"
        case .attack: return "Click to Attack"
        case .patrol: return "Click to Patrol"
        }
    }

    private func isCommandActive(_ index: Int) -> Bool {
        switch (index, gameController.commandMode) {
        case (0, .move): return true
        case (1, .attack): return true
        case (3, .patrol): return true
        default: return false
        }
    }

    private func handleCommand(_ index: Int) {
        switch index {
        case 0: // Move - set mode, wait for click
            if gameController.commandMode == .move {
                gameController.cancelCommandMode()
            } else {
                gameController.setCommandMode(.move)
            }
        case 1: // Attack - set mode, wait for click
            if gameController.commandMode == .attack {
                gameController.cancelCommandMode()
            } else {
                gameController.setCommandMode(.attack)
            }
        case 2: // Hold - immediate command
            gameController.holdPosition()
        case 3: // Patrol - set mode, wait for click
            if gameController.commandMode == .patrol {
                gameController.cancelCommandMode()
            } else {
                gameController.setCommandMode(.patrol)
            }
        case 4: // Stop - immediate command
            gameController.stopSelectedUnits()
        case 5: // Build - TODO: show build menu
            print("Build menu - not yet implemented")
        case 6: // Train - TODO: show train menu based on selected building
            print("Train menu - not yet implemented")
        case 7: // Ability - TODO: show ability menu
            print("Ability menu - not yet implemented")
        case 8: // Options - TODO: show options
            print("Options menu - not yet implemented")
        default:
            break
        }
    }
}

struct CommandButton: View {
    let icon: String
    let label: String
    let hotkey: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(isActive ? Color.yellow.opacity(0.4) : Color.gray.opacity(0.3))
                    .overlay(
                        Rectangle()
                            .stroke(isActive ? Color.yellow : Color.gray, lineWidth: isActive ? 2 : 1)
                    )

                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                    Text(hotkey)
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(isActive ? .yellow : .white)
            }
            .frame(height: 50)
        }
    }
}

// MARK: - Asset Path Input

struct AssetPathInputView: View {
    @Binding var assetPath: String
    let error: String?
    let onInitialize: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("StarCraft iOS")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Enter the path to your StarCraft data files")
                .foregroundColor(.secondary)

            TextField("Asset Path", text: $assetPath)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button("Initialize") {
                onInitialize()
            }
            .buttonStyle(.borderedProminent)
            .disabled(assetPath.isEmpty)

            if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }

            Text("Required files: STARDAT.MPQ, BROODAT.MPQ, patch_rt.mpq")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct ResourceDisplay: View {
    let minerals: Int
    let gas: Int
    let supply: Int
    let supplyMax: Int

    var body: some View {
        HStack(spacing: 16) {
            Label("\(minerals)", systemImage: "diamond.fill")
                .foregroundColor(.cyan)
            Label("\(gas)", systemImage: "flame.fill")
                .foregroundColor(.green)
            Label("\(supply)/\(supplyMax)", systemImage: "person.2.fill")
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }
}

// MARK: - Unit Info Panel

struct UnitInfoPanel: View {
    let units: [UnitInfoModel]

    var body: some View {
        VStack(spacing: 4) {
            if units.count == 1, let unit = units.first {
                // Single unit display
                SingleUnitInfo(unit: unit)
            } else {
                // Multiple units display
                MultipleUnitsInfo(units: units)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }
}

struct SingleUnitInfo: View {
    let unit: UnitInfoModel

    var body: some View {
        VStack(spacing: 6) {
            // Unit name
            Text(unit.typeName)
                .font(.headline)
                .foregroundColor(.white)

            // Health bar
            StatBar(
                label: "HP",
                current: unit.health,
                max: unit.maxHealth,
                color: healthColor(for: unit.healthPercent)
            )

            // Shield bar (if applicable)
            if unit.maxShields > 0 {
                StatBar(
                    label: "Shield",
                    current: unit.shields,
                    max: unit.maxShields,
                    color: .cyan
                )
            }

            // Energy bar (if applicable)
            if unit.energy > 0 {
                StatBar(
                    label: "Energy",
                    current: unit.energy,
                    max: unit.maxEnergy,
                    color: .purple
                )
            }

            // Unit capabilities
            HStack(spacing: 8) {
                if unit.canAttack {
                    Image(systemName: "scope")
                        .foregroundColor(.red)
                }
                if unit.canMove {
                    Image(systemName: "arrow.right")
                        .foregroundColor(.green)
                }
                if unit.isWorker {
                    Image(systemName: "hammer.fill")
                        .foregroundColor(.yellow)
                }
                if unit.isBuilding {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.gray)
                }
            }
            .font(.caption)
        }
        .frame(minWidth: 120)
    }

    private func healthColor(for percent: Double) -> Color {
        if percent > 0.66 { return .green }
        if percent > 0.33 { return .yellow }
        return .red
    }
}

struct MultipleUnitsInfo: View {
    let units: [UnitInfoModel]

    // Group units by type
    private var groupedUnits: [(typeName: String, count: Int, avgHealth: Double)] {
        var groups: [Int: (name: String, count: Int, totalHealth: Double, totalMaxHealth: Double)] = [:]

        for unit in units {
            if var group = groups[unit.typeId] {
                group.count += 1
                group.totalHealth += Double(unit.health)
                group.totalMaxHealth += Double(unit.maxHealth)
                groups[unit.typeId] = group
            } else {
                groups[unit.typeId] = (
                    name: unit.typeName,
                    count: 1,
                    totalHealth: Double(unit.health),
                    totalMaxHealth: Double(unit.maxHealth)
                )
            }
        }

        return groups.values.map { group in
            let avgHealth = group.totalMaxHealth > 0 ? group.totalHealth / group.totalMaxHealth : 0
            return (typeName: group.name, count: group.count, avgHealth: avgHealth)
        }.sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(units.count) units selected")
                .font(.headline)
                .foregroundColor(.white)

            // Show unit type breakdown
            ForEach(Array(groupedUnits.prefix(4).enumerated()), id: \.offset) { _, group in
                HStack {
                    Text("\(group.count)x \(group.typeName)")
                        .font(.caption)
                        .foregroundColor(.white)
                    Spacer()
                    // Health indicator
                    Circle()
                        .fill(healthColor(for: group.avgHealth))
                        .frame(width: 8, height: 8)
                }
            }

            if groupedUnits.count > 4 {
                Text("+ \(groupedUnits.count - 4) more types")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .frame(minWidth: 150)
    }

    private func healthColor(for percent: Double) -> Color {
        if percent > 0.66 { return .green }
        if percent > 0.33 { return .yellow }
        return .red
    }
}

struct StatBar: View {
    let label: String
    let current: Int
    let max: Int
    let color: Color

    private var percent: Double {
        max > 0 ? Double(current) / Double(max) : 0
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(current)/\(max)")
                    .font(.caption2)
                    .foregroundColor(.white)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))

                    // Filled portion
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percent))
                }
            }
            .frame(height: 6)
            .cornerRadius(3)
        }
    }
}

#Preview {
    GameScreen()
}
