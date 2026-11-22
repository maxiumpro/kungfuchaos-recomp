// Kung Fu Chaos launcher for macOS (native recompilation, Metal).
// One config shared with the in-game menu: ~/Games/KFC/config.toml (render/present/display),
// plus ~/Games/KFC/launcher.ini for the options that are passed as environment variables.
// Build: zsh build.sh   (swiftc -O -parse-as-library KFCLauncher.swift -o KFCLauncher)
import SwiftUI
import AppKit
import CryptoKit

let K = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Games/KFC")
let tomlURL = K.appendingPathComponent("config.toml")
let iniURL = K.appendingPathComponent("launcher.ini")
let logURL = K.appendingPathComponent("log.txt")
// Game Mode (KFC-1230): the game's own bundle, and the SHA-256 of the build/kfc_recomp it was made from.
// The hash lives OUTSIDE the bundle: nothing may be written inside a signed .app, and codesign changes the
// binary's bytes, so the bundle's copy never hashes like build/kfc_recomp.
let gameBundleURL = K.appendingPathComponent("KFC Game.app")
let gameBundleSrcURL = K.appendingPathComponent("KFC Game.app.src")
// Built in a hidden work folder under its final .app name, then moved into place.
let gameBundleNewDir = K.appendingPathComponent(".kfc-game-new")
let gameBundleNewURL = gameBundleNewDir.appendingPathComponent("KFC Game.app")

// MARK: - TOML (minimal, in place)

func tableName(_ line: String) -> String? {
    guard line.hasPrefix("["), !line.hasPrefix("[["), let close = line.firstIndex(of: "]") else { return nil }
    return String(line[line.index(after: line.startIndex)..<close]).trimmingCharacters(in: .whitespaces)
}

func trimmed(_ s: String) -> String {
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Returns "table.key" -> raw value (unquoted).
func parseToml(_ text: String) -> [String: String] {
    var out: [String: String] = [:]
    var table = ""
    for raw in text.components(separatedBy: "\n") {
        let line = trimmed(raw)
        if line.isEmpty || line.hasPrefix("#") { continue }
        if let t = tableName(line) { table = t; continue }
        guard let eq = line.firstIndex(of: "=") else { continue }
        let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
        var val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if val.hasPrefix("\"") {
            val.removeFirst()
            if let end = val.firstIndex(of: "\"") { val = String(val[..<end]) }
        } else if let h = val.firstIndex(of: "#") {
            val = String(val[..<h]).trimmingCharacters(in: .whitespaces)
        }
        out[table + "." + key] = val
    }
    return out
}

struct TomlEntry {
    let table: String
    let key: String
    let value: String   // already rendered (quoted strings, bare ints/bools)
}

/// Updates only the given keys; every other line is kept as it was. Never duplicates a [table].
func updateToml(_ text: String, _ entries: [TomlEntry]) -> String {
    var lines = text.components(separatedBy: "\n")
    if let last = lines.last, last.isEmpty { lines.removeLast() }
    for e in entries {
        let newLine = e.key + " = " + e.value
        var start: Int? = nil
        for (i, l) in lines.enumerated() where tableName(trimmed(l)) == e.table {
            start = i
            break
        }
        guard let s = start else {
            if let last = lines.last, !trimmed(last).isEmpty { lines.append("") }
            lines.append("[" + e.table + "]")
            lines.append(newLine)
            continue
        }
        var end = lines.count
        var i = s + 1
        while i < lines.count {
            if tableName(trimmed(lines[i])) != nil { end = i; break }
            i += 1
        }
        var replaced = false
        var j = s + 1
        while j < end {
            let t = trimmed(lines[j])
            if !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") {
                let k = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
                if k == e.key { lines[j] = newLine; replaced = true; break }
            }
            j += 1
        }
        if !replaced {
            var ins = end
            while ins > s + 1 && trimmed(lines[ins - 1]).isEmpty { ins -= 1 }
            lines.insert(newLine, at: ins)
        }
    }
    return lines.joined(separator: "\n") + "\n"
}

// MARK: - Config

