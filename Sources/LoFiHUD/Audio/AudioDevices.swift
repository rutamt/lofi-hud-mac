import CoreAudio
import Foundation

/// Enumerates audio output devices and reports changes via CoreAudio listeners
/// (event-driven, no polling).
final class AudioDevices {
    struct Device: Hashable {
        /// Stable across reconnects and renames; prefer it over `name` for matching.
        let uid: String
        let name: String
    }

    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    /// Every device that currently exposes output streams.
    static func outputDevices() -> [Device] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        var devices: [Device] = []
        for id in ids where hasOutputStreams(id) {
            guard let name = string(id, kAudioObjectPropertyName),
                  let uid = string(id, kAudioDevicePropertyDeviceUID) else { continue }
            devices.append(Device(uid: uid, name: name))
        }
        return devices
    }

    static func outputDeviceNames() -> [String] {
        var names: [String] = []
        for d in outputDevices() where !names.contains(d.name) { names.append(d.name) }
        return names
    }

    static func defaultOutputUID() -> String? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr, id != 0
        else { return nil }
        return string(id, kAudioDevicePropertyDeviceUID)
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr,
              let cf = value?.takeRetainedValue() else { return nil }
        let s = (cf as String).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    /// Calls handlers on the main queue when devices come/go or the default output changes.
    func startMonitoring(devicesChanged: @escaping () -> Void, defaultChanged: @escaping () -> Void) {
        stopMonitoring()
        add(kAudioHardwarePropertyDevices, devicesChanged)
        add(kAudioHardwarePropertyDefaultOutputDevice, defaultChanged)
    }

    private func add(_ selector: AudioObjectPropertySelector, _ handler: @escaping () -> Void) {
        var addr = Self.address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block) == noErr {
            listeners.append((addr, block))
        }
    }

    func stopMonitoring() {
        for (addr, block) in listeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, block)
        }
        listeners.removeAll()
    }
}
