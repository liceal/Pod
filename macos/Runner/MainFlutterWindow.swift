import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSPanel {
  private var globalMonitor: Any?
  private var localMonitor: Any?
  private var previousFrontmostApp: NSRunningApplication?
  private var lastScrollTime: TimeInterval = 0

  override var canBecomeKey: Bool {
    return true
  }

  override var canBecomeMain: Bool {
    return false
  }

  private var dummyCloseButton: NSButton?
  private var dummyMiniaturizeButton: NSButton?
  private var dummyZoomButton: NSButton?
  private var dummyTitleBarView: NSView?
  private var dummyTitleBarContainer: NSView?

  private func restorePreviousFrontmostApp() {
    let appToRestore = previousFrontmostApp
    previousFrontmostApp = nil

    self.makeFirstResponder(nil)
    if self.isKeyWindow {
      self.resignKey()
    }
    NSApp.deactivate()

    if let prev = appToRestore, !prev.isTerminated {
      prev.activate(options: [.activateIgnoringOtherApps])
    }
  }

  override func standardWindowButton(_ button: NSWindow.ButtonType) -> NSButton? {
    if let realButton = super.standardWindowButton(button) {
      return realButton
    }

    if dummyCloseButton == nil {
      let close = NSButton()
      let min = NSButton()
      let zoom = NSButton()
      let titleBar = NSView()
      let container = NSView()
      
      titleBar.addSubview(close)
      titleBar.addSubview(min)
      titleBar.addSubview(zoom)
      container.addSubview(titleBar)
      
      dummyCloseButton = close
      dummyMiniaturizeButton = min
      dummyZoomButton = zoom
      dummyTitleBarView = titleBar
      dummyTitleBarContainer = container
    }

    switch button {
    case .closeButton:
      return dummyCloseButton
    case .miniaturizeButton:
      return dummyMiniaturizeButton
    case .zoomButton:
      return dummyZoomButton
    default:
      return nil
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Force native window to be fully transparent to prevent any pure black mask
    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    flutterViewController.backgroundColor = NSColor.clear
    self.hasShadow = false
    self.isMovable = false
    self.styleMask.insert(.nonactivatingPanel)
    self.styleMask.insert(.utilityWindow)
    self.isFloatingPanel = true
    self.hidesOnDeactivate = false
    self.becomesKeyOnlyIfNeeded = false
    self.isExcludedFromWindowsMenu = true
    self.animationBehavior = .none
    self.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .transient,
      .ignoresCycle,
    ]

    // Remove macOS system-level window corner radius.
    // Flutter's borderRadius=0 only affects widget painting; the OS still clips
    // the window's contentView with its own rounded corners. Setting the layer's
    // cornerRadius to 0 on both the contentView and its hosting layer removes this.
    if let contentView = self.contentView {
      contentView.wantsLayer = true
      contentView.layer?.cornerRadius = 0
      contentView.layer?.masksToBounds = false
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // Re-apply after super.awakeFromNib() in case it resets layer properties.
    // Also zero out the window-level corner radius that macOS 11+ enforces.
    self.contentView?.layer?.cornerRadius = 0
    self.contentView?.layer?.masksToBounds = false

    // Register MethodChannel for scroll events
    let channel = FlutterMethodChannel(
      name: "app.pod/menu_bar_scroll",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      if call.method == "showInactive" {
        // Show window on screen without activating the app or stealing focus
        self.orderFront(nil)
        result(nil)
      } else if call.method == "focusWindow" {
        // Focus the panel without promoting the app into the app switcher.
        self.makeKeyAndOrderFront(nil)
        result(nil)
      } else if call.method == "savePreviousApp" {
        // Remember the currently frontmost app (excluding our own) before we steal focus
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
          self.previousFrontmostApp = frontmost
        }
        result(nil)
      } else if call.method == "restorePreviousApp" {
        self.restorePreviousFrontmostApp()
        result(nil)
      } else if call.method == "getCurrentScreenInfo" {
        // Return the frame of the screen containing the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen = NSScreen.main ?? NSScreen.screens[0]
        for screen in NSScreen.screens {
          if screen.frame.contains(mouseLocation) {
            targetScreen = screen
            break
          }
        }
        let frame = targetScreen.frame
        let visibleFrame = targetScreen.visibleFrame
        let primaryHeight = NSScreen.screens[0].frame.height
        // Convert to Flutter top-left coordinates
        let resultDict: [String: Any] = [
          "x": frame.origin.x,
          "y": primaryHeight - frame.origin.y - frame.height,
          "width": frame.width,
          "height": frame.height,
          "visibleY": primaryHeight - visibleFrame.origin.y - visibleFrame.height,
          "visibleHeight": visibleFrame.height,
        ]
        result(resultDict)
      } else if call.method == "setWindowFrameOnScreen" {
        guard let args = call.arguments as? [String: Any],
              let x = args["x"] as? Double,
              let y = args["y"] as? Double,
              let width = args["width"] as? Double,
              let height = args["height"] as? Double else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
          return
        }
        let primaryHeight = NSScreen.screens[0].frame.height
        let macY = primaryHeight - y - height
        self.setFrame(NSRect(x: x, y: macY, width: width, height: height), display: true)
        result(nil)
      } else if call.method == "expandOnScreen" {
        guard let args = call.arguments as? [String: Any],
              let x = args["x"] as? Double,
              let y = args["y"] as? Double,
              let width = args["width"] as? Double,
              let height = args["height"] as? Double else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
          return
        }
        let shouldFocus = args["focus"] as? Bool ?? false
        if shouldFocus {
          if let frontmost = NSWorkspace.shared.frontmostApplication,
             frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousFrontmostApp = frontmost
          }
        }
        let primaryHeight = NSScreen.screens[0].frame.height
        let macY = primaryHeight - y - height
        
        // Instantly set correct frame width to avoid lag/jump before Flutter animation starts
        self.setFrame(NSRect(x: x, y: macY, width: width, height: height), display: false)
        self.hasShadow = false
        
        if shouldFocus {
          self.makeKeyAndOrderFront(nil)
        } else {
          self.orderFront(nil)
        }
        
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Register MethodChannel for clipboard owner info (app icon and name)
    let clipboardOwnerChannel = FlutterMethodChannel(
      name: "app.pod/clipboard_owner",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    clipboardOwnerChannel.setMethodCallHandler { (call, result) in
      if call.method == "getClipboardChangeCount" {
        result(NSPasteboard.general.changeCount)
      } else if call.method == "getClipboardOwner" {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
          result([String: Any]())
          return
        }
        
        let appName = frontmostApp.localizedName ?? "Unknown"
        var iconPath = ""
        
        if let icon = frontmostApp.icon {
          if let tiffData = icon.tiffRepresentation,
             let bitmapImage = NSBitmapImageRep(data: tiffData),
             let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            let tempDir = FileManager.default.temporaryDirectory
            let iconsDir = tempDir.appendingPathComponent("pod_icons")
            try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true, attributes: nil)
            let destURL = iconsDir.appendingPathComponent("\(appName).png")
            do {
              try pngData.write(to: destURL)
              iconPath = destURL.path
            } catch {
              // ignore
            }
          }
        }
        
        var response = [String: Any]()
        response["name"] = appName
        response["iconPath"] = iconPath
        result(response)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let fileOpenerChannel = FlutterMethodChannel(
      name: "app.pod/file_opener",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    fileOpenerChannel.setMethodCallHandler { (call, result) in
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            !path.isEmpty else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
        return
      }

      guard FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(code: "NOT_FOUND", message: "Path does not exist", details: path))
        return
      }

      let url = URL(fileURLWithPath: path)
      if call.method == "openPath" {
        result(NSWorkspace.shared.open(url))
      } else if call.method == "revealPath" {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let launchAtStartupChannel = FlutterMethodChannel(
      name: "app.pod/launch_at_startup",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    launchAtStartupChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      if call.method == "isEnabled" {
        result(self.isLaunchAtStartupEnabled())
      } else if call.method == "setEnabled" {
        guard let args = call.arguments as? [String: Any],
              let enabled = args["enabled"] as? Bool else {
          result(FlutterError(
            code: "INVALID_ARGS",
            message: "Missing enabled flag",
            details: nil
          ))
          return
        }
        do {
          try self.setLaunchAtStartupEnabled(enabled)
          result(enabled)
        } catch {
          result(FlutterError(
            code: "STARTUP_UPDATE_FAILED",
            message: "Failed to update launch-at-startup setting",
            details: error.localizedDescription
          ))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      self?.handleScrollEvent(event, channel: channel)
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      self?.handleScrollEvent(event, channel: channel)
      return event
    }
  }

  deinit {
    if let monitor = globalMonitor {
      NSEvent.removeMonitor(monitor)
    }
    if let monitor = localMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  private func getTopEdgeScreen() -> NSScreen? {
    let mouseLoc = NSEvent.mouseLocation
    for screen in NSScreen.screens {
      let frame = screen.frame
      // Check if mouse is within the top 20 pixels of the screen
      if mouseLoc.x >= frame.minX && mouseLoc.x <= frame.maxX &&
         mouseLoc.y >= frame.maxY - 20.0 && mouseLoc.y <= frame.maxY {
        return screen
      }
    }
    return nil
  }

  private func handleScrollEvent(_ event: NSEvent, channel: FlutterMethodChannel) {
    guard let targetScreen = getTopEdgeScreen() else { return }

    let deltaY = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
    guard deltaY != 0 else { return }

    // Only throttle expand (dy > 0), let collapse (dy < 0) pass through
    if deltaY > 0 {
      let now = ProcessInfo.processInfo.systemUptime
      if now - lastScrollTime < 0.2 { return }
      lastScrollTime = now
    }

    let frame = targetScreen.frame
    let visibleFrame = targetScreen.visibleFrame
    let primaryHeight = NSScreen.screens[0].frame.height
    let args: [String: Any] = [
      "dy": deltaY,
      "x": frame.origin.x,
      "y": primaryHeight - frame.origin.y - frame.height,
      "width": frame.width,
      "height": frame.height,
      "visibleY": primaryHeight - visibleFrame.origin.y - visibleFrame.height,
      "visibleHeight": visibleFrame.height,
    ]
    channel.invokeMethod("onMenuBarScroll", arguments: args)
  }

  private var launchAgentIdentifier: String {
    let bundleIdentifier =
      Bundle.main.bundleIdentifier ?? "com.liceal.unclutter.pod"
    return "\(bundleIdentifier).launchAtStartup"
  }

  private var launchAgentURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library")
      .appendingPathComponent("LaunchAgents")
      .appendingPathComponent("\(launchAgentIdentifier).plist")
  }

  private func isLaunchAtStartupEnabled() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentURL.path)
  }

  private func setLaunchAtStartupEnabled(_ enabled: Bool) throws {
    let fileManager = FileManager.default
    let url = launchAgentURL

    if !enabled {
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
      }
      return
    }

    let launchAgentsDir = url.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: launchAgentsDir,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let appPath = Bundle.main.bundlePath
    let plist: [String: Any] = [
      "Label": launchAgentIdentifier,
      "ProgramArguments": ["/usr/bin/open", appPath],
      "RunAtLoad": true,
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    try data.write(to: url, options: .atomic)
  }
}