struct Config {
    // config.toml
    var scale = 4   // KFC-1650: 60 FPS at 4x on the M4 Air with the GPU kept busy (metal_gpu_spin)
    var aniso = 16
    var fullscreen = true
    var filter = "linear"
    var shader = "none"
    var pacing = "sleep"
    var aspect = "4:3"
    var movie = "black"
    var overscan = 0
    // launcher.ini
    var upscaler = "linear"   // 4x is above the screen: nothing to upscale
    var progressive = true
    // Off by default (21-nov): with the DSP the fights measured ~2 dB louder but
    // sounded practically the same blind, for ~4.5 ms more CPU a frame (KFC-1810).
    var dsp = false
    var pads = 4
    var player = 1
    var rumble = true
    var fps = 60
    var dof = "off"   // default: sharp background (19-nov); "off": skip the depth-of-field repaint (RECOMP_DOF_SKIP)
    // On by default (21-nov, KFC-1105b): the combiners' fragments without discard_fragment where no
    // kill can fire (metal_nodiscard=1) and with fast math (metal_fs_fastmath=1): the GPU a frame -55 % at
    // 4x, 192 flips/s at 6x, no image change measured. To go back: fastshaders=0 in launcher.ini.
    var fastShaders = true
    // "sync" by default (KFC-2045, 21-nov): only the texture-decode sync drops a dirty render target whose
    // memory the game already rewrote, instead of writing the stale target over the new texture (the bamboo
    // in the forest came out as a purple/green mosaic). Everything else behaves as rt_alias_check=0
    // (README:25). To go back: aliascheck=0 in launcher.ini.
    var aliasCheck = "sync"
    // "0" by default (KFC-0545b, 22-nov): the window's CAMetalLayer without display sync,
    // so a frame goes to the screen as soon as it is drawn instead of waiting in the 3-drawable queue. Measured on
    // the Air at 60: frame age 45.3 -> 4.1 ms, 0 repeated, 60 new frames/s. A torn image is not checked in depth,
    // and the Metal HUD shows "Direct" only sometimes. To go back: vsync=1 in launcher.ini.
    var vsync = "0"
    // "1" by default (KFC-1015, 22-nov): the Metal translator's direct lookups (a texture-key hint
    // before the cache scan, a table of combiner keys after the one-entry memo): -4.9 % of the translating thread's
    // CPU at 60 (67 of 74 block pairs lower), -0.08 W, 0 differences in 3.9 M lookups. To go back: directcache=0.
    var directCache = "1"
    // "1" by default (KFC-1230, 22-nov): the game runs as the
    // executable of its own bundle, KFC Game.app, with LSSupportsGameMode, so macOS turns Game Mode on; same
    // fullscreen as before. To go back: gamemode=0 in launcher.ini.
    var gameMode = "1"
    // Off by default: Apple's Metal performance HUD in the game (MTL_HUD_ENABLED=1), for checking only.
    var hud = false

    static func load() -> Config {
        var c = Config()
        if let t = try? String(contentsOf: tomlURL, encoding: .utf8) {
            let d = parseToml(t)
            func int(_ k: String, _ ok: [Int]) -> Int? {
                if let v = d[k], let n = Int(v), ok.contains(n) { return n }
                return nil
            }
            func str(_ k: String, _ ok: [String]) -> String? {
                if let v = d[k], ok.contains(v) { return v }
                return nil
            }
            if let v = int("render.scale", [1, 2, 3, 4]) { c.scale = v }
            if let v = int("render.aniso", [0, 2, 4, 8, 16]) { c.aniso = v }
            if let v = d["present.fullscreen"], v == "true" || v == "false" { c.fullscreen = (v == "true") }
            if let v = str("present.filter", ["linear", "nearest", "integer"]) { c.filter = v }
            if let v = str("present.shader", ["none", "fsr", "crt-lottes", "crt-lottes-fast"]) { c.shader = v }
            if let v = str("present.pacing", ["sleep", "spin"]) { c.pacing = v }
            if let v = str("display.aspect", ["4:3", "16:9"]) { c.aspect = v }
            if let v = str("display.movie", ["black", "fit", "fill"]) { c.movie = v }
            if let v = int("display.overscan", [0, 8, 16, 32]) { c.overscan = v }
        }
        if let t = try? String(contentsOf: iniURL, encoding: .utf8) {
            var d: [String: String] = [:]
            for raw in t.components(separatedBy: "\n") {
                let line = trimmed(raw)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                d[String(line[..<eq]).trimmingCharacters(in: .whitespaces)] =
                    String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            }
            if let v = d["upscaler"], v == "linear" || v == "metalfx" { c.upscaler = v }
            if let v = d["progressive"], v == "1" || v == "0" { c.progressive = (v == "1") }
            if let v = d["dsp"], v == "1" || v == "0" { c.dsp = (v == "1") }
            if let v = d["pads"], let n = Int(v), (1...4).contains(n) { c.pads = n }
            if let v = d["player"], let n = Int(v), (1...4).contains(n) { c.player = n }
            if let v = d["rumble"], v == "1" || v == "0" { c.rumble = (v == "1") }
            if let v = d["fps"], ["60", "120", "144", "240"].contains(v) { c.fps = Int(v) ?? 60 }
            if let v = d["dof"], v == "original" || v == "off" { c.dof = v }
            if let v = d["fastshaders"], v == "1" || v == "0" { c.fastShaders = (v == "1") }
            if let v = d["aliascheck"], v == "sync" || v == "0" { c.aliasCheck = v }
            if let v = d["vsync"], v == "1" || v == "0" { c.vsync = v }
            if let v = d["directcache"], v == "1" || v == "0" { c.directCache = v }
            if let v = d["gamemode"], v == "1" || v == "0" { c.gameMode = v }
            if let v = d["hud"], v == "1" || v == "0" { c.hud = (v == "1") }
        }
        return c
    }

