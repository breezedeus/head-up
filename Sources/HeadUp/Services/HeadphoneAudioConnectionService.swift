import CoreAudio
import Foundation

struct HeadphoneAudioConnectionService {
    func hasConnectedCompatibleHeadphones() -> Bool {
        connectedAudioDeviceNames().contains { Self.isCompatibleHeadphoneName($0) }
    }

    func connectedAudioDeviceNames() -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard dataStatus == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasOutputStreams(deviceID) else { return nil }
            return deviceName(deviceID)
        }
    }

    static func isCompatibleHeadphoneName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("airpods")
            || normalized.contains("beats fit pro")
            || normalized.contains("powerbeats pro")
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutableBytes(of: &name) { buffer in
            guard let baseAddress = buffer.baseAddress else { return OSStatus(kAudioHardwareBadObjectError) }
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, baseAddress)
        }
        guard status == noErr, let name else { return nil }
        return name as String
    }

    private func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }
}
