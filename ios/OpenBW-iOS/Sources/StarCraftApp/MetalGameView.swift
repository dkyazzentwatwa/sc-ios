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
        var lastViewportSize: CGSize = .zero

        init(_ parent: MetalGameView) {
            self.parent = parent
        }

        /// Updates the game viewport size in points (logical coordinates).
        ///
        /// All coordinates in the game system use points, not pixels, for resolution independence.
        /// This means the same coordinate values work across devices with different pixel densities.
        ///
        /// - Parameter size: The viewport size in points from view.bounds.size
        private func updateViewportIfNeeded(size: CGSize) {
            guard size.width > 0 && size.height > 0 else { return }
            guard let runner = parent.gameController.gameRunner else { return }

            // Only update if size actually changed
            if lastViewportSize != size {
                // Set viewport in points (logical coordinates)
                runner.setViewportWidth(Float(size.width), height: Float(size.height))
                lastViewportSize = size
            }
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
            // Update viewport dimensions when view size changes
            // Use bounds size (points) instead of drawable size (pixels) for proper scaling
            updateViewportIfNeeded(size: view.bounds.size)
        }

        func draw(in view: MTKView) {
            guard let gameRunner = parent.gameController.gameRunner else { return }

            // Ensure viewport is set (handles initial setup and rotation)
            // Use bounds size (points) instead of drawable size (pixels)
            updateViewportIfNeeded(size: view.bounds.size)

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
    @Published var showingBuildMenu = false
    @Published var showingTrainMenu = false
    @Published var showingAbilityMenu = false
    @Published var buildPlacementMode = false
    @Published var pendingBuildingType: Int = 0
    @Published var pendingAbilityId: Int = 0
    @Published var abilityTargetMode: Int = 0  // 0=none, 1=ground, 2=unit
    @Published var controlGroupSizes: [Int] = Array(repeating: 0, count: 10)
    @Published var rallyPointMode = false

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

        // Scale pan delta by inverse zoom for natural panning feel
        // When zoomed in, camera moves less per screen pixel
        // When zoomed out, camera moves more per screen pixel
        let zoom = runner.zoom()
        let scaledDx = Float(dx) / zoom
        let scaledDy = Float(dy) / zoom

        runner.setCameraX(x + scaledDx, y: y + scaledDy)
    }

    func setZoom(_ zoom: CGFloat) {
        gameRunner?.setZoom(Float(zoom))
    }

    // MARK: - Touch Input

    func handleTap(at point: CGPoint, in viewSize: CGSize) {
        guard let runner = gameRunner else { return }

        // If in build placement mode, place the building
        if buildPlacementMode {
            placeBuildingAt(point)
            return
        }

        // If in ability targeting mode, use the ability
        if abilityTargetMode == 1 {
            // Ground targeting
            useAbilityOnGround(at: point)
            return
        } else if abilityTargetMode == 2 {
            // Unit targeting - select unit first, then if it's an enemy, cast on it
            // For now, try to cast on unit at location
            // TODO: Get unit ID at location for proper unit targeting
            runner.selectUnitAt(x: point.x, y: point.y)
            // For now, use ground position (imperfect but functional)
            gameRunner?.useAbility(onGround: Int32(pendingAbilityId), atX: point.x, y: point.y)
            pendingAbilityId = 0
            abilityTargetMode = 0
            return
        }

        // If in rally point mode, set rally point
        if rallyPointMode {
            setRallyPoint(at: point)
            return
        }

        // If there's a pending command mode, execute it instead of selecting
        if commandMode != .none {
            handlePendingCommand(at: point)
            return
        }

        // Select unit at tap location
        runner.selectUnitAt(x: point.x, y: point.y)
        updateSelectedUnits()
    }

    func handleDrag(from start: CGPoint, to end: CGPoint, in viewSize: CGSize) {
        guard let runner = gameRunner else { return }

        // Create selection rectangle
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        // Box select units in rectangle
        runner.selectUnits(in: rect)
        updateSelectedUnits()
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

    // MARK: - Building Commands

    func startBuildPlacement(buildingType: Int) {
        pendingBuildingType = buildingType
        buildPlacementMode = true
        showingBuildMenu = false
    }

    func placeBuildingAt(_ point: CGPoint) {
        guard let runner = gameRunner, buildPlacementMode else { return }
        runner.buildStructure(Int32(pendingBuildingType), atX: point.x, y: point.y)
        buildPlacementMode = false
        pendingBuildingType = 0
    }

    func cancelBuildPlacement() {
        buildPlacementMode = false
        pendingBuildingType = 0
    }

    func trainUnit(_ unitType: Int) {
        guard let runner = gameRunner else { return }
        runner.trainUnit(Int32(unitType))
        showingTrainMenu = false
    }

    // MARK: - Ability Commands

    func getAvailableAbilities() -> [[String: Any]] {
        guard let runner = gameRunner else { return [] }
        return runner.getAvailableAbilities() as? [[String: Any]] ?? []
    }

    func useAbility(_ abilityId: Int, targetType: Int) {
        if targetType == 0 {
            // No-target ability - use immediately
            gameRunner?.useAbility(Int32(abilityId))
            showingAbilityMenu = false
        } else {
            // Targeting ability - enter targeting mode
            pendingAbilityId = abilityId
            abilityTargetMode = targetType
            showingAbilityMenu = false
        }
    }

    func useAbilityOnGround(at point: CGPoint) {
        guard pendingAbilityId != 0 && abilityTargetMode == 1 else { return }
        gameRunner?.useAbility(onGround: Int32(pendingAbilityId), atX: point.x, y: point.y)
        pendingAbilityId = 0
        abilityTargetMode = 0
    }

    func useAbilityOnUnit(targetId: Int) {
        guard pendingAbilityId != 0 && abilityTargetMode == 2 else { return }
        gameRunner?.useAbility(onUnit: Int32(pendingAbilityId), targetUnitId: Int32(targetId))
        pendingAbilityId = 0
        abilityTargetMode = 0
    }

    func cancelAbilityTargeting() {
        pendingAbilityId = 0
        abilityTargetMode = 0
    }

    func hasAbilities() -> Bool {
        return !getAvailableAbilities().isEmpty
    }

    // MARK: - Control Groups

    func assignControlGroup(_ group: Int) {
        guard let runner = gameRunner else { return }
        runner.assignControlGroup(Int32(group))
        updateControlGroupSizes()
    }

    func addToControlGroup(_ group: Int) {
        guard let runner = gameRunner else { return }
        runner.add(toControlGroup: Int32(group))
        updateControlGroupSizes()
    }

    func selectControlGroup(_ group: Int) {
        guard let runner = gameRunner else { return }
        runner.selectControlGroup(Int32(group))
        updateSelectedUnits()
        updateControlGroupSizes()
    }

    func updateControlGroupSizes() {
        guard let runner = gameRunner else { return }
        for i in 0..<10 {
            controlGroupSizes[i] = Int(runner.getControlGroupSize(Int32(i)))
        }
    }

    // MARK: - Rally Points

    func setRallyPoint(at point: CGPoint) {
        guard let runner = gameRunner else { return }
        runner.setRallyPointAtX(point.x, y: point.y)
        rallyPointMode = false
    }

    func enterRallyPointMode() {
        rallyPointMode = true
    }

    func cancelRallyPointMode() {
        rallyPointMode = false
    }

    // MARK: - Menu State

    func hasSelectedWorker() -> Bool {
        return selectedUnits.contains { $0.isWorker }
    }

    func hasSelectedProductionBuilding() -> Bool {
        return selectedUnits.contains { $0.isBuilding }
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

                    // Control group bar
                    ControlGroupBar(gameController: gameController)
                        .padding(.horizontal)

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

                    // Build menu overlay
                    if gameController.showingBuildMenu {
                        BuildMenuView(gameController: gameController)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Train menu overlay
                    if gameController.showingTrainMenu {
                        TrainMenuView(gameController: gameController)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Ability menu overlay
                    if gameController.showingAbilityMenu {
                        AbilityMenuView(gameController: gameController)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Ability targeting mode indicator
                    if gameController.abilityTargetMode > 0 {
                        VStack {
                            Text(gameController.abilityTargetMode == 1 ? "Click ground to cast" : "Click target unit")
                                .font(.headline)
                                .foregroundColor(.cyan)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                            Button("Cancel") {
                                gameController.cancelAbilityTargeting()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .position(x: UIScreen.main.bounds.width / 2, y: 100)
                    }

                    // Build placement mode indicator
                    if gameController.buildPlacementMode {
                        VStack {
                            Text("Tap to place building")
                                .font(.headline)
                                .foregroundColor(.yellow)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                            Button("Cancel") {
                                gameController.cancelBuildPlacement()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .position(x: UIScreen.main.bounds.width / 2, y: 100)
                    }

                    // Rally point mode indicator
                    if gameController.rallyPointMode {
                        VStack {
                            Text("Tap to set rally point")
                                .font(.headline)
                                .foregroundColor(.orange)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                            Button("Cancel") {
                                gameController.cancelRallyPointMode()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .position(x: UIScreen.main.bounds.width / 2, y: 100)
                    }
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
        case 5: // Build - show build menu if worker selected
            if gameController.hasSelectedWorker() {
                gameController.showingBuildMenu.toggle()
                gameController.showingTrainMenu = false
            }
        case 6: // Train - show train menu if building selected
            if gameController.hasSelectedProductionBuilding() {
                gameController.showingTrainMenu.toggle()
                gameController.showingBuildMenu = false
            }
        case 7: // Ability - show ability menu if unit has abilities
            if gameController.hasAbilities() {
                gameController.showingAbilityMenu.toggle()
                gameController.showingBuildMenu = false
                gameController.showingTrainMenu = false
            }
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

// MARK: - Build Menu

struct BuildMenuView: View {
    @ObservedObject var gameController: GameController

    // Terran buildings with their type IDs
    private let terranBuildings: [(name: String, typeId: Int, minerals: Int, gas: Int)] = [
        ("Supply Depot", 120, 100, 0),
        ("Barracks", 122, 150, 0),
        ("Refinery", 121, 100, 0),
        ("Engineering Bay", 133, 125, 0),
        ("Bunker", 136, 100, 0),
        ("Missile Turret", 135, 75, 0),
        ("Academy", 123, 150, 0),
        ("Factory", 124, 200, 100),
        ("Armory", 134, 100, 50)
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Build")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { gameController.showingBuildMenu = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(terranBuildings, id: \.typeId) { building in
                    BuildingButton(
                        name: building.name,
                        minerals: building.minerals,
                        gas: building.gas,
                        canAfford: gameController.minerals >= building.minerals && gameController.gas >= building.gas
                    ) {
                        gameController.startBuildPlacement(buildingType: building.typeId)
                    }
                }
            }

            if gameController.buildPlacementMode {
                Text("Tap to place building")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .frame(width: 280)
    }
}

struct BuildingButton: View {
    let name: String
    let minerals: Int
    let gas: Int
    let canAfford: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "building.2.fill")
                    .font(.title3)
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.cyan)
                    Text("\(minerals)")
                        .font(.caption2)
                    if gas > 0 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                        Text("\(gas)")
                            .font(.caption2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(canAfford ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
            .cornerRadius(6)
            .foregroundColor(canAfford ? .white : .gray)
        }
        .disabled(!canAfford)
    }
}

// MARK: - Train Menu

struct TrainMenuView: View {
    @ObservedObject var gameController: GameController

    // Get trainable units based on selected building type
    private var trainableUnits: [(name: String, typeId: Int, minerals: Int, gas: Int)] {
        // Check first selected building type
        guard let building = gameController.selectedUnits.first(where: { $0.isBuilding }) else {
            return []
        }

        // Return units based on building type
        switch building.typeId {
        case 122: // Barracks
            return [
                ("Marine", 0, 50, 0),
                ("Firebat", 32, 50, 25),
                ("Medic", 34, 50, 25)
            ]
        case 117: // Command Center
            return [
                ("SCV", 7, 50, 0)
            ]
        case 124: // Factory
            return [
                ("Vulture", 2, 75, 0),
                ("Tank", 5, 150, 100),
                ("Goliath", 3, 100, 50)
            ]
        case 125: // Starport
            return [
                ("Wraith", 8, 150, 100),
                ("Dropship", 11, 100, 100),
                ("Science Vessel", 9, 100, 225),
                ("Battlecruiser", 12, 400, 300)
            ]
        default:
            return []
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Train")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { gameController.showingTrainMenu = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }

            if trainableUnits.isEmpty {
                Text("No units available")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(trainableUnits, id: \.typeId) { unit in
                        TrainButton(
                            name: unit.name,
                            minerals: unit.minerals,
                            gas: unit.gas,
                            canAfford: gameController.minerals >= unit.minerals && gameController.gas >= unit.gas
                        ) {
                            gameController.trainUnit(unit.typeId)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .frame(width: 220)
    }
}

struct TrainButton: View {
    let name: String
    let minerals: Int
    let gas: Int
    let canAfford: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "person.fill")
                    .font(.title3)
                Text(name)
                    .font(.caption2)
                HStack(spacing: 4) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.cyan)
                    Text("\(minerals)")
                        .font(.caption2)
                    if gas > 0 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                        Text("\(gas)")
                            .font(.caption2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(canAfford ? Color.green.opacity(0.3) : Color.gray.opacity(0.2))
            .cornerRadius(6)
            .foregroundColor(canAfford ? .white : .gray)
        }
        .disabled(!canAfford)
    }
}

// MARK: - Ability Menu

struct AbilityMenuView: View {
    @ObservedObject var gameController: GameController

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Abilities")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { gameController.showingAbilityMenu = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }

            let abilities = gameController.getAvailableAbilities()

            if abilities.isEmpty {
                Text("No abilities available")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 6) {
                    ForEach(abilities.indices, id: \.self) { index in
                        let ability = abilities[index]
                        AbilityButton(
                            name: ability["name"] as? String ?? "Unknown",
                            energyCost: ability["energyCost"] as? Int ?? 0,
                            targetType: ability["targetType"] as? Int ?? 0,
                            hasEnergy: true, // TODO: check unit energy
                            action: {
                                let abilityId = ability["id"] as? Int ?? 0
                                let targetType = ability["targetType"] as? Int ?? 0
                                gameController.useAbility(abilityId, targetType: targetType)
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.9))
        .cornerRadius(12)
        .frame(width: 220)
    }
}

struct AbilityButton: View {
    let name: String
    let energyCost: Int
    let targetType: Int
    let hasEnergy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: iconForAbility(name))
                    .font(.title3)
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                if energyCost > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.purple)
                        Text("\(energyCost)")
                            .font(.caption2)
                    }
                }
                // Indicator for targeting type
                if targetType > 0 {
                    Text(targetType == 1 ? "Ground" : "Unit")
                        .font(.system(size: 7))
                        .foregroundColor(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(hasEnergy ? Color.purple.opacity(0.3) : Color.gray.opacity(0.2))
            .cornerRadius(6)
            .foregroundColor(hasEnergy ? .white : .gray)
        }
        .disabled(!hasEnergy)
    }

    func iconForAbility(_ name: String) -> String {
        switch name.lowercased() {
        case "stim pack": return "bolt.heart.fill"
        case "siege mode", "tank mode": return "shield.fill"
        case "burrow": return "arrow.down.to.line"
        case "cloak": return "eye.slash.fill"
        case "yamato cannon": return "scope"
        case "lockdown": return "lock.fill"
        case "psionic storm": return "cloud.bolt.fill"
        case "defensive matrix": return "shield.checkered"
        case "emp shockwave": return "bolt.circle.fill"
        case "irradiate": return "rays"
        case "restoration": return "cross.fill"
        case "optical flare": return "sun.max.fill"
        case "dark swarm": return "cloud.fill"
        case "plague": return "allergens"
        case "consume": return "mouth.fill"
        case "parasite": return "ant.fill"
        case "spawn broodlings": return "ladybug.fill"
        case "ensnare": return "web.camera"
        case "infestation": return "microbe.fill"
        case "hallucination": return "person.2.fill"
        case "feedback": return "arrow.uturn.backward"
        case "mind control": return "brain.head.profile"
        case "maelstrom": return "tornado"
        case "disruption web": return "network"
        case "recall": return "arrow.up.and.down.and.arrow.left.and.right"
        case "stasis field": return "pause.circle.fill"
        default: return "sparkles"
        }
    }
}

// MARK: - Control Group Bar

struct ControlGroupBar: View {
    @ObservedObject var gameController: GameController

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { index in
                ControlGroupButton(
                    group: index,
                    unitCount: gameController.controlGroupSizes[index],
                    onTap: {
                        gameController.selectControlGroup(index)
                    },
                    onLongPress: {
                        gameController.assignControlGroup(index)
                    }
                )
            }

            // Rally point button (shown when production building selected)
            if gameController.hasSelectedProductionBuilding() {
                Divider()
                    .frame(height: 30)
                    .background(Color.gray)

                Button(action: {
                    gameController.enterRallyPointMode()
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 14))
                        Text("Rally")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.orange)
                    .frame(width: 36, height: 36)
                    .background(gameController.rallyPointMode ? Color.orange.opacity(0.3) : Color.black.opacity(0.6))
                    .cornerRadius(6)
                }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }
}

struct ControlGroupButton: View {
    let group: Int
    let unitCount: Int
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                Text("\(group + 1)")
                    .font(.system(size: 12, weight: .bold))
                if unitCount > 0 {
                    Text("\(unitCount)")
                        .font(.system(size: 8))
                        .foregroundColor(.cyan)
                }
            }
            .foregroundColor(unitCount > 0 ? .white : .gray)
            .frame(width: 28, height: 36)
            .background(unitCount > 0 ? Color.blue.opacity(0.4) : Color.black.opacity(0.4))
            .cornerRadius(4)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    onLongPress()
                    // Haptic feedback
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }
        )
    }
}

#Preview {
    GameScreen()
}
