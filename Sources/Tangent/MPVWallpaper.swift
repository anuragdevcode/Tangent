import AppKit
import Darwin
import OpenGL.GL3

extension Notification.Name {
    /// Posted when libmpv cannot decode a file, so the menu can explain why the
    /// desktop stayed black instead of failing silently.
    static let tangentMPVFailed = Notification.Name("tangent.mpv.failed")

    /// Posted when libmpv is not installed/loadable on this machine.
    static let tangentMPVUnavailable = Notification.Name("tangent.mpv.unavailable")
}

/// Video backend for formats AVFoundation cannot decode.
///
/// libmpv covers what AVFoundation cannot. On Apple Silicon AVFoundation is
/// the efficient default for H.264/HEVC, but it has no VP9 decoder and no
/// reliable AV1 decoder on older chips. This class embeds libmpv (Homebrew) and
/// draws through its OpenGL render API into an `NSOpenGLView`, which the engine
/// puts in the desktop-level window.
///
/// All libmpv calls happen on the main thread except `mpv_wait_event`, which
/// runs on a dedicated thread. Diagnostics are published on the main thread so
/// the CLI probe can read them without locking.
final class MPVWallpaper: Wallpaper {
    let type: WallpaperType = .video
    let view: NSView
    private(set) var isLoaded = false

    /// Filled in after `MPV_EVENT_FILE_LOADED`; used by `--probe-mpv`.
    private(set) var codecName: String?
    private(set) var videoSize: CGSize?
    private(set) var renderedFrames = 0
    private(set) var lastRenderError: Int32 = 0

    /// Where libmpv was loaded from (bundled copy or Homebrew).
    var libraryPath: String { api.path }

    private let api: MPVAPI
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    private var glView: MPVOpenGLView!
    private var eventThread: Thread?
    private var stopping = false
    private let stateLock = NSLock()
    private var updateScheduled = false
    private let muted: Bool

