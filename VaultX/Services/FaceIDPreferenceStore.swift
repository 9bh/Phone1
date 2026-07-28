import Foundation

protocol FaceIDPreferenceStore {
    var isFaceIDEnabled: Bool { get set }
}

class UserDefaultsFaceIDPreferenceStore: FaceIDPreferenceStore {
    private let defaultsKey = "VaultX.FaceIDEnabled"
    
    var isFaceIDEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}
