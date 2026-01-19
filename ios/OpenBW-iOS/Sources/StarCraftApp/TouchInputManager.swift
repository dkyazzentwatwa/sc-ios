// TouchInputManager.swift
// Comprehensive touch input handling for StarCraft iOS

import UIKit
// OpenBWBridge types are available via bridging header

/// Manages all touch input and translates gestures to game commands
class TouchInputManager: NSObject {

    // MARK: - Types

    /// The current input mode determines how touches are interpreted
    enum InputMode {
        case normal          // Default: pan camera, tap to select
        case buildPlacement  // Placing a building
        case targeting       // Targeting an ability
    }

    /// Command type for selected units
    enum CommandType {
        case move
        case attackMove
        case patrol
        case holdPosition
    }

    // MARK: - Properties

    weak var gameController: GameController?
    weak var targetView: UIView?

    /// Current input mode
    private(set) var inputMode: InputMode = .normal

    /// Pending command type (from command palette)
    private(set) var pendingCommand: CommandType?

    /// Building type ID being placed (when in buildPlacement mode)
    private(set) var pendingBuildingType: Int?

    /// Tracks whether units are currently selected
    private(set) var hasSelection: Bool = false

    // Touch tracking
    private var touchStartTime: Date?
    private var touchStartLocation: CGPoint = .zero
    private var isDragging = false
    private var isBoxSelecting = false
    private var lastPanTranslation: CGPoint = .zero

    // Selection box callback
    var onSelectionBoxUpdate: ((CGRect?) -> Void)?

    // Context menu callback
    var onShowContextMenu: ((CGPoint) -> Void)?

    // Build preview callback
    var onBuildPreviewUpdate: ((CGPoint?, Int?) -> Void)?

    // MARK: - Constants

    private let tapDistanceThreshold: CGFloat = 10
    private let longPressThreshold: TimeInterval = 0.5
    private let doubleTapTimeThreshold: TimeInterval = 0.3
    private var lastTapTime: Date = .distantPast
    private var lastTapLocation: CGPoint = .zero

    // MARK: - Initialization

    init(gameController: GameController) {
        self.gameController = gameController
        super.init()
    }

    // MARK: - Gesture Recognizer Setup

    /// Attach gesture recognizers to a view
    func attachToView(_ view: UIView) {
        targetView = view
        view.isMultipleTouchEnabled = true

        // Single tap - select or command
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)

        // Double tap - attack move or center camera
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.delegate = self
        view.addGestureRecognizer(doubleTapGesture)
        tapGesture.require(toFail: doubleTapGesture)

        // Long press - context menu
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = longPressThreshold
        longPressGesture.delegate = self
        view.addGestureRecognizer(longPressGesture)

