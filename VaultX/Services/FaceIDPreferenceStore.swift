import Foundation
import Combine

protocol FaceIDPreferenceStore: AnyObject {
    var isFaceIDEnabled: Bool { get set }
}

enum AutoLockDelay: Int, CaseIterable, Identifiable {
    case immediately = 0
    case seconds15 = 15
    case seconds30 = 30
    case minute1 = 60

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var displayName: String {
        switch self {
        case .immediately:
            return "فورًا"
        case .seconds15:
            return "بعد 15 ثانية"
        case .seconds30:
            return "بعد 30 ثانية"
        case .minute1:
            return "بعد دقيقة"
        }
    }
}

enum ClipboardClearDelay: Int, CaseIterable, Identifiable {
    case seconds15 = 15
    case seconds30 = 30
    case seconds45 = 45
    case seconds60 = 60

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var displayName: String {
        "بعد \(rawValue) ثانية"
    }
}

final class VaultSecuritySettings: ObservableObject, FaceIDPreferenceStore {
    private enum Key {
        static let faceIDEnabled = "VaultX.FaceIDEnabled"
        static let autoLockDelay = "VaultX.AutoLockDelay"
        static let clipboardClearDelay = "VaultX.ClipboardClearDelay"
        static let hideTOTPCodes = "VaultX.HideTOTPCodesByDefault"
    }

    private let defaults: UserDefaults

    @Published var isFaceIDEnabled: Bool {
        didSet { defaults.set(isFaceIDEnabled, forKey: Key.faceIDEnabled) }
    }

    @Published var autoLockDelay: AutoLockDelay {
        didSet { defaults.set(autoLockDelay.rawValue, forKey: Key.autoLockDelay) }
    }

    @Published var clipboardClearDelay: ClipboardClearDelay {
        didSet { defaults.set(clipboardClearDelay.rawValue, forKey: Key.clipboardClearDelay) }
    }

    @Published var hideTOTPCodesByDefault: Bool {
        didSet { defaults.set(hideTOTPCodesByDefault, forKey: Key.hideTOTPCodes) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isFaceIDEnabled = defaults.bool(forKey: Key.faceIDEnabled)

        let autoLockRaw = defaults.object(forKey: Key.autoLockDelay) as? Int
        self.autoLockDelay = autoLockRaw.flatMap(AutoLockDelay.init(rawValue:)) ?? .immediately

        let clipboardRaw = defaults.object(forKey: Key.clipboardClearDelay) as? Int
        self.clipboardClearDelay = clipboardRaw.flatMap(ClipboardClearDelay.init(rawValue:)) ?? .seconds45

        self.hideTOTPCodesByDefault = defaults.bool(forKey: Key.hideTOTPCodes)
    }
}

final class UserDefaultsFaceIDPreferenceStore: FaceIDPreferenceStore {
    private let defaultsKey = "VaultX.FaceIDEnabled"

    var isFaceIDEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}
