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
}

// Built-in keyboard backlight via private CoreBrightness (what the keyboard-brightness keys use).
enum KeyboardLight {
    struct Level: Codable, Equatable {
        var brightness: Float
        var auto: Bool   // ambient-light adjustment
    }

    private static let client: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()
    private static let keyboard: UInt64? = (client?.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?
        .takeRetainedValue() as? [NSNumber])?.first?.uint64Value

    private static func method<F>(_ name: String, _ type: F.Type) -> (NSObject, Selector, UInt64, F)? {
        let selector = NSSelectorFromString(name)
        guard let client, let keyboard, let m = class_getInstanceMethod(Swift.type(of: client), selector) else { return nil }
        return (client, selector, keyboard, unsafeBitCast(method_getImplementation(m), to: F.self))
    }

    static func get() -> Level? {
        guard let (c, s, k, brightness) = method("brightnessForKeyboard:", (@convention(c) (AnyObject, Selector, UInt64) -> Float).self),
              let (_, s2, _, isAuto) = method("isAutoBrightnessEnabledForKeyboard:", (@convention(c) (AnyObject, Selector, UInt64) -> Bool).self)
        else { return nil }
        return Level(brightness: brightness(c, s, k), auto: isAuto(c, s2, k))
    }

    static func set(_ level: Level) {
        guard let (c, s, k, setBrightness) = method("setBrightness:forKeyboard:", (@convention(c) (AnyObject, Selector, Float, UInt64) -> Bool).self),
              let (_, s2, _, enableAuto) = method("enableAutoBrightness:forKeyboard:", (@convention(c) (AnyObject, Selector, Bool, UInt64) -> Void).self)
        else { return NSLog("SleepLess: keyboard backlight unavailable") }
        if !level.auto { enableAuto(c, s2, false, k) }   // off first, so ambient light can't pull it back up
        if !setBrightness(c, s, level.brightness, k) { NSLog("SleepLess: keyboard backlight set failed") }
        if level.auto { enableAuto(c, s2, true, k) }
    }
}

enum Awake {
    /// Same pair as `caffeinate -di`: screen never idle-dims/sleeps, system never idle-sleeps — or the system
    /// half alone (`caffeinate -i`) when the screen may sleep.
    static func hold(display: Bool = true) -> [IOPMAssertionID] {
        let types = display ? [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep]
                            : [kIOPMAssertionTypePreventUserIdleSystemSleep]
        return types.compactMap { type in
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
    private static let lightRequestPath = "/Library/Application Support/SleepLess/led"
    private static let installedPath = "/Library/PrivilegedHelperTools/io.github.cyborgfingers.sleepless.lid.sh"
    private static let installedLightPath = "/Library/PrivilegedHelperTools/io.github.cyborgfingers.sleepless.led"
    private static var bundledPath: String { Bundle.main.path(forResource: "sleepless-helper", ofType: "sh") ?? "" }
    private static var bundledLightPath: String { Bundle.main.path(forResource: "sleepless-led", ofType: nil) ?? "" }

    /// Installed, same version as this build (script and light tool), and the request files are ours to write.
    static var isReady: Bool {
        let files = FileManager.default
        return files.contentsEqual(atPath: installedPath, andPath: bundledPath)
            && files.contentsEqual(atPath: installedLightPath, andPath: bundledLightPath)
            && files.isWritableFile(atPath: requestPath)
            && files.isWritableFile(atPath: lightRequestPath)
    }

    /// Some version of the helper is installed (so a signed self-update is possible when it isn't this one).
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installedPath) }

    /// The one admin prompt (password or Touch ID): installs everything SleepLess ever needs as root.
    static func install() -> Admin.Outcome {
        let outcome = Admin.run(bundledPath, ["install", NSUserName()], prompt: "SleepLess needs to install its helper for lid-closed mode and the charging light. This is the only time it will ask.")
        return outcome == .done && !isReady ? .failed("The helper didn't install.") : outcome
    }

    static func request(_ on: Bool) {
        // atomically: false — the helper's folder is root-owned, so we rewrite our file in place.
        do { try (on ? "1\n" : "0\n").write(toFile: requestPath, atomically: false, encoding: .utf8) }
        catch { NSLog("SleepLess: lid request failed: \(error)") }
    }

    /// The MagSafe charging light: off while the lid is shut, back to macOS's normal colour when it opens.
    static func light(_ on: Bool) {
        do { try (on ? "on\n" : "off\n").write(toFile: lightRequestPath, atomically: false, encoding: .utf8) }
        catch { NSLog("SleepLess: light request failed: \(error)") }
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
