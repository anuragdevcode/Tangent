import Darwin
import Foundation

/// Runtime loader for libmpv.
///
/// The Homebrew bottle declares a minimum OS newer than Tangent's deployment
/// target, and a hard link would make the whole app refuse to launch on older
/// macOS versions. Loading it lazily keeps AVFoundation/H.264 wallpapers
/// working everywhere while VP9/AV1 support appears when `libmpv` is present.
///
/// Set `TANGENT_LIBMPV` to override the dylib path.
struct MPVAPI {    typealias Create = @convention(c) () -> OpaquePointer?
    typealias SetOptionString = @convention(c) (
        OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?
    ) -> Int32
    typealias Initialize = @convention(c) (OpaquePointer?) -> Int32
    typealias TerminateDestroy = @convention(c) (OpaquePointer?) -> Void
    typealias Command = @convention(c) (
        OpaquePointer?, UnsafeMutablePointer<UnsafePointer<CChar>?>?
    ) -> Int32
    typealias WaitEvent = @convention(c) (
        OpaquePointer?, Double
    ) -> UnsafePointer<mpv_event>?
    typealias GetProperty = @convention(c) (
        OpaquePointer?, UnsafePointer<CChar>?, mpv_format, UnsafeMutableRawPointer?
    ) -> Int32
    typealias SetProperty = @convention(c) (
        OpaquePointer?, UnsafePointer<CChar>?, mpv_format, UnsafeMutableRawPointer?
    ) -> Int32
    typealias Free = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias RenderCreate = @convention(c) (
        UnsafeMutablePointer<OpaquePointer?>?, OpaquePointer?,
        UnsafeMutablePointer<mpv_render_param>?
    ) -> Int32
    typealias RenderSetUpdateCallback = @convention(c) (
        OpaquePointer?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias RenderFree = @convention(c) (OpaquePointer?) -> Void
    typealias Render = @convention(c) (
        OpaquePointer?, UnsafeMutablePointer<mpv_render_param>?
    ) -> Int32
    typealias ReportSwap = @convention(c) (OpaquePointer?) -> Void

    let create: Create
    let setOptionString: SetOptionString
    let initialize: Initialize
    let terminateDestroy: TerminateDestroy
    let command: Command
    let waitEvent: WaitEvent
    let getProperty: GetProperty
    let setProperty: SetProperty
    let free: Free
    let renderCreate: RenderCreate
    let renderSetUpdateCallback: RenderSetUpdateCallback
    let renderFree: RenderFree
    let render: Render
    let reportSwap: ReportSwap

    /// Absolute path of the dylib that was loaded; reported by `--probe-mpv`
    /// so bundled builds can be distinguished from Homebrew fallbacks.
    let path: String

    static let shared: MPVAPI? = load()

    private static func load() -> MPVAPI? {
        let candidates: [String]
        if let override = ProcessInfo.processInfo.environment["TANGENT_LIBMPV"] {
            // An explicit override is exclusive: it makes "libmpv missing"
            // reproducible for testing instead of silently using the default.
            candidates = [override]
        } else {
            // The bundled copy always wins: it is the signed, self-contained
            // library that matches the app.
            candidates = bundledCandidates() + [
                "/opt/homebrew/opt/mpv/lib/libmpv.2.dylib",
                "/opt/homebrew/lib/libmpv.2.dylib",
                "/usr/local/opt/mpv/lib/libmpv.2.dylib",
                "/usr/local/lib/libmpv.2.dylib",
            ]
        }

        for path in candidates {
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { continue }
            guard let api = build(from: handle, path: path) else {
                dlclose(handle)
                continue
            }
            return api
        }
        return nil
    }

    /// `Tangent.app/Contents/Frameworks/libmpv.2.dylib`, with a
    /// path-relative fallback for hand-assembled bundles.
    private static func bundledCandidates() -> [String] {
        var result: [String] = []
        if let frameworks = Bundle.main.privateFrameworksURL {
            result.append(frameworks.appendingPathComponent("libmpv.2.dylib").path)
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        let relative = executable
            .deletingLastPathComponent()   // Contents/MacOS
            .deletingLastPathComponent()   // Contents
            .appendingPathComponent("Frameworks/libmpv.2.dylib")
        if !result.contains(relative.path) {
            result.append(relative.path)
        }
        return result
    }

    private static func build(from handle: UnsafeMutableRawPointer, path: String) -> MPVAPI? {
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        guard let create = symbol("mpv_create", as: Create.self),
              let setOptionString = symbol("mpv_set_option_string", as: SetOptionString.self),
              let initialize = symbol("mpv_initialize", as: Initialize.self),
              let terminateDestroy = symbol("mpv_terminate_destroy", as: TerminateDestroy.self),
              let command = symbol("mpv_command", as: Command.self),
              let waitEvent = symbol("mpv_wait_event", as: WaitEvent.self),
              let getProperty = symbol("mpv_get_property", as: GetProperty.self),
              let setProperty = symbol("mpv_set_property", as: SetProperty.self),
              let free = symbol("mpv_free", as: Free.self),
              let renderCreate = symbol("mpv_render_context_create", as: RenderCreate.self),
              let renderSetUpdateCallback = symbol(
                  "mpv_render_context_set_update_callback",
                  as: RenderSetUpdateCallback.self
              ),
              let renderFree = symbol("mpv_render_context_free", as: RenderFree.self),
              let render = symbol("mpv_render_context_render", as: Render.self),
              let reportSwap = symbol("mpv_render_context_report_swap", as: ReportSwap.self)
        else { return nil }

        return MPVAPI(
            create: create,
            setOptionString: setOptionString,
            initialize: initialize,
            terminateDestroy: terminateDestroy,
            command: command,
            waitEvent: waitEvent,
            getProperty: getProperty,
            setProperty: setProperty,
            free: free,
            renderCreate: renderCreate,
            renderSetUpdateCallback: renderSetUpdateCallback,
            renderFree: renderFree,
            render: render,
            reportSwap: reportSwap,
            path: path
        )
    }
}
