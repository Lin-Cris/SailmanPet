import AppKit
import Darwin
import QuartzCore

private struct PetConfig: Decodable {
    let spritesheetPath: String
    let externalStates: ExternalStates
}

private struct ExternalStates: Decodable {
    let stateFile: String
    let overrideFile: String?
    let pollIntervalMs: Int
    let fallbackState: String
    let states: [String: ExternalState]
}

private struct ExternalState: Decodable {
    let imagePath: String
    let framesDirectory: String?
    let framePattern: String?
    let frameCount: Int?
    let fps: Double?
    let animation: Motion?
}

private struct Motion: Decodable {
    let type: String
    let amplitudePx: Double
    let periodMs: Double
}

private struct StateRecord: Decodable {
    let state: String
    let pid: Int32?
}

private enum PetLayout {
    // A 52×52 slot renders the 192×208 atlas cell at exactly 48×52 (25%).
    static let displaySize = NSSize(width: 52, height: 52)
    static let windowPadding: CGFloat = 8
    static let windowSize = NSSize(
        width: displaySize.width + windowPadding * 2,
        height: displaySize.height + windowPadding * 2
    )
}

private final class PetController: NSObject, NSApplicationDelegate {
    private let projectDirectory: URL
    private let config: PetConfig
    private let imageView = NSImageView()
    private let transitionImageView = NSImageView()
    private var window: NSWindow!
    private var pollTimer: Timer?
    private var motionTimer: Timer?
    private var currentState = ""
    private var motion: Motion?
    private var frames: [NSImage] = []
    private var frameRate = 8.0
    private var frameIndex = 0
    private var stateScale: CGFloat = 1
    private var sequenceCache: [String: [NSImage]] = [:]
    private var transitionStartedAt: TimeInterval?
    private var motionStartedAt = ProcessInfo.processInfo.systemUptime

