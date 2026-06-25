//
//  MenuBarView.swift
//  LidAngleSensor
//
//  Created by Sam on 2026-03-22.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(\.lidAngleSensor) private var sensor
    @Environment(\.audioController) private var audioController
    
    var body: some View {
        @Bindable var controller = audioController
        
        if !sensor.isAvailable {
            Text("Sensor Not Available")
        }

        if sensor.angle >= 119 {
            Label("Warning: 119° reached", systemImage: "exclamationmark.triangle.fill")
            
        }
        
        Section {
            Picker("Sound Mode", selection: $controller.mode) {
                ForEach(AudioMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.inline)
            
            Button(audioController.isPlaying ? "🖐Stop" : "✅Start") {
                audioController.toggle()
            }
        }
        .disabled(!sensor.isAvailable)

        Button("👁Show") {
            AppWindowPresenter.show(sensor: sensor, audioController: audioController)
        }
        
        Button("❌Quit") {
            NSApplication.shared.terminate(nil)
        }
        Button("🔼Hide") {
            NSApplication.shared.windows.forEach { $0.orderOut(nil) }
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
private enum AppWindowPresenter {
    private static var window: NSWindow?

    static func show(sensor: LidAngleSensor, audioController: AudioController) {
        NSApplication.shared.setActivationPolicy(.regular)

        if let window = Self.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ContentView()
            .environment(\.lidAngleSensor, sensor)
            .environment(\.audioController, audioController)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 667),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Lid Angle Sensor"
        window.contentViewController = NSHostingController(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        Self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