        // Pan - camera movement (two fingers) or box selection (one finger)
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)

        // Pinch - zoom
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        view.addGestureRecognizer(pinchGesture)
    }

    // MARK: - Mode Management

    /// Enter build placement mode
    func enterBuildMode(buildingType: Int) {
        inputMode = .buildPlacement
        pendingBuildingType = buildingType
    }

    /// Enter targeting mode for an ability
    func enterTargetingMode(command: CommandType) {
        inputMode = .targeting
        pendingCommand = command
    }

    /// Exit special modes and return to normal
    func cancelMode() {
        inputMode = .normal
        pendingCommand = nil
        pendingBuildingType = nil
        onBuildPreviewUpdate?(nil, nil)
    }

    /// Update selection state
    func setHasSelection(_ hasSelection: Bool) {
        self.hasSelection = hasSelection
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = gesture.location(in: targetView)

        switch inputMode {
        case .normal:
            // Check if GameController has a pending command mode
            if let controller = gameController, controller.commandMode != .none {
                // Execute the pending command from the command palette
                controller.handlePendingCommand(at: location)
            } else if hasSelection && pendingCommand != nil {
                // Execute pending command from this manager
                executeCommand(at: location)
            } else {
                // Select unit at location
                gameController?.handleTap(at: location, in: targetView?.bounds.size ?? .zero)
            }

        case .buildPlacement:
            // Place building
            if let buildingType = pendingBuildingType {
                gameController?.gameRunner?.buildStructure(Int32(buildingType), atX: location.x, y: location.y)
                cancelMode()
            }

        case .targeting:
            // Execute targeted ability
            executeCommand(at: location)
            cancelMode()
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = gesture.location(in: targetView)

        if hasSelection {
            // Attack-move to location
            gameController?.attackMoveUnits(to: location)
        } else {
            // Double-tap without selection: center camera on location
            gameController?.centerCamera(on: location)
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: targetView)

        switch gesture.state {
        case .began:
            // Show context menu
            onShowContextMenu?(location)

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

        case .changed:
            // Update context menu highlight based on position
            break

        case .ended, .cancelled:
            // Hide context menu, execute selected action
            break

        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: targetView)
        let translation = gesture.translation(in: targetView)
        let numberOfTouches = gesture.numberOfTouches

        switch gesture.state {
        case .began:
            touchStartLocation = location
            lastPanTranslation = .zero

            if numberOfTouches >= 2 {
                // Two-finger pan: camera movement
                isDragging = true
                isBoxSelecting = false
            } else {
                // One-finger: could be box selection or building preview
                if inputMode == .buildPlacement {
                    isDragging = true
                    isBoxSelecting = false
                } else {
                    isBoxSelecting = true
                    isDragging = false
                }
            }

        case .changed:
            if numberOfTouches >= 2 || isDragging {
                // Camera pan
                let delta = CGPoint(
                    x: translation.x - lastPanTranslation.x,
                    y: translation.y - lastPanTranslation.y
                )
                lastPanTranslation = translation

                // Invert for natural scrolling feel
                gameController?.moveCamera(dx: -delta.x, dy: -delta.y)

                isBoxSelecting = false
                onSelectionBoxUpdate?(nil)

            } else if isBoxSelecting {
                // Update selection box
                let rect = CGRect(
                    x: min(touchStartLocation.x, location.x),
                    y: min(touchStartLocation.y, location.y),
                    width: abs(location.x - touchStartLocation.x),
                    height: abs(location.y - touchStartLocation.y)
                )
                onSelectionBoxUpdate?(rect)

            } else if inputMode == .buildPlacement {
                // Update build preview position
                onBuildPreviewUpdate?(location, pendingBuildingType)
            }

        case .ended, .cancelled:
            if isBoxSelecting {
                // Complete box selection
                let endLocation = location
                let rect = CGRect(
                    x: min(touchStartLocation.x, endLocation.x),
                    y: min(touchStartLocation.y, endLocation.y),
                    width: abs(endLocation.x - touchStartLocation.x),
                    height: abs(endLocation.y - touchStartLocation.y)
                )

                // Only select if box is large enough
                if rect.width > tapDistanceThreshold || rect.height > tapDistanceThreshold {
                    gameController?.handleDrag(from: touchStartLocation, to: endLocation, in: targetView?.bounds.size ?? .zero)
                }

                onSelectionBoxUpdate?(nil)
            }

            isDragging = false
            isBoxSelecting = false
            lastPanTranslation = .zero

        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            gameController?.setZoom(gesture.scale)

        case .ended:
            // Clamp zoom to valid range
            let currentZoom = gameController?.getCurrentZoom() ?? 1.0
            gameController?.setZoom(currentZoom)

        default:
            break
        }
    }

    // MARK: - Command Execution

    private func executeCommand(at location: CGPoint) {
        guard let command = pendingCommand else {
            // Default: move command
            gameController?.moveSelectedUnits(to: location)
            return
        }

        switch command {
        case .move:
            gameController?.moveSelectedUnits(to: location)
        case .attackMove:
            gameController?.attackMoveUnits(to: location)
        case .patrol:
            gameController?.patrolUnits(to: location)
        case .holdPosition:
            // Hold position doesn't need a target
            gameController?.holdPosition()
        }

        pendingCommand = nil
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TouchInputManager: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pinch and pan simultaneously for smooth zoom+pan
        if gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer {
            return true
        }
        if gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer {
            return true
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Single tap should wait for double tap to fail
        if gestureRecognizer is UITapGestureRecognizer && otherGestureRecognizer is UITapGestureRecognizer {
            let tap1 = gestureRecognizer as! UITapGestureRecognizer
            let tap2 = otherGestureRecognizer as! UITapGestureRecognizer
            return tap1.numberOfTapsRequired == 1 && tap2.numberOfTapsRequired == 2
        }
        return false
    }
}