    func save() throws {
        try FileManager.default.createDirectory(at: K, withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: tomlURL, encoding: .utf8))
            ?? "# Kung Fu Chaos settings (shared by the launcher and the in-game menu)\n"
        let entries: [TomlEntry] = [
            TomlEntry(table: "render", key: "scale", value: String(scale)),
            TomlEntry(table: "render", key: "aniso", value: String(aniso)),
            TomlEntry(table: "present", key: "fullscreen", value: fullscreen ? "true" : "false"),
            TomlEntry(table: "present", key: "filter", value: "\"" + filter + "\""),
            TomlEntry(table: "present", key: "shader", value: "\"" + shader + "\""),
            TomlEntry(table: "present", key: "pacing", value: "\"" + pacing + "\""),
            TomlEntry(table: "display", key: "aspect", value: "\"" + aspect + "\""),
            TomlEntry(table: "display", key: "movie", value: "\"" + movie + "\""),
            TomlEntry(table: "display", key: "overscan", value: String(overscan)),
        ]
        try updateToml(existing, entries).write(to: tomlURL, atomically: true, encoding: .utf8)
        let ini = [
            "# Kung Fu Chaos launcher settings",
            "upscaler=" + upscaler,
            "progressive=" + (progressive ? "1" : "0"),
            "dsp=" + (dsp ? "1" : "0"),
            "pads=" + String(pads),
            "player=" + String(player),
            "rumble=" + (rumble ? "1" : "0"),
            "fps=" + String(fps),
            "dof=" + dof,
            "fastshaders=" + (fastShaders ? "1" : "0"),
            "aliascheck=" + aliasCheck,
            "vsync=" + vsync,
            "directcache=" + directCache,
            "gamemode=" + gameMode,
            "hud=" + (hud ? "1" : "0"),
        ].joined(separator: "\n") + "\n"
        try ini.write(to: iniURL, atomically: true, encoding: .utf8)
    }

    func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Options that live in the TOML must not be set here: env vars win over the TOML.
        for k in ["RECOMP_RENDER_SCALE", "RECOMP_PRESENT_FILTER", "RECOMP_PRESENT_FULLSCREEN", "RECOMP_METAL_UPSCALE"] {
            env.removeValue(forKey: k)
        }
        env["RECOMP_GAME_FILES"] = K.appendingPathComponent("game/Kung Fu Chaos").path
        env["RECOMP_HDD_DIR"] = K.appendingPathComponent("hdd").path
        env["RECOMP_PB_BACKEND"] = "metal"
        env["RECOMP_AC97_READY"] = "1"
        env["RECOMP_VBLANK"] = "1"
        env["RECOMP_FB_WINDOW"] = "1"
        env["RECOMP_USB"] = "1"
        env["RECOMP_USB_NDP"] = "4"
        // fastshaders (KFC-1105b): fastshaders=0 in launcher.ini goes back to the stock fragments.
        // aliascheck (KFC-2045): aliascheck=0 in launcher.ini goes back to rt_alias_check=0.
        // directcache (KFC-1015): directcache=0 in launcher.ini goes back to the plain cache scans.
        env["RECOMP_DEBUG"] = "rt_alias_check=" + aliasCheck + (fastShaders ? ",metal_nodiscard=1,metal_fs_fastmath=1" : "")
            + (directCache == "1" ? ",metal_direct_cache=1" : "")
        // vsync (KFC-0545b): vsync=1 in launcher.ini goes back to the display-synced layer.
        env["RECOMP_PRESENT_VSYNC"] = vsync
        env["RECOMP_CONFIG"] = tomlURL.path
        if upscaler == "metalfx" { env["RECOMP_METAL_UPSCALE"] = "metalfx" }
        env["RECOMP_KFC_PROGRESSIVE"] = progressive ? "1" : "0"
        env["RECOMP_APU_DSP"] = dsp ? "1" : "0"
        env["RECOMP_USB_PADS"] = String(pads)
        let ports = ["2", "3", "0", "1"]
        env["RECOMP_USB_PORT"] = ports[max(1, min(4, player)) - 1]
        env["RECOMP_RUMBLE"] = rumble ? "1" : "0"
        env["RECOMP_VBLANK_HZ"] = String(fps)
        if dof == "off" { env["RECOMP_DOF_SKIP"] = "320x240,64x64" }
        if hud { env["MTL_HUD_ENABLED"] = "1" } else { env.removeValue(forKey: "MTL_HUD_ENABLED") }
        return env
    }
}

