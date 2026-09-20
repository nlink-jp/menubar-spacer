import Foundation
// A throwaway domain: nothing here touches the global domain or the menu bar keys.
let domain = "jp.nlink.menubar-spacer.cfprobe" as CFString
let key = "Probe" as CFString
let user = kCFPreferencesCurrentUser, host = kCFPreferencesCurrentHost
func read() -> String { (CFPreferencesCopyValue(key, domain, user, host)).map { "\($0)" } ?? "<absent>" }
let args = CommandLine.arguments
switch args[1] {
case "write":
    CFPreferencesSetValue(key, Int(args[2])! as CFNumber, domain, user, host)
    let ok = CFPreferencesSynchronize(domain, user, host)
    print("write \(args[2]): synchronize=\(ok) same-process read=\(read())")
    if args.count > 3 { Thread.sleep(forTimeInterval: 1.5); _ = CFPreferencesSynchronize(domain, user, host); print("  1.5 s later, same process, after another synchronize: read=\(read())") }
case "multi":   // the call the app uses
    CFPreferencesSetMultiple([key: Int(args[2])! as CFNumber] as CFDictionary, nil, domain, user, host)
    let ok = CFPreferencesSynchronize(domain, user, host)
    print("setMultiple \(args[2]): synchronize=\(ok) same-process read=\(read())")
case "read":
    let ok = CFPreferencesSynchronize(domain, user, host)
    print("new process: synchronize=\(ok) read=\(read())")
case "delete":
    CFPreferencesSetValue(key, nil, domain, user, host)
    print("delete: synchronize=\(CFPreferencesSynchronize(domain, user, host)) read=\(read())")
default: break
}
