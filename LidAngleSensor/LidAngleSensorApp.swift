import SwiftUI

@main
struct LidAngleSensorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let warningAngle = 119.0
    private static let statusItemSidePadding = 1.0
    private static let statusItemIconTitleSpacing = 1.0
    private static let statusItemClippingAllowance = 3.0
    private static let statusItemImageSize = NSSize(width: 14, height: 14)

    private let sensor = LidAngleSensor()
    private let audioController = AudioController()
    private let statusMenu = NSMenu()

    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    private var didShowWarning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.setActivationPolicy(.accessory)

        createStatusItem()
        sensor.start()

        updateTimer = .scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSensorUpdate()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
        updateTimer = nil
        sensor.stop()
    }

    private func createStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu.delegate = self
        statusItem.menu = statusMenu

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "angle", accessibilityDescription: "Lid angle")
            image?.isTemplate = true
            image?.size = Self.statusItemImageSize

            button.image = image
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.toolTip = "Lid angle"
        }

        self.statusItem = statusItem
        updateStatusItem()
        rebuildMenu(statusMenu)
    }

    private func handleSensorUpdate() {
        audioController.feed(angle: sensor.angle, velocity: sensor.velocity)
        updateStatusItem()

        guard sensor.isAvailable else { return }

        if sensor.angle >= Self.warningAngle {
            guard !didShowWarning else { return }
            didShowWarning = true
            showLidAngleWarning()
        } else {
            didShowWarning = false
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let angleText = sensor.isAvailable
        ? "\(sensor.angle.formatted(.number.precision(.fractionLength(0))))°"
        : ""

        let attributedTitle = NSAttributedString(
            string: angleText,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )

        button.attributedTitle = attributedTitle
        button.imagePosition = sensor.isAvailable ? .imageLeading : .imageOnly
        button.imageHugsTitle = true
        updateStatusItemLength(title: attributedTitle)
    }

    private func updateStatusItemLength(title: NSAttributedString) {
        let imageWidth = Self.statusItemImageSize.width
        let titleWidth = sensor.isAvailable ? title.size().width : 0
        let spacing = sensor.isAvailable ? Self.statusItemIconTitleSpacing : 0
        let sidePadding = Self.statusItemSidePadding * 2
        let clippingAllowance = sensor.isAvailable ? Self.statusItemClippingAllowance : 0

        statusItem?.length = ceil(imageWidth + titleWidth + spacing + sidePadding + clippingAllowance)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        
        if !sensor.isAvailable {
            let item = NSMenuItem(title: "Sensor Not Available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        if sensor.angle >= Self.warningAngle {
            let item = NSMenuItem(title: "Warning: 119° reached", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            item.isEnabled = false
            menu.addItem(item)
        }

        let soundModeItem = NSMenuItem(title: "Sound Mode", action: nil, keyEquivalent: "")
        let soundModeMenu = NSMenu()
        for mode in AudioMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(selectSoundMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = audioController.mode == mode ? .on : .off
            soundModeMenu.addItem(item)
        }
        soundModeItem.submenu = soundModeMenu
        menu.addItem(soundModeItem)

        let startStopItem = NSMenuItem(
            title: audioController.isPlaying ? "🖐Stop" : "✅Start",
            action: #selector(toggleAudio),
            keyEquivalent: ""
        )
        startStopItem.target = self
        startStopItem.isEnabled = sensor.isAvailable
        menu.addItem(startStopItem)

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "👁Show", action: #selector(showApplication), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let hideItem = NSMenuItem(title: "🔼Hide", action: #selector(hideApplication), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        let quitItem = NSMenuItem(title: "❌Quit", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func selectSoundMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? AudioMode else { return }
        audioController.mode = mode
    }

    @objc private func toggleAudio() {
        audioController.toggle()
    }

    @objc private func showApplication() {
        AppWindowPresenter.show(sensor: sensor, audioController: audioController)
    }

    @objc private func hideApplication() {
        NSApplication.shared.windows.forEach { $0.orderOut(nil) }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showLidAngleWarning() {
        NSSound.beep()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Lid angle warning"
        alert.informativeText = "The lid sensor has reached 119 degrees (Fully Open)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
