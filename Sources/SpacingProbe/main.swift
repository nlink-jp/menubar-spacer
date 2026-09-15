// Phase 1 measurement probe. Development-only target: it is never copied into
// the .app bundle. It owns its own preference access on purpose — a measurement
// that is meant to inform the product's design must not depend on the product's
// untested assumptions.
//
// It writes preferences only in the `same-process` and `write` modes, and only
// the two spacing keys. The coordinator (spikes/run_phase1.py) captures an exact
// backup and arms a watchdog before any of those modes is invoked.
import AppKit
import CoreFoundation
import Foundation

let spacingKeys = ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"]

// MARK: - Preferences

func readScope(_ host: CFString) -> [String: Int] {
    CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host)
    var result: [String: Int] = [:]
    for key in spacingKeys {
        let raw = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                                         kCFPreferencesCurrentUser, host)
        if let number = raw as? NSNumber { result[key] = number.intValue }
    }
    return result
}

/// Only the two spacing keys may ever appear in a write payload.
func isValidPayload(_ values: Any?) -> Bool {
    guard let values = values as? [String: Any] else { return false }
    return values.keys.allSatisfy(spacingKeys.contains) && values.values.allSatisfy { $0 is NSNumber }
}

/// Writes the payload, deleting any spacing key it omits, then reads the scope
/// back and reports a mismatch rather than assuming the write landed.
@discardableResult
func writeValues(_ values: [String: Int]) -> Int32 {
    let removed = spacingKeys.filter { values[$0] == nil }
    CFPreferencesSetMultiple(values as CFDictionary, removed as CFArray,
                             kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                             kCFPreferencesCurrentHost)
    guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                   kCFPreferencesCurrentHost) else { return 3 }
    return readScope(kCFPreferencesCurrentHost) == values ? 0 : 4
}

func effectivePreferences() -> [String: Any] {
    let viaPreferences = readScope(kCFPreferencesCurrentHost)
    var viaDefaults: [String: Any] = [:]
    for key in spacingKeys {
        viaDefaults[key] = UserDefaults.standard.object(forKey: key) ?? NSNull()
    }
    return [
        "cfpreferences": viaPreferences,
        "user_defaults": viaDefaults,
    ]
}

