// Kung Fu Chaos launcher for macOS (native recompilation, Metal).
// One config shared with the in-game menu: ~/Games/KFC/config.toml (render/present/display),
// plus ~/Games/KFC/launcher.ini for the options that are passed as environment variables.
// Build: zsh build.sh   (swiftc -O -parse-as-library KFCLauncher.swift -o KFCLauncher)
import SwiftUI
import AppKit

let K = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Games/KFC")
let tomlURL = K.appendingPathComponent("config.toml")
let iniURL = K.appendingPathComponent("launcher.ini")
let logURL = K.appendingPathComponent("log.txt")

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
    var scale = 2
    var aniso = 16
    var fullscreen = true
    var filter = "linear"
    var shader = "none"
    var pacing = "sleep"
    var aspect = "4:3"
    var movie = "black"
    var overscan = 0
    // launcher.ini
    var upscaler = "metalfx"
    var progressive = true
    var dsp = true
    var pads = 4
    var player = 1
    var rumble = true
    var fps = 60
    var dof = "off"   // default: sharp background; "off": skip the depth-of-field repaint (RECOMP_DOF_SKIP)

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
            if let v = d["fps"], v == "60" || v == "120" { c.fps = Int(v) ?? 60 }
            if let v = d["dof"], v == "original" || v == "off" { c.dof = v }
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
        env["RECOMP_DEBUG"] = "rt_alias_check=0"
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
        return env
    }
}

// MARK: - Model

@MainActor
final class LauncherModel: ObservableObject {
    @Published var c: Config
    @Published var running = false
    @Published var alertMessage: String? = nil
    private var hiddenWindows: [NSWindow] = []

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
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)
        let p = Process()
        p.executableURL = exe
        p.currentDirectoryURL = build
        p.environment = c.environment()
        p.standardOutput = FileHandle.nullDevice
        if let h = logHandle { p.standardError = h }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.gameEnded()
                }
            }
        }
        do {
            try p.run()
        } catch {
            alertMessage = "Could not start the game:\n" + error.localizedDescription
            return
        }
        running = true
        hiddenWindows = NSApp.windows.filter { $0.isVisible }
        for w in hiddenWindows { w.orderOut(nil) }
    }

    func gameEnded() {
        running = false
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
                    .help("MetalFX (Apple) scales the image up to the screen with more sharpness; use it with an internal resolution below the screen's (2x on the MacBook Air).")
                    Picker("Window mode", selection: $model.c.fullscreen) {
                        Text("Fullscreen").tag(true)
                        Text("Window").tag(false)
                    }
                    .help("Fullscreen is borderless, on the desktop's resolution.")
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
                        Text("120  (experimental)").tag(120)
                    }
                    .help("The game times itself, so it runs at normal speed at any rate; higher is smoother. Experimental above 60.")
                    Picker("Frame pacing", selection: $model.c.pacing) {
                        Text("Low CPU").tag("sleep")
                        Text("Exact timing").tag("spin")
                    }
                    .help("Low CPU sleeps between frames. Exact timing busy-waits, as the console did.")
                    Toggle("Accurate audio effects", isOn: $model.c.dsp)
                        .help("Reverb and echoes as the console had them. Uses a little more CPU.")
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
        return true
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