// MARK: - Game Mode bundle (KFC-1230)

struct BundleError: LocalizedError {
    let text: String
    var errorDescription: String? { return text }
}

/// Runs a tool and waits for it; returns its exit status (-1 if it could not start).
func runTool(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
    } catch {
        return -1
    }
    p.waitUntilExit()
    return p.terminationStatus
}

/// Makes sure ~/Games/KFC/KFC Game.app holds the current build/kfc_recomp, signed ad hoc.
/// Returns nil when the bundle is ready, or the error text.
func prepareGameBundle() -> String? {
    let fm = FileManager.default
    let src = K.appendingPathComponent("game-src/build/kfc_recomp")
    let data: Data
    let hash: String
    do {
        data = try Data(contentsOf: src, options: .mappedIfSafe)
        hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    } catch {
        return "could not read " + src.path + ": " + error.localizedDescription
    }
    // Up to date: same source hash, and the bundle's executable and Info.plist are there.
    if fm.fileExists(atPath: gameBundleURL.path),
       fm.fileExists(atPath: gameBundleURL.appendingPathComponent("Contents/MacOS/kfc_recomp").path),
       fm.fileExists(atPath: gameBundleURL.appendingPathComponent("Contents/Info.plist").path),
       let old = try? String(contentsOf: gameBundleSrcURL, encoding: .utf8),
       trimmed(old) == hash {
        return nil
    }
    do {
        if fm.fileExists(atPath: gameBundleNewDir.path) { try fm.removeItem(at: gameBundleNewDir) }
        let contents = gameBundleNewURL.appendingPathComponent("Contents")
        let macos = contents.appendingPathComponent("MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        // The same bytes that were hashed, so the .src always matches the copy that was signed.
        let exe = macos.appendingPathComponent("kfc_recomp")
        try data.write(to: exe)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        var info: [String: Any] = [
            "CFBundleIdentifier": "com.github.maxiumpro.kfc.game",
            "CFBundleName": "Kung Fu Chaos",
            "CFBundleExecutable": "kfc_recomp",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "LSMinimumSystemVersion": "14.0",
            "LSApplicationCategoryType": "public.app-category.action-games",
            "LSSupportsGameMode": true,
            "GCSupportsGameMode": true,
            "NSHighResolutionCapable": true,
        ]
        // Optional icon: the launcher's own, when it has one. No icon is not an error.
        if let iconFile = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
           let res = Bundle.main.resourceURL {
            for name in [iconFile, iconFile + ".icns"] {
                let icon = res.appendingPathComponent(name)
                guard fm.fileExists(atPath: icon.path) else { continue }
                let resources = contents.appendingPathComponent("Resources")
                do {
                    try fm.createDirectory(at: resources, withIntermediateDirectories: true)
                    try fm.copyItem(at: icon, to: resources.appendingPathComponent(name))
                    info["CFBundleIconFile"] = name
                } catch {
                    // No icon: the bundle works without one.
                }
                break
            }
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        // Extended attributes (e.g. on a copied icon) make codesign refuse the bundle.
        _ = runTool("/usr/bin/xattr", ["-cr", gameBundleNewURL.path])
        let signed = runTool("/usr/bin/codesign", ["--force", "-s", "-", gameBundleNewURL.path])
        if signed != 0 { throw BundleError(text: "codesign exited with status " + String(signed)) }
        let verified = runTool("/usr/bin/codesign", ["--verify", "--strict", gameBundleNewURL.path])
        if verified != 0 { throw BundleError(text: "codesign --verify exited with status " + String(verified)) }
        // Swap in the new bundle; the .src is written only once the bundle is in place.
        if fm.fileExists(atPath: gameBundleURL.path) { try fm.removeItem(at: gameBundleURL) }
        try fm.moveItem(at: gameBundleNewURL, to: gameBundleURL)
        try? fm.removeItem(at: gameBundleNewDir)
        try (hash + "\n").write(to: gameBundleSrcURL, atomically: true, encoding: .utf8)
    } catch {
        try? fm.removeItem(at: gameBundleNewDir)
        return error.localizedDescription
    }
    return nil
}

// MARK: - Model

/// True from PLAY until the game ends; read by AppDelegate so hiding the window doesn't quit the launcher.
@MainActor var gameIsRunning = false

@MainActor
final class LauncherModel: ObservableObject {
    @Published var c: Config
    @Published var running = false
    @Published var alertMessage: String? = nil
    private var hiddenWindows: [NSWindow] = []
    private var autoPlayed = false
    private var quitWhenGameEnds = false

    init() {
        if NSEvent.modifierFlags.contains(.option) {
            c = Config()   // rescue: defaults instead of the files
        } else {
            c = Config.load()
        }
    }

    func restoreDefaults() {
        c = Config()
    }

    func openLog() {
        NSWorkspace.shared.open(logURL)
    }

    func play() {
        let build = K.appendingPathComponent("game-src/build")
        let exe = build.appendingPathComponent("kfc_recomp")
        guard FileManager.default.isExecutableFile(atPath: exe.path) else {
            alertMessage = "kfc_recomp was not found at\n" + exe.path + "\n\nBuild the game first."
            return
        }
        do {
            try c.save()
        } catch {
            alertMessage = "Could not save the settings:\n" + error.localizedDescription
            return
        }
        let env = c.environment()
        // Game Mode (KFC-1230): launch KFC Game.app through LaunchServices, so the process that makes the
        // window is a bundle's executable with LSSupportsGameMode. With -W, open exits when the game does.
        // If the bundle can't be made or open can't start, the plain binary below runs, as before.
        var gameModeNote: String? = nil
        if c.gameMode == "1" {
            if let err = prepareGameBundle() {
                gameModeNote = err
            } else {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                // Start log.txt empty, as the plain-binary path does (open --stderr may append).
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                var args = ["-W", "-n", "-a", gameBundleURL.path, "--stderr", logURL.path]
                for k in env.keys.sorted() where k.hasPrefix("RECOMP_") || k.hasPrefix("MTL_") || k.hasPrefix("SDL_") {
                    args += ["--env", k + "=" + (env[k] ?? "")]
                }
                p.arguments = args
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                watchForGameEnd(p)
                do {
                    try p.run()
                    gameStarted()
                    return
                } catch {
                    gameModeNote = "open failed: " + error.localizedDescription
                }
            }
        }
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)
        if let note = gameModeNote, let h = logHandle {
            let line = "[launcher] Game Mode bundle not ready (" + note + "); running the plain binary\n"
            try? h.write(contentsOf: Data(line.utf8))
            _ = h.seekToEndOfFile()
        }
        let p = Process()
        p.executableURL = exe
        p.currentDirectoryURL = build
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        if let h = logHandle { p.standardError = h }
        watchForGameEnd(p)
        do {
            try p.run()
        } catch {
            alertMessage = "Could not start the game:\n" + error.localizedDescription
            return
        }
        gameStarted()
    }

    private func watchForGameEnd(_ p: Process) {
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.gameEnded()
                }
            }
        }
    }

    private func gameStarted() {
        running = true
        gameIsRunning = true
        hiddenWindows = NSApp.windows.filter { $0.isVisible }
        for w in hiddenWindows { w.orderOut(nil) }
    }

    /// --play (smoke test over SSH, like KFCLauncher.exe --play on Windows): press PLAY once at start,
    /// and quit the launcher when the game ends.
    func autoPlayIfAsked() {
        guard !autoPlayed, CommandLine.arguments.contains("--play") else { return }
        autoPlayed = true
        quitWhenGameEnds = true
        // One second later, so the launcher window is fully up before play() hides it: hiding it while it is
        // still appearing counts as closing the last window, and the launcher quit (KFC-1230 smoke test).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            MainActor.assumeIsolated {
                self?.play()
            }
        }
    }

    func gameEnded() {
        running = false
        gameIsRunning = false
        if quitWhenGameEnds {
            NSApp.terminate(nil)
            return
        }
        for w in hiddenWindows { w.makeKeyAndOrderFront(nil) }
        hiddenWindows = []
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - UI

let accent = Color(red: 0.87, green: 0.66, blue: 0.18)

@MainActor
struct ContentView: View {
    @StateObject private var model = LauncherModel()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("DISPLAY") {
                    Picker("Internal resolution", selection: $model.c.scale) {
                        ForEach([1, 2, 3, 4], id: \.self) { n in
                            Text("\(n)x  (\(640 * n)x\(480 * n))").tag(n)
                        }
                    }
                    .help("Renders the game at a multiple of the Xbox's 640x480. Higher is sharper and asks more of the GPU.")
                    Picker("Upscaler", selection: $model.c.upscaler) {
                        Text("MetalFX (Apple)").tag("metalfx")
                        Text("Linear").tag("linear")
                    }
                    .help("MetalFX (Apple) scales the image up to the screen with more sharpness; use it with an internal resolution below the screen's (2x or 3x on the MacBook Air).")
                    Picker("Window mode", selection: $model.c.fullscreen) {
                        Text("Fullscreen").tag(true)
                        Text("Window").tag(false)
                    }
                    .help("Fullscreen uses the screen's own resolution while the game is in front, and puts yours back when you leave.")
                    Picker("Upscaling filter", selection: $model.c.filter) {
                        Text("Smooth").tag("linear")
                        Text("Sharp pixels").tag("nearest")
                        Text("Integer (pixel perfect)").tag("integer")
                    }
                    .help("How the picture is scaled to the window.")
                    Picker("Aspect ratio", selection: $model.c.aspect) {
                        Text("4:3  (original)").tag("4:3")
                        Text("16:9  (experimental)").tag("16:9")
                    }
                    .help("Widescreen shows more of each side of a match. Experimental: menu backgrounds look stretched at the sides.")
                    Picker("Movies on widescreen", selection: $model.c.movie) {
                        Text("Black bars").tag("black")
                        Text("Stretch").tag("fit")
                        Text("Zoom").tag("fill")
                    }
                    .help("How full-screen videos and stills fill a wide picture.")
                    Picker("Overscan crop", selection: $model.c.overscan) {
                        Text("None").tag(0)
                        Text("Small").tag(8)
                        Text("Medium").tag(16)
                        Text("Large").tag(32)
                    }
                    .help("Crops the edges, as an old TV did.")
                    Picker("Post-processing", selection: $model.c.shader) {
                        Text("None").tag("none")
                        Text("FSR (sharp upscale)").tag("fsr")
                        Text("CRT (tube TV)").tag("crt-lottes")
                        Text("CRT light (faster)").tag("crt-lottes-fast")
                    }
                    .help("FSR: AMD's sharp upscaler, best with a lower internal resolution than the window. CRT: the look of an old tube TV (scanlines, phosphor glow).")
                }
                Section("GRAPHICS") {
                    Picker("Anisotropic filtering", selection: $model.c.aniso) {
                        Text("Off").tag(0)
                        Text("2x").tag(2)
                        Text("4x").tag(4)
                        Text("8x").tag(8)
                        Text("16x").tag(16)
                    }
                    .help("Keeps textures seen at an angle (the ring's floor) sharp.")
                    Toggle("Progressive matches (480 lines)", isOn: $model.c.progressive)
                        .help("Matches drawn as full 640x480 frames. Off: the console's 480i fields, half the lines, which flicker.")
                    Picker("Background blur", selection: $model.c.dof) {
                        Text("Original (as on console)").tag("original")
                        Text("Off (sharp background)").tag("off")
                    }
                    .help("The game blurs the far scene behind the fighters (depth of field) by repainting it. Off skips that repaint, so the background stays sharp; the rest of the picture is unchanged.")
                }
                Section("PERFORMANCE") {
                    Picker("Frame rate", selection: $model.c.fps) {
                        Text("60  (original)").tag(60)
                        Text("120  (untested)").tag(120)
                        Text("144  (untested)").tag(144)
                        Text("240  (untested)").tag(240)
                    }
                    .help("60 is the original rate. Not tested above 60 on the Mac (game speed, sound and hits not checked yet). Above 60 only helps on an external monitor that refreshes that fast: the MacBook Air screen shows 60.")
                    Picker("Frame pacing", selection: $model.c.pacing) {
                        Text("Low CPU").tag("sleep")
                        Text("Exact timing").tag("spin")
                    }
                    .help("Low CPU sleeps between frames. Exact timing busy-waits, as the console did.")
                    Toggle("Accurate audio effects", isOn: $model.c.dsp)
                        .help("Reverb and echoes as the console had them. Uses a little more CPU.")
                    Toggle("VSync", isOn: Binding(get: { model.c.vsync == "1" }, set: { model.c.vsync = $0 ? "1" : "0" }))
                        .help("Off (default): each frame goes to the screen as soon as it is drawn, about 4 ms instead of about 45. On: waits for the screen's refresh; may avoid a rare torn line, with more input lag.")
                    Toggle("Game Mode", isOn: Binding(get: { model.c.gameMode == "1" }, set: { model.c.gameMode = $0 ? "1" : "0" }))
                        .help("On (default): the game runs as its own app (KFC Game.app in ~/Games/KFC) so macOS turns on Game Mode, which gives the game priority and lowers Bluetooth controller latency. The first match after a game update may stutter while shaders compile. Off: the game runs as before.")
                    Toggle("Metal HUD", isOn: $model.c.hud)
                        .help("Shows Apple's performance overlay in the game (frame rate, frame time, Direct or Composited). For checking only; the first match with it on may stutter while shaders compile.")
                }
                Section("CONTROLS") {
                    Picker("Controllers", selection: $model.c.pads) {
                        ForEach([1, 2, 3, 4], id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .help("How many controllers the game sees plugged in (up to 4).")
                    Picker("First controller is player", selection: $model.c.player) {
                        ForEach([1, 2, 3, 4], id: \.self) { n in
                            Text("Player \(n)").tag(n)
                        }
                    }
                    .help("The first controller plays as this player; the others follow.")
                    Toggle("Rumble", isOn: $model.c.rumble)
                        .help("The game's rumble on the controller.")
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Button("Restore defaults") { model.restoreDefaults() }
                    .help("Back to the default settings. Nothing is saved until PLAY.")
                Button("Open log") { model.openLog() }
                    .help("Opens log.txt, the game's last console output.")
                Spacer()
                Button(action: { model.play() }) {
                    Text("PLAY")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 150, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.running)
            }
            .padding(16)
        }
        .frame(width: 540, height: 780)
        .tint(accent)
        .preferredColorScheme(.dark)
        .onAppear { model.autoPlayIfAsked() }
        .alert("Kung Fu Chaos", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { shown in if !shown { model.alertMessage = nil } }
        ), actions: {
            Button("OK") { }
        }, message: {
            Text(model.alertMessage ?? "")
        })
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Not while a game runs: hiding the window when the plain binary starts counted as closing the last
        // window, and the launcher quit 30 ms after the game started (KFC-1230 smoke test).
        return !gameIsRunning
    }
}

@main
struct KFCLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Kung Fu Chaos") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
