#if AIRDESK_CORE_SMOKE
import AirDeskCore

enum CoreFFISmoke {
    static var label: String { coreSmokeLabel() }
    static var abiVersion: UInt32 { coreAbiVersion() }
    static var isCurrentABICompatible: Bool { coreIsAbiCompatible(required: coreAbiVersion()) }
}
#endif
