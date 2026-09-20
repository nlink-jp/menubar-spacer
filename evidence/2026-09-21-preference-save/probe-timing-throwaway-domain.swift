import Foundation
// Throwaway domain only. Question: after a write, who tells the truth, and how soon —
// the preferences API, or the settings file on disk?
let domainName = "jp.nlink.menubar-spacer.cfprobe"
let domain = domainName as CFString, key = "Probe" as CFString
let user = kCFPreferencesCurrentUser, host = kCFPreferencesCurrentHost

func hostUUID() -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    var wait = timespec(tv_sec: 1, tv_nsec: 0)
    gethostuuid(&bytes, &wait)
    return NSUUID(uuidBytes: bytes).uuidString
}
let file = NSHomeDirectory() + "/Library/Preferences/ByHost/\(domainName).\(hostUUID()).plist"

func api() -> String { (CFPreferencesCopyValue(key, domain, user, host)).map { "\($0)" } ?? "<absent>" }
func disk() -> String {
    guard let data = FileManager.default.contents(atPath: file),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return "<no file>" }
    return plist["Probe"].map { "\($0)" } ?? "<absent>"
}

let value = Int(CommandLine.arguments[1])!
print("file: ByHost/\(domainName).<host uuid>.plist  before: api=\(api()) disk=\(disk())")
let start = Date()
CFPreferencesSetMultiple([key: value as CFNumber] as CFDictionary, nil, domain, user, host)
let ok = CFPreferencesSynchronize(domain, user, host)
func ms() -> Int { Int(Date().timeIntervalSince(start) * 1000) }
print("wrote \(value): synchronize=\(ok)")
for pause in [0.0, 0.05, 0.2, 0.5, 1.0, 2.0] {
    Thread.sleep(forTimeInterval: pause)
    print(String(format: "  +%5d ms  api says %@   disk says %@", ms(), api(), disk()))
}
