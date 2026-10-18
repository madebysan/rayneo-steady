import AppKit
import MetalKit
import SteadyCore

private extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}

final class GlassesWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controls: NSWindowController!
    private var output: NSWindowController?
    private var diagnostics: NSWindowController?
    private var renderer: ScreenRenderer?
    private var capture: DesktopCapture?
    private let sensors = SensorService()
    private var shortcuts: GlobalShortcuts!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var size = ScreenSize(UserDefaults.standard.object(forKey: "screenSize") as? Int ?? 80)
    private var options = SensorOptions()
    private var active = false
    private var starting = false
    private var session = 0
    private var activeDisplay: CGDirectDisplayID?
    private let percent = NSTextField(labelWithString: "80%")
    private let slider = NSSlider(value: 80, minValue: 40, maxValue: 100, target: nil, action: nil)
    private let contentPicker = NSPopUpButton()
    private let sourcePicker = NSPopUpButton()
    private let outputPicker = NSPopUpButton()
    private let modePicker = NSSegmentedControl(labels: ["Off", "Pinned", "Steady Follow"], trackingMode: .selectOne, target: nil, action: nil)
    private let startButton = NSButton(title: "Open Preview", target: nil, action: nil)
    private let recenterButton = NSButton(title: "Recenter", target: nil, action: nil)
    private let calibrationButton = NSButton(title: "Calibrate Sensors…", target: nil, action: nil)
    private let refinementButton = NSButton(checkboxWithTitle: "Refined tracking", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "Test screen size in a preview, or connect your RayNeo glasses.")
    private let modeHelp = NSTextField(wrappingLabelWithString: "Smooths quick shakes, then follows deliberate head turns.")
    private let sourceHelp = NSTextField(wrappingLabelWithString: "The grid works without Screen Recording permission.")
    private let diagnosticText = NSTextField(wrappingLabelWithString: "Not connected")
    private var statusMenuItem: NSMenuItem!
    private var stopMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.accessory)
        setUpMenus()
        makeControls()
        refreshDisplays()
        updateControls()
        shortcuts = GlobalShortcuts()
        shortcuts.onRecenter = { [weak self] in self?.recenter() }
        shortcuts.onStop = { [weak self] in self?.stop() }
        shortcuts.onShowControls = { [weak self] in self?.showControls() }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.updateStatus() }
        showControls()
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); stop(); sensors.shutDown()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls(); return false
    }

    private func setUpMenus() {
        let main = NSMenu()
        let root = NSMenuItem(); main.addItem(root)
        let appMenu = NSMenu(); root.submenu = appMenu
        let about = appMenu.addItem(withTitle: "About RayNeo Steady", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit RayNeo Steady", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu; main.addItem(windowItem)
        let show = windowMenu.addItem(withTitle: "Show Controls", action: #selector(showControls), keyEquivalent: "1")
        show.target = self
        let bringBack = windowMenu.addItem(withTitle: "Bring Controls to Front", action: #selector(showControls), keyEquivalent: "1")
        bringBack.target = self; bringBack.keyEquivalentModifierMask = [.command, .control]
        let preview = windowMenu.addItem(withTitle: "Show Output", action: #selector(showOutput), keyEquivalent: "2")
        preview.target = self
        windowMenu.addItem(.separator())
        let recenterCommand = windowMenu.addItem(withTitle: "Recenter", action: #selector(recenter), keyEquivalent: "r")
        recenterCommand.target = self; recenterCommand.keyEquivalentModifierMask = [.command, .control]
        let stopCommand = windowMenu.addItem(withTitle: "Stop Output", action: #selector(stop), keyEquivalent: "s")
        stopCommand.target = self; stopCommand.keyEquivalentModifierMask = [.command, .control]
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eyeglasses", accessibilityDescription: "RayNeo Steady")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "RayNeo Steady"
        let menu = NSMenu()
        statusMenuItem = menu.addItem(withTitle: "RayNeo Steady · Stopped", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let control = menu.addItem(withTitle: "Show Controls…", action: #selector(showControls), keyEquivalent: "")
        control.target = self
        let center = menu.addItem(withTitle: "Recenter", action: #selector(recenter), keyEquivalent: "r")
        center.target = self; center.keyEquivalentModifierMask = [.command, .control]
        stopMenuItem = menu.addItem(withTitle: "Stop", action: #selector(stop), keyEquivalent: "s")
        stopMenuItem.target = self; stopMenuItem.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(.separator())
        let info = menu.addItem(withTitle: "About RayNeo Steady", action: #selector(showAbout), keyEquivalent: "")
        info.target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
    private func makeControls() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 586), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "RayNeo Steady"
        window.isReleasedWhenClosed = false
        window.center()
        controls = NSWindowController(window: window)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        let title = label("A smaller, steadier screen.", size: 22, weight: .semibold)
        stack.addArrangedSubview(title)
        let intro = label("Made for your RayNeo Air 4 Pro", size: 12, secondary: true)
        stack.addArrangedSubview(intro); stack.setCustomSpacing(24, after: intro)

        let sizing = NSStackView(); sizing.orientation = .horizontal; sizing.alignment = .centerY; sizing.spacing = 12
        let sizeLabels = NSStackView(views: [label("Screen size", size: 13, weight: .medium), label("One point at a time", size: 11, secondary: true)])
        sizeLabels.orientation = .vertical; sizeLabels.alignment = .leading; sizeLabels.spacing = 4
        sizing.addArrangedSubview(sizeLabels)
        let spacer = NSView(); sizing.addArrangedSubview(spacer)
        let minus = button("−", #selector(smaller)); minus.toolTip = "Reduce screen size by 1 percentage point"; minus.setAccessibilityLabel("Reduce screen size by 1 percent")
        percent.font = .monospacedDigitSystemFont(ofSize: 32, weight: .medium)
        percent.alignment = .center; percent.setAccessibilityLabel("Screen size")
        percent.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let plus = button("+", #selector(larger)); plus.toolTip = "Increase screen size by 1 percentage point"; plus.setAccessibilityLabel("Increase screen size by 1 percent")
        sizing.addArrangedSubview(minus); sizing.addArrangedSubview(percent); sizing.addArrangedSubview(plus)
        sizing.widthAnchor.constraint(equalToConstant: 432).isActive = true
        stack.addArrangedSubview(sizing)
        slider.target = self; slider.action = #selector(sliderChanged); slider.isContinuous = true
        slider.setAccessibilityLabel("Screen size percentage")
        slider.widthAnchor.constraint(equalToConstant: 432).isActive = true
        stack.addArrangedSubview(slider)
        stack.addArrangedSubview(divider())

        contentPicker.addItems(withTitles: ["Calibration grid", "My Mac desktop"])
        contentPicker.selectItem(at: UserDefaults.standard.object(forKey: "contentMode") as? Int == 0 ? 0 : 1)
        contentPicker.target = self; contentPicker.action = #selector(selectionChanged)
        contentPicker.setAccessibilityLabel("Content")
        outputPicker.target = self; outputPicker.action = #selector(selectionChanged); outputPicker.setAccessibilityLabel("Output display")
        sourcePicker.target = self; sourcePicker.action = #selector(selectionChanged); sourcePicker.setAccessibilityLabel("Desktop source")
        stack.addArrangedSubview(row("Show", contentPicker))
        stack.addArrangedSubview(row("Output", outputPicker))
        stack.addArrangedSubview(row("Source", sourcePicker))
        sourceHelp.font = .systemFont(ofSize: 11); sourceHelp.textColor = .secondaryLabelColor
        sourceHelp.preferredMaxLayoutWidth = 432
        stack.addArrangedSubview(sourceHelp)
        stack.addArrangedSubview(divider())

        modePicker.selectedSegment = UserDefaults.standard.object(forKey: "motionMode") as? Int ?? 2
        if !(0...2).contains(modePicker.selectedSegment) { modePicker.selectedSegment = 2 }
        modePicker.target = self; modePicker.action = #selector(modeChanged)
        modePicker.setAccessibilityLabel("Stabilization mode")
        modePicker.widthAnchor.constraint(equalToConstant: 432).isActive = true
        stack.addArrangedSubview(modePicker)
        modeHelp.font = .systemFont(ofSize: 11); modeHelp.textColor = .secondaryLabelColor
        stack.addArrangedSubview(modeHelp)
        refinementButton.target = self; refinementButton.action = #selector(refinementChanged)
        refinementButton.state = UserDefaults.standard.object(forKey: "refinedTracking") as? Bool == false ? .off : .on
        refinementButton.toolTip = "Even frame timing with gentle motion prediction. Turn off to compare with the original tracking, without recalibrating."
        stack.addArrangedSubview(refinementButton)

        let actions = NSStackView(); actions.orientation = .horizontal; actions.spacing = 8
        startButton.bezelStyle = .rounded; startButton.target = self; startButton.action = #selector(toggleOutput)
        startButton.keyEquivalent = "\r"; startButton.controlSize = .large
        startButton.widthAnchor.constraint(equalToConstant: 170).isActive = true
        recenterButton.bezelStyle = .rounded; recenterButton.target = self; recenterButton.action = #selector(recenter)
        recenterButton.toolTip = "Look straight ahead, then recenter (Control–Command–R)"
        let diagnosticsButton = button("Sensors…", #selector(showDiagnostics))
        actions.addArrangedSubview(startButton); actions.addArrangedSubview(recenterButton); actions.addArrangedSubview(diagnosticsButton)
        stack.addArrangedSubview(actions)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.preferredMaxLayoutWidth = 432
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        stack.addArrangedSubview(status)
        applySize(); modeChanged(); selectionChanged()
        // Fit the actual native control metrics rather than relying on hard-coded text heights.
        window.contentView!.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 480, height: stack.fittingSize.height + 48))
    }
    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let view = NSTextField(labelWithString: text); view.font = .systemFont(ofSize: size, weight: weight)
        if secondary { view.textColor = .secondaryLabelColor }
        return view
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        let view = NSButton(title: title, target: self, action: action); view.bezelStyle = .rounded; return view
    }
    private func divider() -> NSBox {
        let box = NSBox(); box.boxType = .separator; box.widthAnchor.constraint(equalToConstant: 432).isActive = true; return box
    }
    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let caption = label(title, size: 13)
        caption.widthAnchor.constraint(equalToConstant: 68).isActive = true
        control.widthAnchor.constraint(equalToConstant: 352).isActive = true
        let row = NSStackView(views: [caption, control]); row.orientation = .horizontal; row.spacing = 12; return row
    }

    private func refreshDisplays() {
        let previousOutput = outputPicker.selectedItem?.tag ?? 0
        let previousSource = sourcePicker.selectedItem?.tag ?? 0
        outputPicker.removeAllItems(); sourcePicker.removeAllItems()
        outputPicker.addItem(withTitle: "Preview window"); outputPicker.lastItem?.tag = 0
        for screen in NSScreen.screens {
            sourcePicker.addItem(withTitle: screen.localizedName); sourcePicker.lastItem?.tag = Int(screen.displayID)
            if CGDisplayIsBuiltin(screen.displayID) == 0 {
                outputPicker.addItem(withTitle: screen.localizedName); outputPicker.lastItem?.tag = Int(screen.displayID)
            }
        }
        outputPicker.selectItem(withTag: previousOutput)
        if sourcePicker.itemArray.contains(where: { $0.tag == previousSource }) { sourcePicker.selectItem(withTag: previousSource) }
        else if let builtin = NSScreen.screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) { sourcePicker.selectItem(withTag: Int(builtin.displayID)) }
        if previousOutput == 0, let glasses = outputPicker.itemArray.first(where: { $0.title.localizedCaseInsensitiveContains("RayNeo") || $0.title.localizedCaseInsensitiveContains("SmartGlasses") }) {
            outputPicker.select(glasses)
        }
        selectionChanged()
    }
    @objc private func displaysChanged() {
        if active || starting { stop(); status.stringValue = "Display setup changed. Check Output and start again." }
        refreshDisplays()
    }
    @objc private func willSleep() { stop() }
    @objc func showControls() {
        if let id = activeDisplay, id != 0, CGDisplayIsInMirrorSet(id) != 0 {
            controls?.window?.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        }
        controls?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showOutput() { output?.window?.makeKeyAndOrderFront(nil) }
    @objc private func smaller() { size.step(-1); applySize() }
    @objc private func larger() { size.step(1); applySize() }
    @objc private func sliderChanged() { size = ScreenSize(Int(slider.doubleValue.rounded())); applySize() }
    private func applySize() {
        percent.stringValue = "\(size.percent)%"; slider.integerValue = size.percent
        renderer?.scale = size.scale; UserDefaults.standard.set(size.percent, forKey: "screenSize")
    }
    @objc private func modeChanged() {
        let mode = MotionMode(rawValue: modePicker.selectedSegment) ?? .follow
        modeHelp.stringValue = ["The screen moves with your head. Size controls remain active.",
                               "Holds a direction. Look ahead and use Recenter when needed.",
                               "Smooths quick shakes, then follows deliberate head turns."][mode.rawValue]
        sensors.configure(mode: mode, options: options)
        UserDefaults.standard.set(mode.rawValue, forKey: "motionMode")
    }
    @objc private func selectionChanged() {
        let desktop = contentPicker.indexOfSelectedItem == 1
        UserDefaults.standard.set(desktop ? 1 : 0, forKey: "contentMode")
        sourcePicker.isEnabled = desktop && !active && !starting
        sourceHelp.stringValue = desktop ? "Copies this screen and its pointer. Keep the Mac display available." : "The grid works without Screen Recording permission."
        if !active && !starting { startButton.title = outputPicker.selectedItem?.tag == 0 ? "Open Preview" : "Start in Glasses" }
    }
    @objc private func refinementChanged() {
        let enabled = refinementButton.state == .on
        renderer?.refinedTracking = enabled
        UserDefaults.standard.set(enabled, forKey: "refinedTracking")
    }
    @objc private func toggleOutput() {
        if active || starting { stop(); return }
        startOutput()
    }
    private func startOutput() {
        let target = CGDirectDisplayID(outputPicker.selectedItem?.tag ?? 0)
        let source = CGDirectDisplayID(sourcePicker.selectedItem?.tag ?? 0)
        let desktop = contentPicker.indexOfSelectedItem == 1
        if desktop && source == 0 { status.stringValue = "Choose a source screen first."; return }
        if desktop && source == target { status.stringValue = "Choose your Mac screen as Source. The glasses are the output."; return }
        if desktop && target != 0 && CGDisplayIsInMirrorSet(target) != 0 {
            status.stringValue = "Desktop output currently needs an extended display. Keep your settings and use Calibration grid or Preview window."; return
        }
        session += 1; let token = session
        starting = true; updateControls()
        if desktop && !CGPreflightScreenCaptureAccess() {
            starting = false; updateControls()
            let alert = NSAlert()
            alert.messageText = "Allow desktop mirroring"
            alert.informativeText = "RayNeo Steady needs Screen Recording access to display your desktop. Frames stay on this Mac. You can use the calibration grid without this permission."
            alert.addButton(withTitle: "Request Access"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                let granted = CGRequestScreenCaptureAccess()
                if granted { startOutput(); return }
                status.stringValue = "Allow RayNeo Steady in System Settings → Privacy & Security → Screen Recording, then reopen it."
            }
            return
        }
        guard makeOutput(target: target) else { starting = false; updateControls(); return }
        activeDisplay = target
        if target != 0 && CGDisplayIsInMirrorSet(target) != 0 { showControls() }
        renderer?.usesDesktop = desktop
        sensors.start()
        if desktop {
            let capture = DesktopCapture(); self.capture = capture
            capture.onFrame = { [weak renderer] buffer in renderer?.setFrame(buffer) }
            capture.onError = { [weak self] error in
                DispatchQueue.main.async {
                    guard let self, self.session == token else { return }
                    self.stop(); self.status.stringValue = "Screen sharing stopped: \(error.localizedDescription)"
                }
            }
            Task { @MainActor [weak self] in
                do {
                    try await capture.start(displayID: source)
                    guard let self, self.session == token else { await capture.stop(); return }
                    self.starting = false; self.active = true; self.updateControls()
                } catch {
                    guard let self, self.session == token else { await capture.stop(); return }
                    self.stop(); self.status.stringValue = "Could not capture desktop: \(error.localizedDescription)"
                }
            }
        } else { starting = false; active = true; updateControls() }
    }
    private func makeOutput(target: CGDirectDisplayID) -> Bool {
        let window: NSWindow
        if target == 0 {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "RayNeo Steady — Preview"; window.center()
            window.contentAspectRatio = NSSize(width: 16, height: 9)
        } else {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == target }) else {
                status.stringValue = "Output display is no longer connected."; return false
            }
            window = GlassesWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
            window.setFrame(screen.frame, display: false)
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            (window as? NSPanel)?.hidesOnDeactivate = false
        }
        window.isReleasedWhenClosed = false; window.delegate = self
        window.backgroundColor = .black; window.isOpaque = true
        let view = MTKView(frame: window.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        guard let renderer = ScreenRenderer(view) else {
            status.stringValue = "Metal rendering is unavailable on this Mac."; return false
        }
        renderer.scale = size.scale
        renderer.refinedTracking = refinementButton.state == .on
        renderer.rotation = { [weak sensors] target in sensors?.rotationForDisplay(targetTime: target) ?? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)) }
        self.renderer = renderer
        window.contentView = view
        output = NSWindowController(window: window)
        if target == 0 { window.makeKeyAndOrderFront(nil) }
        else {
            window.orderFrontRegardless()
        }
        return true
    }
    @objc func stop() {
        session += 1; active = false; starting = false
        sensors.stop()
        if let capture { Task { await capture.stop() } }
        capture = nil
        (output?.window?.contentView as? MTKView)?.isPaused = true
        renderer?.stop()
        output?.window?.delegate = nil; output?.close(); output = nil; renderer = nil
        activeDisplay = nil
        controls?.window?.level = .normal
        controls?.showWindow(nil)
        status.stringValue = "Stopped. Your size and stabilization mode are saved."
        updateControls()
    }
    @objc func recenter() { sensors.recenter() }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === output?.window { stop() }
    }
    private func updateControls() {
        let running = active || starting
        contentPicker.isEnabled = !running; outputPicker.isEnabled = !running
        sourcePicker.isEnabled = !running && contentPicker.indexOfSelectedItem == 1
        startButton.title = running ? "Stop" : (outputPicker.selectedItem?.tag == 0 ? "Open Preview" : "Start in Glasses")
        recenterButton.isEnabled = running
        stopMenuItem?.isEnabled = running
        statusMenuItem?.title = "RayNeo Steady · \(running ? "Running" : "Stopped")"
    }
    private func updateStatus() {
        let snapshot = sensors.snapshot
        if active || starting {
            let prefix = starting ? "Starting… " : (activeDisplay == 0 ? "Preview · " : "Glasses · ")
            if let capture, capture.status.frames == 0 {
                status.stringValue = "Waiting for your desktop’s first frame…"
            } else {
                status.stringValue = prefix + (capture == nil ? "" : "Desktop live · ") + snapshot.message
            }
        }
        calibrationButton.isEnabled = snapshot.connected
        let dps = snapshot.rawDPS
        let timing = renderer?.timing.snapshot ?? RenderTimingSnapshot()
        diagnosticText.stringValue = "\(snapshot.message)\n\nSamples: \(snapshot.samples)    Rate: \(Int(snapshot.sampleRate.rounded())) Hz\nGyroscope: \(String(format: "%.2f, %.2f, %.2f", dps.x, dps.y, dps.z)) °/s\nCalibration: \(snapshot.calibrated ? "Ready" : "Not ready")\nMotion applied: \(snapshot.integratedSamples) · Timing skipped: \(snapshot.rejectedTimingSamples)\nImage correction: \(String(format: "%.2f", snapshot.rotation.angle * 180 / .pi))°\nRenderer: \(renderer?.frames ?? 0) frames\n\nControl–Command–1: show controls\nControl–Command–R: recenter\nControl–Command–S: stop\(shortcuts?.available == false ? "\nA shortcut is in use by another app. Use the menu bar controls." : "")"
        diagnosticText.stringValue += String(format: "\n\nDisplay: %.1f fps · p95 interval %.1f ms\nDraw-to-display: %.1f ms · p95 %.1f ms", timing.fps, timing.p95IntervalMS, timing.meanLatencyMS, timing.p95LatencyMS)
        if let capture {
            let video = capture.status
            diagnosticText.stringValue += "\nDesktop: \(video.frames) frames · \(video.width)×\(video.height)"
        }
    }
    @objc private func showDiagnostics() {
        if diagnostics == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Motion Sensors"; window.isReleasedWhenClosed = false; window.center()
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
            diagnosticText.font = .monospacedSystemFont(ofSize: 11, weight: .regular); diagnosticText.preferredMaxLayoutWidth = 392
            stack.addArrangedSubview(diagnosticText)
            calibrationButton.target = self; calibrationButton.action = #selector(calibrate); calibrationButton.bezelStyle = .rounded
            stack.addArrangedSubview(calibrationButton)
            for (index, title) in ["Use 45° sensor alignment", "Reverse horizontal tracking", "Reverse vertical tracking", "Compensate head tilt"].enumerated() {
                let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(sensorOptionChanged(_:)))
                checkbox.tag = index; checkbox.state = index == 3 ? .on : .off; stack.addArrangedSubview(checkbox)
                stack.setCustomSpacing(8, after: checkbox)
            }
            let help = NSTextField(wrappingLabelWithString: "Experimental tracking. Change alignment only if head movement goes in the wrong direction. Recenter after putting the glasses on.")
            help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor; help.preferredMaxLayoutWidth = 392
            stack.addArrangedSubview(help)
            window.contentView!.layoutSubtreeIfNeeded(); window.setContentSize(NSSize(width: 440, height: stack.fittingSize.height + 48))
            diagnostics = NSWindowController(window: window)
        }
        updateStatus(); diagnostics?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func sensorOptionChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        switch sender.tag {
        case 0: options.tiltedSensor = enabled
        case 1: options.reverseYaw = enabled
        case 2: options.reversePitch = enabled
        default: options.trackRoll = enabled
        }
        sensors.configure(mode: MotionMode(rawValue: modePicker.selectedSegment) ?? .follow, options: options)
    }
    @objc private func calibrate() {
        let alert = NSAlert(); alert.messageText = "Rest the glasses on a still surface"
        alert.informativeText = "Leave them still for two seconds after starting. Then put them on, look straight ahead, and press Recenter. Calibration is temporary and does not change the glasses' firmware."
        alert.addButton(withTitle: "Start Calibration"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { sensors.calibrate() }
    }
    @objc private func showAbout() {
        let credits = NSMutableAttributedString(string: "A personal prototype by san.\n")
        credits.append(NSAttributedString(string: "santiagoalonso.com", attributes: [.link: URL(string: "https://santiagoalonso.com")!]))
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "RayNeo Steady", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0", .credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}