    init?(url: URL, muted: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let api = MPVAPI.shared else {
            NSLog("Tangent: libmpv not available; install it with `brew install mpv`")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .tangentMPVUnavailable, object: nil)
            }
            return nil
        }
        self.api = api
        self.muted = muted

        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAOpenGLProfile),
            NSOpenGLPixelFormatAttribute(NSOpenGLProfileVersion3_2Core),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), 24,
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAlphaSize), 8,
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAccelerated),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFANoRecovery),
            0,
        ]
        guard let format = NSOpenGLPixelFormat(attributes: attributes) else {
            NSLog("Tangent: no OpenGL pixel format for mpv")
            return nil
        }
        guard let glView = MPVOpenGLView(frame: .zero, pixelFormat: format) else {
            NSLog("Tangent: could not create mpv OpenGL view")
            return nil
        }
        self.glView = glView
        self.view = glView
        glView.wallpaper = self
        glView.wantsBestResolutionOpenGLSurface = true

        guard let handle = api.create() else {
            NSLog("Tangent: mpv_create failed")
            return nil
        }
        mpv = handle

        setOption("vo", "libmpv")
        setOption("hwdec", "auto-safe")
        setOption("loop-file", "inf")
        setOption("keep-open", "no")
        setOption("idle", "yes")
        setOption("osc", "no")
        setOption("input-default-bindings", "no")
        setOption("input-vo-keyboard", "no")
        setOption("audio-display", "no")
        setOption("terminal", "no")
        setOption("msg-level", "all=warn")
        setOption("mute", muted ? "yes" : "no")
        setOption("panscan", "1.0")

        guard api.initialize(handle) >= 0 else {
            NSLog("Tangent: mpv_initialize failed")
            api.terminateDestroy(handle)
            mpv = nil
            return nil
        }

        glView.openGLContext?.makeCurrentContext()
        guard createRenderContext() >= 0, let renderContext else {
            NSLog("Tangent: mpv render context creation failed")
            api.terminateDestroy(handle)
            mpv = nil
            return nil
        }
        api.renderSetUpdateCallback(
            renderContext,
            mpvRenderUpdate,
            Unmanaged.passUnretained(self).toOpaque()
        )

        startEventLoop()
        load(url)
        isLoaded = true
    }

    deinit {
        close()
    }

    // MARK: - Wallpaper

    func play() {
        setPause(false)
    }

    func pause() {
        setPause(true)
    }

    func setMuted(_ muted: Bool) {
        guard let mpv else { return }
        var flag: Int32 = muted ? 1 : 0
        api.setProperty(mpv, "mute", MPV_FORMAT_FLAG, &flag)
    }

    func close() {
        stateLock.lock()
        if stopping {
            stateLock.unlock()
            return
        }
        stopping = true
        stateLock.unlock()

        if let renderContext {
            api.renderSetUpdateCallback(renderContext, nil, nil)
            api.renderFree(renderContext)
            self.renderContext = nil
        }
        if let mpv {
            api.terminateDestroy(mpv)
            self.mpv = nil
        }
        glView?.removeFromSuperview()
        isLoaded = false
    }

    // MARK: - Setup

    private func setOption(_ name: String, _ value: String) {
        guard let mpv else { return }
        let result = api.setOptionString(mpv, name, value)
        if result < 0 {
            NSLog("Tangent: mpv option %@=%@ rejected (%d)", name, value, result)
        }
    }

    private func createRenderContext() -> Int32 {
        guard let mpv else { return -1 }
        let apiType = strdup("opengl")!
        defer { free(apiType) }

        let apiParam = mpv_render_param(
            type: MPV_RENDER_PARAM_API_TYPE,
            data: UnsafeMutableRawPointer(apiType)
        )
        var glInit = mpv_opengl_init_params(
            get_proc_address: mpvGetProcAddress,
            get_proc_address_ctx: nil
        )
        return withUnsafeMutablePointer(to: &glInit) { glInitPointer in
            let initParam = mpv_render_param(
                type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                data: UnsafeMutableRawPointer(glInitPointer)
            )
            let terminator = mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            var params = [apiParam, initParam, terminator]
            return params.withUnsafeMutableBufferPointer { buffer in
                api.renderCreate(&renderContext, mpv, buffer.baseAddress)
            }
        }
    }

    private func load(_ url: URL) {
        guard let mpv else { return }
        let arguments = ["loadfile", url.path, "replace"]
        var pointers: [UnsafePointer<CChar>?] = arguments.map { argument in
            guard let copy = strdup(argument) else { return nil }
            return UnsafePointer(copy)
        }
        pointers.append(nil)

        let result = pointers.withUnsafeMutableBufferPointer { buffer in
            api.command(mpv, buffer.baseAddress)
        }
        for pointer in pointers {
            if let pointer { free(UnsafeMutablePointer(mutating: pointer)) }
        }
        if result < 0 {
            NSLog("Tangent: mpv loadfile failed (%d)", result)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .tangentMPVFailed,
                    object: nil,
                    userInfo: ["path": url.path]
                )
            }
        }
    }

    private func setPause(_ paused: Bool) {
        guard let mpv else { return }
        var flag: Int32 = paused ? 1 : 0
        api.setProperty(mpv, "pause", MPV_FORMAT_FLAG, &flag)
    }

    // MARK: - Event loop

    private func startEventLoop() {
        let thread = Thread { [weak self] in
            self?.runEventLoop()
        }
        thread.name = "Tangent mpv events"
        thread.start()
        eventThread = thread
    }

    private func runEventLoop() {
        while !isStopping {
            guard let mpv else { return }
            guard let event = api.waitEvent(mpv, 0.25) else { continue }

            switch event.pointee.event_id.rawValue {
            case MPV_EVENT_FILE_LOADED.rawValue:
                publishTrackInfo()
            case MPV_EVENT_END_FILE.rawValue:
                handleEndFile(event)
            case MPV_EVENT_SHUTDOWN.rawValue:
                return
            default:
                break
            }
        }
    }

    private var isStopping: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopping
    }

    private func handleEndFile(_ event: UnsafePointer<mpv_event>) {
        guard let raw = event.pointee.data else { return }
        let end = raw.assumingMemoryBound(to: mpv_event_end_file.self).pointee
        guard end.reason.rawValue == MPV_END_FILE_REASON_ERROR.rawValue else { return }
        let code = end.error
        DispatchQueue.main.async {
            NSLog("Tangent: mpv decode ended with error %d", code)
            NotificationCenter.default.post(
                name: .tangentMPVFailed,
                object: nil,
                userInfo: ["error": Int(code)]
            )
        }
    }

    /// Reads codec and size after the file is open. Property access is cheap and
    /// only happens once per file, so no observation plumbing is needed.
    private func publishTrackInfo() {
        guard let mpv else { return }

        var codec: String?
        var codecPointer: UnsafeMutablePointer<CChar>?
        if api.getProperty(mpv, "video-codec", MPV_FORMAT_STRING, &codecPointer) >= 0,
           let codecPointer {
            codec = String(cString: codecPointer)
            api.free(codecPointer)
        }

        var width: Int64 = 0
        var height: Int64 = 0
        _ = api.getProperty(mpv, "width", MPV_FORMAT_INT64, &width)
        _ = api.getProperty(mpv, "height", MPV_FORMAT_INT64, &height)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.codecName = codec
            if width > 0, height > 0 {
                self.videoSize = CGSize(width: Int(width), height: Int(height))
            }
        }
    }

    // MARK: - Rendering

    fileprivate func requestRender() {
        stateLock.lock()
        if updateScheduled || stopping {
            stateLock.unlock()
            return
        }
        updateScheduled = true
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            self.updateScheduled = false
            self.stateLock.unlock()
            self.glView?.needsDisplay = true
        }
    }

    fileprivate func renderFrame() {
        guard let renderContext else { return }
        guard let context = glView.openGLContext else { return }
        context.makeCurrentContext()

        let backing = glView.convertToBacking(glView.bounds)
        let width = Int32(max(backing.width, 1))
        let height = Int32(max(backing.height, 1))

        var fbo = mpv_opengl_fbo(fbo: 0, w: width, h: height, internal_format: 0)
        var flip: Int32 = 1
        let status: Int32 = withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flip) { flipPointer in
                let fboParam = mpv_render_param(
                    type: MPV_RENDER_PARAM_OPENGL_FBO,
                    data: UnsafeMutableRawPointer(fboPointer)
                )
                let flipParam = mpv_render_param(
                    type: MPV_RENDER_PARAM_FLIP_Y,
                    data: UnsafeMutableRawPointer(flipPointer)
                )
                let terminator = mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                var params = [fboParam, flipParam, terminator]
                return params.withUnsafeMutableBufferPointer { buffer in
                    api.render(renderContext, buffer.baseAddress)
                }
            }
        }

        if status < 0 {
            if lastRenderError == 0 {
                NSLog("Tangent: mpv render failed (%d)", status)
            }
            lastRenderError = status
            return
        }

        context.flushBuffer()
        api.reportSwap(renderContext)
        renderedFrames += 1
    }
}

// MARK: - OpenGL view

/// `NSOpenGLView` whose draw call is driven by mpv's update callback.
private final class MPVOpenGLView: NSOpenGLView {
    weak var wallpaper: MPVWallpaper?

    override func prepareOpenGL() {
        super.prepareOpenGL()
        var swapInterval: GLint = 1
        openGLContext?.setValues(&swapInterval, for: .swapInterval)
    }

    override func draw(_ dirtyRect: NSRect) {
        wallpaper?.renderFrame()
    }

    override func reshape() {
        super.reshape()
        needsDisplay = true
    }

    override var isOpaque: Bool { true }
}

// MARK: - C callbacks

/// libmpv asks for GL entry points by name; macOS resolves them from the loaded
/// OpenGL framework.
private func mpvGetProcAddress(
    _ context: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    // RTLD_DEFAULT is a C macro Swift does not import; its value is -2.
    return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
}

/// Called by mpv's render thread whenever a new frame is ready.
private func mpvRenderUpdate(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let wallpaper = Unmanaged<MPVWallpaper>.fromOpaque(context).takeUnretainedValue()
    wallpaper.requestRender()
}
