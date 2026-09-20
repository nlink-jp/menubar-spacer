import Foundation
// The REAL domain (global, current host), one real key. Run only under the guard
// script, which has set the user's values aside and puts them back.
// Question: after a saved write here, how soon does the settings file show it?
let key = "NSStatusItemSpacing" as CFString
let app = kCFPreferencesAnyApplication, user = kCFPreferencesCurrentUser, host = kCFPreferencesCurrentHost

func hostUUID() -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    var wait = timespec(tv_sec: 1, tv_nsec: 0)
    gethostuuid(&bytes, &wait)
    return NSUUID(uuidBytes: bytes).uuidString
}
let file = NSHomeDirectory() + "/Library/Preferences/ByHost/.GlobalPreferences.\(hostUUID()).plist"

func api() -> String { CFPreferencesCopyValue(key, app, user, host).map { "\($0)" } ?? "<absent>" }
func disk() -> String {
    guard let data = FileManager.default.contents(atPath: file),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return "<no file/unparsable>" }
    return plist["NSStatusItemSpacing"].map { "\($0)" } ?? "<absent>"
}
func mtime() -> String {
    let d = (try? FileManager.default.attributesOfItem(atPath: file)[.modificationDate]) as? Date
    return d.map { String(format: "%.3f", $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) } ?? "-"
}
func sample(_ label: String, _ start: Date, _ pauses: [Double]) {
    for pause in pauses {
        Thread.sleep(forTimeInterval: pause)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print(String(format: "  %@ +%6d ms  api=%@  disk=%@  mtime=%@", label, ms, api(), disk(), mtime()))
    }
}
let pauses: [Double] = [0, 0.05, 0.2, 0.5, 1, 2, 3, 4, 5]
print("before: api=\(api()) disk=\(disk()) mtime=\(mtime())")
var start = Date()
CFPreferencesSetMultiple([key: 8 as CFNumber] as CFDictionary, nil, app, user, host)
print("set 8: synchronize=\(CFPreferencesSynchronize(app, user, host))")
sample("set   ", start, pauses)
start = Date()
CFPreferencesSetMultiple(nil, [key] as CFArray, app, user, host)
print("delete: synchronize=\(CFPreferencesSynchronize(app, user, host))")
sample("delete", start, pauses)
