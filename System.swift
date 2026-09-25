import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement

// Built-in screen brightness via private DisplayServices (what the brightness keys use).
enum Brightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getFn = dlsym(lib, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: Get.self) }
    private static let setFn = dlsym(lib, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: Set.self) }

    private static var display: CGDirectDisplayID {
        Display.online.first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static func get() -> Float? {
        var value: Float = 0
        guard let getFn, getFn(display, &value) == 0 else { return nil }
        return value
    }

    static func set(_ value: Float) {
        guard let setFn, setFn(display, value) == 0 else { return NSLog("SleepLess: brightness set failed") }
    }
}

enum Display {
    static var online: [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// A monitor is plugged in (lid shut + monitor = ordinary clamshell use).
    static var hasExternal: Bool { online.contains { CGDisplayIsBuiltin($0) == 0 } }

    /// Some screen is still lit.
    static var anyAwake: Bool { online.contains { CGDisplayIsAsleep($0) == 0 } }

    /// `pmset displaysleepnow`: screens off (the keyboard backlight goes with them), the Mac itself stays up.
    static func sleepNow() {
        do { try Process.run(URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["displaysleepnow"]) }
        catch { NSLog("SleepLess: displaysleepnow failed: \(error)") }
    }
}

enum Awake {
    /// Same pair as `caffeinate -di`: screen never idle-dims/sleeps, system never idle-sleeps.
    static func hold() -> [IOPMAssertionID] {
        [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep].compactMap { type in
            var id: IOPMAssertionID = 0
            let rc = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "SleepLess: keeping the screen awake" as CFString, &id)
            guard rc == kIOReturnSuccess else { NSLog("SleepLess: \(type) assertion failed \(rc)"); return nil }
            return id
        }
    }
}

enum Power {
    struct Battery: Equatable {
        var percent: Int
        var onAC: Bool
    }

    /// nil on Macs without a battery.
    static func battery() -> Battery? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let onAC = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? == kIOPSACPowerValue
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return Battery(percent: current * 100 / max, onAC: onAC)
        }
        return nil
    }

    static var isHot: Bool { [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) }

    private static let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))

    /// The live SleepDisabled flag — confirms the helper really applied lid-closed mode.
    static var sleepDisabled: Bool { rootFlag("SleepDisabled") }

    /// The lid (clamshell) is shut.
    static var lidClosed: Bool { rootFlag("AppleClamshellState") }

    private static func rootFlag(_ key: String) -> Bool {
        IORegistryEntryCreateCFProperty(rootDomain, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool ?? false
    }
}

/// Root launchd helper for lid-closed mode (sleepless-helper.sh). The app only ever writes 1/0 to a file;
/// the helper applies it and ignores it once it's 90 s stale, so a dead app can't leave the Mac unable to sleep.
enum LidHelper {
    private static let requestPath = "/Library/Application Support/SleepLess/lid"
    private static let installedPath = "/Library/PrivilegedHelperTools/io.github.cyborgfingers.sleepless.lid.sh"
    private static var bundledPath: String { Bundle.main.path(forResource: "sleepless-helper", ofType: "sh") ?? "" }

    /// Installed, same version as this build, and the request file is ours to write.
    static var isReady: Bool {
        FileManager.default.contentsEqual(atPath: installedPath, andPath: bundledPath)
            && FileManager.default.isWritableFile(atPath: requestPath)
    }

    /// One admin prompt. Returns an error message, or nil on success.
    static func install() -> String? {
        let quote = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let script = "do shell script \"/bin/sh \" & quoted form of \"\(quote(bundledPath))\" & \" install \" & quoted form of \"\(quote(NSUserName()))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { return error[NSAppleScript.errorMessage] as? String ?? "Helper install failed." }
        return isReady ? nil : "Helper install didn't complete."
    }

    static func request(_ on: Bool) {
        // atomically: false — the helper's folder is root-owned, so we rewrite our file in place.
        do { try (on ? "1\n" : "0\n").write(toFile: requestPath, atomically: false, encoding: .utf8) }
        catch { NSLog("SleepLess: lid request failed: \(error)") }
    }
}

enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message, or nil on success.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
