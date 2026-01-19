// GameView.swift
// SwiftUI view for rendering and interacting with the StarCraft game

import SwiftUI
import MetalKit

/// Main game view that handles rendering and touch input
public struct GameView: View {
    @StateObject private var game = OpenBWGame.shared

    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var selectionRect: CGRect? = nil

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Game rendering layer (Metal-based in full implementation)
                GameRenderView()
                    .gesture(gameGestures(in: geometry))

                // HUD overlay
                VStack {
                    // Top bar - resources
                    HStack {
                        ResourceBar(
                            minerals: game.minerals,
                            gas: game.gas,
                            supply: game.supply,
                            supplyMax: game.supplyMax
                        )
                        Spacer()
                    }
                    .padding()

                    Spacer()

                    // Bottom bar - commands and minimap
                    HStack(alignment: .bottom) {
                        // Minimap
                        MinimapView()
                            .frame(width: 150, height: 150)

                        Spacer()

                        // Command panel
                        CommandPanel()
                            .frame(width: 200)
                    }
                    .padding()
                }

                // Selection rectangle overlay
                if let rect = selectionRect {
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
                        .background(Color.green.opacity(0.1))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func gameGestures(in geometry: GeometryProxy) -> some Gesture {
        // Combined gestures for game interaction
        SimultaneousGesture(
            // Tap for selection
            TapGesture(count: 1)
                .onEnded { _ in
                    // Handle tap - implemented via drag gesture end
                },
            // Drag for box selection or camera pan
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStart = value.startLocation
                    }

                    // Show selection box
                    let rect = CGRect(
                        x: min(dragStart.x, value.location.x),
                        y: min(dragStart.y, value.location.y),
                        width: abs(value.location.x - dragStart.x),
                        height: abs(value.location.y - dragStart.y)
                    )
                    selectionRect = rect
                }
                .onEnded { value in
                    isDragging = false

                    if let rect = selectionRect, rect.width > 10 || rect.height > 10 {
                        // Box selection
                        game.boxSelect(from: dragStart, to: value.location)
                    } else {
                        // Single tap - select or command
                        game.selectUnit(at: value.location)
                    }

                    selectionRect = nil
                }
        )
    }
}

/// Metal-based game rendering view
struct GameRenderView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // TODO: Set up Metal rendering pipeline
        // This would connect to OpenBW's rendering output

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Update rendering if needed
    }
}

/// Resource display bar
struct ResourceBar: View {
    let minerals: Int
    let gas: Int
    let supply: Int
    let supplyMax: Int

    var body: some View {
        HStack(spacing: 20) {
            // Minerals
            HStack(spacing: 4) {
                Image(systemName: "diamond.fill")
                    .foregroundColor(.cyan)
                Text("\(minerals)")
                    .font(.system(.body, design: .monospaced))
            }

            // Gas
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.green)
                Text("\(gas)")
                    .font(.system(.body, design: .monospaced))
            }

            // Supply
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.white)
                Text("\(supply)/\(supplyMax)")
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }
}

/// Minimap view
struct MinimapView: View {
    var body: some View {
        ZStack {
            // Minimap background
            Rectangle()
                .fill(Color.black)
                .overlay(
                    Rectangle()
                        .stroke(Color.gray, lineWidth: 2)
                )

            // TODO: Render actual minimap from game state
            Text("Minimap")
                .foregroundColor(.gray)
                .font(.caption)
        }
    }
}

/// Command panel for unit actions
struct CommandPanel: View {
    var body: some View {
        VStack(spacing: 8) {
            // Command buttons grid (3x3)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(0..<9) { index in
                    CommandButton(index: index)
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }
}

/// Individual command button
struct CommandButton: View {
    let index: Int

    var body: some View {
        Button(action: {
            // TODO: Execute command
        }) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Rectangle()
                        .stroke(Color.gray, lineWidth: 1)
                )
                .frame(width: 50, height: 50)
        }
    }
}

#Preview {
    GameView()
}
