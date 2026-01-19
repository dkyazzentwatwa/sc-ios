// OpenBW.swift
// Swift wrapper for the OpenBW engine

import Foundation
import UIKit
// OpenBWBridge types are available via bridging header

/// Swift-friendly wrapper around the OpenBW game engine
public class OpenBWGame: ObservableObject {
    /// Shared singleton instance
    public static let shared = OpenBWGame()

    /// The underlying Objective-C++ engine
    private let engine: OpenBWEngine

    /// Whether a game is currently running
    @Published public private(set) var isRunning: Bool = false

    /// Current minerals
    @Published public private(set) var minerals: Int = 0

    /// Current gas
    @Published public private(set) var gas: Int = 0

    /// Current supply
    @Published public private(set) var supply: Int = 0

    /// Maximum supply
    @Published public private(set) var supplyMax: Int = 0

    private init() {
        engine = OpenBWEngine.shared
    }

    /// Initialize the engine with the path to game assets (MPQ files)
    public func initialize(assetPath: String) throws {
        do {
            try engine.initializeWithAssetPath(assetPath)
        } catch {
            throw OpenBWError.initializationFailed(error.localizedDescription)
        }
    }

    /// Start a new game
    public func startGame(config: GameConfig) throws {
        let objcConfig = OpenBWConfig()
        objcConfig.mapPath = config.mapPath
        objcConfig.replayPath = config.replayPath
        objcConfig.playerRace = Int32(config.playerRace.rawValue)
        objcConfig.aiDifficulty = Int32(config.aiDifficulty)
        objcConfig.enableSound = config.enableSound
        objcConfig.enableMusic = config.enableMusic

        do {
            try engine.startGame(with: objcConfig)
            isRunning = true
        } catch {
            throw OpenBWError.gameStartFailed(error.localizedDescription)
        }
    }

    /// Pause the game
    public func pause() {
        engine.pause()
        isRunning = false
    }

    /// Resume the game
    public func resume() {
        engine.resume()
        isRunning = true
    }

    /// Stop the game
    public func stop() {
        engine.stop()
        isRunning = false
    }

    // MARK: - Input Handling

    /// Handle touch began
    public func touchBegan(at point: CGPoint) {
        engine.touchBegan(atX: point.x, y: point.y)
    }

    /// Handle touch moved
    public func touchMoved(to point: CGPoint) {
        engine.touchMoved(toX: point.x, y: point.y)
    }

    /// Handle touch ended
    public func touchEnded(at point: CGPoint) {
        engine.touchEnded(atX: point.x, y: point.y)
    }

    /// Handle pinch gesture (zoom)
    public func pinch(scale: CGFloat) {
        engine.pinch(withScale: scale)
    }

    /// Handle pan gesture (camera)
    public func pan(delta: CGPoint) {
        engine.pan(withDeltaX: delta.x, deltaY: delta.y)
    }

    // MARK: - Commands

    /// Select unit at screen position
    public func selectUnit(at point: CGPoint) {
        engine.selectUnit(atX: point.x, y: point.y)
    }

    /// Box select units
    public func boxSelect(from start: CGPoint, to end: CGPoint) {
        engine.boxSelect(fromX: start.x, y: start.y, toX: end.x, y: end.y)
    }

    /// Move selected units to position
    public func moveSelected(to point: CGPoint) {
        engine.moveSelected(toX: point.x, y: point.y)
    }

    /// Attack-move selected units
    public func attackMove(to point: CGPoint) {
        engine.attackMove(toX: point.x, y: point.y)
    }

    /// Build structure at position
    public func buildStructure(_ type: Int, at point: CGPoint) {
        engine.buildStructure(Int32(type), atX: point.x, y: point.y)
    }

    /// Train unit from selected building
    public func trainUnit(_ type: Int) {
        engine.trainUnit(Int32(type))
    }

    /// Assign selected units to control group
    public func assignToControlGroup(_ group: Int) {
        engine.assign(toControlGroup: Int32(group))
    }

    /// Select control group
    public func selectControlGroup(_ group: Int) {
        engine.selectControlGroup(Int32(group))
    }

    // MARK: - Camera

    /// Set camera position
    public func setCameraPosition(_ position: CGPoint) {
        engine.setCameraX(position.x, y: position.y)
    }

    /// Get camera position
    public var cameraPosition: CGPoint {
        engine.cameraPosition()
    }

    /// Set zoom level
    public func setZoomLevel(_ zoom: CGFloat) {
        engine.setZoomLevel(zoom)
    }
}

// MARK: - Supporting Types

/// Game configuration
public struct GameConfig {
    public var mapPath: String
    public var replayPath: String?
    public var playerRace: Race
    public var aiDifficulty: Int
    public var enableSound: Bool
    public var enableMusic: Bool

    public init(
        mapPath: String,
        replayPath: String? = nil,
        playerRace: Race = .terran,
        aiDifficulty: Int = 1,
        enableSound: Bool = true,
        enableMusic: Bool = true
    ) {
        self.mapPath = mapPath
        self.replayPath = replayPath
        self.playerRace = playerRace
        self.aiDifficulty = aiDifficulty
        self.enableSound = enableSound
        self.enableMusic = enableMusic
    }
}

/// Player race
public enum Race: Int {
    case terran = 0
    case protoss = 1
    case zerg = 2
    case random = 3
}

/// OpenBW errors
public enum OpenBWError: Error, LocalizedError {
    case initializationFailed(String)
    case gameStartFailed(String)
    case assetNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "Failed to initialize OpenBW: \(message)"
        case .gameStartFailed(let message):
            return "Failed to start game: \(message)"
        case .assetNotFound(let path):
            return "Required asset not found: \(path)"
        }
    }
}
