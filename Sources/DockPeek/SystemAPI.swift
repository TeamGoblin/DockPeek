import AppKit
import ApplicationServices

// MARK: - Accessibility helpers

extension AXUIElement {
    func raw(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ name: String) -> String? { raw(name) as? String }
    func bool(_ name: String) -> Bool? { (raw(name) as? NSNumber)?.boolValue }
    func elements(_ name: String) -> [AXUIElement] { (raw(name) as? [AXUIElement]) ?? [] }

    func element(_ name: String) -> AXUIElement? {
        guard let v = raw(name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var title: String? { string(kAXTitleAttribute) }

    var url: URL? {
        guard let v = raw(kAXURLAttribute) else { return nil }
        if let u = v as? URL { return u }
        if let u = v as? NSURL { return u as URL }
        return nil
    }

    /// Frame in global "top-left origin" coordinates (same space as CGWindow bounds).
    var frame: CGRect? {
        guard let p = raw(kAXPositionAttribute), let s = raw(kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(self, action as CFString) == .success
    }

    var windowID: CGWindowID? {
        guard let fn = Private.axGetWindow else { return nil }
        var id: CGWindowID = 0
        return fn(self, &id) == .success && id != 0 ? id : nil
    }
}

// MARK: - Private symbols, resolved at runtime so a missing one degrades gracefully

enum Private {
    private static let skyLight: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        _ = skyLight
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let p = dlsym(handle, name) ?? skyLight.flatMap({ dlsym($0, name) }) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    static let axGetWindow = sym("_AXUIElementGetWindow", AXGetWindowFn.self)

    typealias MainConnFn = @convention(c) () -> Int32
    typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias ManagedSpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    static let mainConnection = sym("CGSMainConnectionID", MainConnFn.self)
    static let spacesForWindows = sym("CGSCopySpacesForWindows", SpacesForWindowsFn.self)
    static let managedDisplaySpaces = sym("CGSCopyManagedDisplaySpaces", ManagedSpacesFn.self)

    typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    typealias PostEventFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    static let getPSN = sym("GetProcessForPID", GetPSNFn.self)
    static let setFrontProcess = sym("_SLPSSetFrontProcessWithOptions", SetFrontFn.self)
    static let postEventRecord = sym("SLPSPostEventRecordTo", PostEventFn.self)

    /// Brings a specific window (even on another Space) to the front and makes it key.
    /// Same technique AltTab uses; works from a background (LSUIElement) app.
    static func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let getPSN, let setFrontProcess, let postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { return false }
        guard setFrontProcess(&psn, windowID, 0x200 /* kCPSUserGenerated */) == .success else { return false }
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        var wid = windowID
        withUnsafeBytes(of: &wid) { src in
            for i in 0..<4 { bytes[0x3c + i] = src[i] }
        }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = postEventRecord(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = postEventRecord(&psn, &bytes)
        return true
    }
}

// MARK: - Spaces

struct SpaceSnapshot {
    /// ManagedSpaceID -> 1-based user-visible desktop number
    var numberBySpace: [Int: Int] = [:]
    var currentSpaces: Set<Int> = []
    private let conn: Int32

    init() {
        conn = Private.mainConnection?() ?? 0
        guard let fn = Private.managedDisplaySpaces, let arr = fn(conn)?.takeRetainedValue() as? [[String: Any]] else { return }
        var n = 0
        for display in arr {
            if let cur = display["Current Space"] as? [String: Any], let id = cur["ManagedSpaceID"] as? Int {
                currentSpaces.insert(id)
            }
            for space in (display["Spaces"] as? [[String: Any]]) ?? [] {
                guard let id = space["ManagedSpaceID"] as? Int else { continue }
                n += 1
                numberBySpace[id] = n
            }
        }
    }

    func spaces(for window: CGWindowID) -> [Int] {
        guard let fn = Private.spacesForWindows else { return [] }
        let ids = [NSNumber(value: window)] as CFArray
        guard let res = fn(conn, 0x7, ids)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return res.map { $0.intValue }
    }
}

// MARK: - Coordinates

enum Coords {
    /// Height of the primary screen; AX / CGWindow use a top-left origin anchored to it.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Converts a top-left-origin rect (AX / CG) to an AppKit bottom-left-origin rect.
    static func toAppKit(_ r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