    init(projectDirectory: URL) throws {
        self.projectDirectory = projectDirectory
        let configURL = projectDirectory.appendingPathComponent("pet.json")
        self.config = try JSONDecoder().decode(
            PetConfig.self,
            from: Data(contentsOf: configURL)
        )
        super.init()
        let runtimeDirectory = projectDirectory.appendingPathComponent(".runtime")
        try? FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true
        )
        try? "LuffyPet runtime v2; project=\(projectDirectory.path)\n"
            .write(
                to: runtimeDirectory.appendingPathComponent("renderer.log"),
                atomically: true,
                encoding: .utf8
            )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = PetLayout.windowSize
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        for view in [imageView, transitionImageView] {
            view.frame = NSRect(
                x: PetLayout.windowPadding,
                y: PetLayout.windowPadding,
                width: PetLayout.displaySize.width,
                height: PetLayout.displaySize.height
            )
            view.imageScaling = .scaleProportionallyUpOrDown
            view.imageAlignment = .alignCenter
            view.wantsLayer = true
            window.contentView?.addSubview(view)
        }
        transitionImageView.alphaValue = 0

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameOrigin(
                NSPoint(
                    x: visible.maxX - size.width - 24,
                    y: visible.minY + 18
                )
            )
        }

        window.orderFrontRegardless()
        updateState(force: true)

        let pollInterval = max(100, config.externalStates.pollIntervalMs)
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: Double(pollInterval) / 1000,
            repeats: true
        ) { [weak self] _ in
            self?.updateState()
        }

        motionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 30.0,
            repeats: true
        ) { [weak self] _ in
            self?.animate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        motionTimer?.invalidate()
    }

    private func expandedURL(_ value: String) -> URL {
        let expanded = (value as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return projectDirectory.appendingPathComponent(expanded)
    }

    private func readRecord(at path: String?) -> StateRecord? {
        guard let path else { return nil }
        do {
            let record = try JSONDecoder().decode(
                StateRecord.self,
                from: Data(contentsOf: expandedURL(path))
            )
            if let pid = record.pid, kill(pid, 0) != 0 && errno != EPERM {
                return nil
            }
            return record
        } catch {
            return nil
        }
    }

    private func desiredState() -> String {
        if let override = readRecord(at: config.externalStates.overrideFile),
           config.externalStates.states[override.state] != nil {
            return override.state
        }
        if let automatic = readRecord(at: config.externalStates.stateFile),
           config.externalStates.states[automatic.state] != nil {
            return automatic.state
        }
        return config.externalStates.fallbackState
    }

    private func updateState(force: Bool = false) {
        let desired = desiredState()
        guard force || desired != currentState else { return }
        currentState = desired
        motionStartedAt = ProcessInfo.processInfo.systemUptime
        frameIndex = 0
        imageView.layer?.setAffineTransform(.identity)

        if let external = config.externalStates.states[desired] {
            // Seated external poses have a naturally shorter visible silhouette than
            // the jumping idle frame. Normalize their visible envelope inside the
            // same 52×52 slot without changing aspect ratio.
            stateScale = 1.06
            let sequence = loadFrameSequence(for: desired, config: external)
            if let sequence {
                frames = sequence
                frameRate = max(1, external.fps ?? 8)
                motion = external.animation
                setDisplayedImage(sequence[0], animated: !currentState.isEmpty)
                fputs(
                    "LuffyPet: state \(desired), 8-frame sequence at \(frameRate) fps\n",
                    stderr
                )
                log("state=\(desired) mode=sequence frames=\(sequence.count)")
            } else {
                frames = []
                let imageURL = projectDirectory.appendingPathComponent(external.imagePath)
                let image = NSImage(contentsOf: imageURL).map(trimmedImage)
                motion = external.animation
                setDisplayedImage(image, animated: !currentState.isEmpty)
                fputs(
                    "LuffyPet: state \(desired), static fallback with breathing\n",
                    stderr
                )
                log("state=\(desired) mode=fallback imageLoaded=\(image != nil)")
            }
            imageView.layer?.setAffineTransform(
                CGAffineTransform(scaleX: stateScale, y: stateScale)
            )
        } else {
            stateScale = 1
            frames = []
            motion = nil
            setDisplayedImage(idleFrame(), animated: !currentState.isEmpty)
            fputs("LuffyPet: state idle, spritesheet frame\n", stderr)
            log("state=idle mode=spritesheet")
        }
    }

    private func loadFrameSequence(
        for state: String,
        config: ExternalState
    ) -> [NSImage]? {
        if let cached = sequenceCache[state] {
            return cached
        }
        guard
            let directory = config.framesDirectory,
            let pattern = config.framePattern,
            let count = config.frameCount,
            count > 0
        else {
            return nil
        }

        let directoryURL = projectDirectory.appendingPathComponent(directory)
        var loaded: [NSImage] = []
        for index in 0..<count {
            let filename = String(format: pattern, index)
            let url = directoryURL.appendingPathComponent(filename)
            guard let image = NSImage(contentsOf: url) else {
                log("sequence=\(state) missing=\(url.path)")
                return nil
            }
            loaded.append(trimmedImage(image))
        }
        sequenceCache[state] = loaded
        return loaded
    }

    private func trimmedImage(_ image: NSImage) -> NSImage {
        guard let source = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return image
        }

        let width = source.width
        let height = source.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * bytesPerRow + x * 4 + 3] >= 8 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }

        let contentWidth = maxX - minX + 1
        let contentHeight = maxY - minY + 1
        let padding = max(8, Int(Double(max(contentWidth, contentHeight)) * 0.02))
        let cropX = max(0, minX - padding)
        let cropY = max(0, minY - padding)
        let cropMaxX = min(width, maxX + padding + 1)
        let cropMaxY = min(height, maxY + padding + 1)
        let cropRect = CGRect(
            x: cropX,
            y: cropY,
            width: cropMaxX - cropX,
            height: cropMaxY - cropY
        )
        guard let cropped = source.cropping(to: cropRect) else { return image }
        return NSImage(
            cgImage: cropped,
            size: NSSize(width: cropped.width, height: cropped.height)
        )
    }

    private func setDisplayedImage(_ image: NSImage?, animated: Bool) {
        guard animated, let previous = imageView.image else {
            imageView.image = image
            imageView.alphaValue = 1
            transitionImageView.image = nil
            transitionImageView.alphaValue = 0
            return
        }

        transitionImageView.image = previous
        transitionImageView.alphaValue = 1
        imageView.image = image
        imageView.alphaValue = 1
        transitionStartedAt = ProcessInfo.processInfo.systemUptime
        log("transition started targetLoaded=\(image != nil)")
    }

    private func idleFrame() -> NSImage? {
        let atlasURL = projectDirectory.appendingPathComponent(config.spritesheetPath)
        guard
            let atlas = NSImage(contentsOf: atlasURL),
            let cgImage = atlas.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            ),
            let cropped = cgImage.cropping(
                to: CGRect(x: 0, y: 0, width: 192, height: 208)
            )
        else {
            return nil
        }
        return NSImage(cgImage: cropped, size: NSSize(width: 192, height: 208))
    }

    private func animate() {
        updateTransition()

        if !frames.isEmpty {
            let elapsed =
                ProcessInfo.processInfo.systemUptime - motionStartedAt
            let nextIndex = Int(elapsed * frameRate) % frames.count
            if nextIndex != frameIndex {
                frameIndex = nextIndex
                imageView.image = frames[nextIndex]
            }
        }

        guard let motion, motion.type == "breathing" else { return }
        let elapsedMs =
            (ProcessInfo.processInfo.systemUptime - motionStartedAt) * 1000
        let phase = elapsedMs / max(250, motion.periodMs) * 2 * Double.pi
        let bob = CGFloat(sin(phase) * motion.amplitudePx)
        let scale =
            stateScale * CGFloat(1 + 0.004 * sin(phase - Double.pi / 2))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.layer?.setAffineTransform(
            CGAffineTransform(translationX: 0, y: bob)
                .scaledBy(x: scale, y: scale)
        )
        CATransaction.commit()
    }

    private func updateTransition() {
        guard let startedAt = transitionStartedAt else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let progress = min(1, max(0, elapsed / 0.16))
        let eased = progress * progress * (3 - 2 * progress)
        transitionImageView.alphaValue = CGFloat(1 - eased)
        if progress >= 1 {
            imageView.alphaValue = 1
            transitionImageView.alphaValue = 0
            transitionImageView.image = nil
            transitionStartedAt = nil
            log("transition completed")
        }
    }

    private func log(_ message: String) {
        let url = projectDirectory
            .appendingPathComponent(".runtime")
            .appendingPathComponent("renderer.log")
        guard let data = "\(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                return
            }
        }
    }
}

private let projectDirectory: URL = {
    if let explicit = CommandLine.arguments.dropFirst().first {
        return URL(fileURLWithPath: explicit, isDirectory: true)
    }
    if Bundle.main.bundleURL.pathExtension == "app" {
        return Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
    return URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}()

do {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let controller = try PetController(projectDirectory: projectDirectory)
    application.delegate = controller
    application.run()
} catch {
    fputs("LuffyPet: \(error)\n", stderr)
    exit(1)
}