func writeJSON(_ value: Any, to path: String) {
    guard let data = try? JSONSerialization.data(withJSONObject: value,
                                                 options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

// MARK: - Status item fixture

enum ItemKind: String, CaseIterable {
    case variableText = "variable_text"
    case squareSymbol = "square_symbol"
    case fixed32 = "fixed_32"
}

/// Three items matching the feasibility study's fixture, so the numbers here are
/// directly comparable with the values recorded there.
func makeItems(labelPrefix: String) -> [(ItemKind, NSStatusItem)] {
    ItemKind.allCases.map { kind in
        let length: CGFloat
        switch kind {
        case .variableText: length = NSStatusItem.variableLength
        case .squareSymbol: length = NSStatusItem.squareLength
        case .fixed32: length = 32
        }
        let item = NSStatusBar.system.statusItem(withLength: length)
        switch kind {
        case .variableText: item.button?.title = "SP"
        case .fixed32: item.button?.title = "FX"
        case .squareSymbol:
            let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Spacing probe symbol")
            image?.size = NSSize(width: 16, height: 16)
            item.button?.image = image
        }
        item.button?.setAccessibilityLabel("\(labelPrefix) \(kind.rawValue)")
        return (kind, item)
    }
}

func rect(_ r: NSRect) -> [CGFloat] { [r.origin.x, r.origin.y, r.size.width, r.size.height] }

func measure(_ items: [(ItemKind, NSStatusItem)]) -> [[String: Any]] {
    items.map { kind, item in
        let button = item.button
        return [
            "kind": kind.rawValue,
            "length": item.length,
            "bounds": rect(button?.bounds ?? .zero),
            "frame": rect(button?.frame ?? .zero),
            "intrinsic_width": button?.intrinsicContentSize.width ?? 0,
            "has_window": button?.window != nil,
            "window_frame": rect(button?.window?.frame ?? .zero),
        ]
    }
}

// MARK: - Probe application

final class Probe: NSObject, NSApplicationDelegate {
    let output: String
    /// nil = measure only (no write); a value = the same-process write test.
    let writeValue: Int?

    private var before: [(ItemKind, NSStatusItem)] = []
    private var after: [(ItemKind, NSStatusItem)] = []
    private var report: [String: Any] = [:]
    private var samples: [[String: Any]] = []

    init(output: String, writeValue: Int?) {
        self.output = output
        self.writeValue = writeValue
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        report["os"] = ProcessInfo.processInfo.operatingSystemVersionString
        report["pid"] = ProcessInfo.processInfo.processIdentifier
        report["mode"] = writeValue == nil ? "sample" : "same-process"
        report["effective_at_launch"] = effectivePreferences()

        before = makeItems(labelPrefix: "Probe before")

        if let value = writeValue {
            report["requested_value"] = value
            schedule(0.5) { self.sample(phase: "before_write") }
            schedule(1.5) { self.sample(phase: "before_write") }
            schedule(2.0) {
                let status = writeValues(Dictionary(uniqueKeysWithValues: spacingKeys.map { ($0, value) }))
                self.report["write_status"] = status
                self.report["effective_after_write"] = effectivePreferences()
            }
            // Did the items that already existed change? This is the question the
            // study never asked: it only ever launched a new process per value.
            schedule(2.5) { self.sample(phase: "existing_items_after_write") }
            schedule(4.0) { self.sample(phase: "existing_items_after_write") }
            schedule(4.5) {
                self.after = makeItems(labelPrefix: "Probe after")
            }
            schedule(5.0) { self.sample(phase: "new_items_after_write") }
            // A child launched *by the process that did the write*. This is the
            // shape the preview feature would take, and it is not the same thing
            // as a child of some unrelated coordinator.
            schedule(5.5) { self.spawnChild() }
            schedule(6.0) { self.sample(phase: "new_items_after_write") }
            schedule(10.5) { self.sample(phase: "new_items_after_write"); self.finish() }
        } else {
            schedule(0.5) { self.sample(phase: "sample") }
            schedule(1.5) { self.sample(phase: "sample") }
            schedule(3.0) { self.sample(phase: "sample"); self.finish() }
        }

        // Hard stop: this process must never outlive the coordinator's window.
        let limit: TimeInterval = writeValue == nil ? 12 : 26
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + limit) { _Exit(124) }
    }

    /// Runs this same executable in `sample` mode and records where it wrote.
    private func spawnChild() {
        let childOutput = output + "-child.json"
        report["child_output"] = childOutput
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["sample", childOutput]
        do {
            try process.run()
            report["child_launched"] = true
        } catch {
            report["child_launched"] = false
            report["child_error"] = String(describing: error)
        }
    }

    private func schedule(_ delay: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body)
    }

    private func sample(phase: String) {
        var entry: [String: Any] = [
            "phase": phase,
            "seconds_after_launch": Date().timeIntervalSince(launchedAt),
            "before_group": measure(before),
        ]
        if !after.isEmpty { entry["after_group"] = measure(after) }
        samples.append(entry)
        report["samples"] = samples
        report["effective_at_sample"] = effectivePreferences()
        writeJSON(report, to: output)
    }

    private func finish() {
        writeJSON(report, to: output)
        NSApp.terminate(nil)
    }
}

let launchedAt = Date()

// MARK: - Entry point

func selfTest() -> Int32 {
    guard isValidPayload([String: Any]()),
          isValidPayload(["NSStatusItemSpacing": 4]),
          isValidPayload(["NSStatusItemSpacing": 4, "NSStatusItemSelectionPadding": 4]),
          !isValidPayload(["OtherSetting": 4]),
          !isValidPayload(["NSStatusItemSpacing": "4"]),
          !isValidPayload([Int]()),
          !isValidPayload(nil),
          spacingKeys.count == 2,
          ItemKind.allCases.count == 3
    else { return 1 }
    print("PASS: 9 probe guard cases")
    return 0
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "--self-test":
    exit(selfTest())

case "read":
    guard arguments.count == 2, arguments[1].hasPrefix("/") else { exit(2) }
    let snapshot: [String: Any] = [
        "current_host": readScope(kCFPreferencesCurrentHost),
        "any_host": readScope(kCFPreferencesAnyHost),
    ]
    guard let data = try? PropertyListSerialization.data(fromPropertyList: snapshot,
                                                         format: .xml, options: 0),
          (try? data.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)) != nil
    else { exit(1) }
    exit(0)

case "write":
    guard arguments.count == 2, arguments[1].hasPrefix("/") else { exit(2) }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
          let payload = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
          isValidPayload(payload), let values = payload as? [String: Int]
    else { exit(2) }
    exit(writeValues(values))

case "sample", "same-process":
    guard arguments.count >= 2, arguments[1].hasPrefix("/") else { exit(2) }
    var value: Int?
    if arguments[0] == "same-process" {
        guard arguments.count == 3, let parsed = Int(arguments[2]), (0...64).contains(parsed) else { exit(2) }
        value = parsed
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let probe = Probe(output: arguments[1], writeValue: value)
    app.delegate = probe
    app.run()

default:
    FileHandle.standardError.write(Data("usage: spacing-probe --self-test | read PATH | write PATH | sample PATH | same-process PATH VALUE\n".utf8))
    exit(2)
}
