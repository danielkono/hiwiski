import Foundation
import Security

/// Where and as whom the widgets ask the server.
struct Credentials: Codable, Equatable {
  let server: String
  let token: String
}

/// What the home screen widgets hold, in the App Group the app and the widget extension share:
/// the app's settings and pictures, the pictures the widgets fetched themselves, and the
/// session — in the keychain, readable after the first unlock like the app's own token.
///
/// Compiled into the app (`HomeWidgetBridge`, which writes) and the extension (which reads,
/// and writes what it fetched). Each key has one writer, so the two never overwrite each other.
/// What is stored is described in docs/development/home-widgets.md.
enum WidgetStore {
  static let appGroup = "group.de.danielkononov.hiwiski"

  private static let configKey = "config"
  private static let appPrefix = "snapshot.app."
  private static let serverPrefix = "snapshot.server."
  private static let gonePrefix = "gone."
  private static let keychainService = "de.danielkononov.hiwiski.home_widgets"
  private static let keychainAccount = "credentials"
  private static let kinds = ["agenda", "shopping", "tasks", "kanban"]

  private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  static var config: String? {
    get { defaults?.string(forKey: configKey) }
    set { defaults?.set(newValue, forKey: configKey) }
  }

  static func appSnapshot(_ kind: String) -> String? { defaults?.string(forKey: appPrefix + kind) }

  static func setAppSnapshot(_ kind: String, _ json: String?) { defaults?.set(json, forKey: appPrefix + kind) }

  static func serverSnapshot(_ kind: String) -> String? { defaults?.string(forKey: serverPrefix + kind) }

  static func setServerSnapshot(_ kind: String, _ json: String?) {
    defaults?.set(json, forKey: serverPrefix + kind)
  }

  /// The server answered that the widget's list is gone — or hidden, which reads the same.
  static func gone(_ kind: String) -> Bool { defaults?.bool(forKey: gonePrefix + kind) ?? false }

  static func setGone(_ kind: String, _ gone: Bool) { defaults?.set(gone, forKey: gonePrefix + kind) }

  /// New settings: what the server said about the old ones no longer applies.
  static func forgetGone() { kinds.forEach { defaults?.removeObject(forKey: gonePrefix + $0) } }

  static func credentials() -> Credentials? {
    var query = keychainQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data
    else { return nil }
    return try? JSONDecoder().decode(Credentials.self, from: data)
  }

  static func setCredentials(_ credentials: Credentials?) {
    SecItemDelete(keychainQuery() as CFDictionary)
    guard let credentials, let data = try? JSONEncoder().encode(credentials) else { return }
    var item = keychainQuery()
    item[kSecValueData as String] = data
    // Readable after the first unlock: the widgets refresh with the phone in the pocket,
    // locked. "This device only": the session belongs to this device, not to a backup.
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(item as CFDictionary, nil)
  }

  /// Everything — after a sign-out nothing of the member stays on the home screen.
  static func clear() {
    if let defaults {
      for key in defaults.dictionaryRepresentation().keys
      where key == configKey || key.hasPrefix(appPrefix) || key.hasPrefix(serverPrefix)
        || key.hasPrefix(gonePrefix)
      {
        defaults.removeObject(forKey: key)
      }
    }
    setCredentials(nil)
  }

  /// In the App Group's keychain access group, so that the extension reads what the app wrote.
  private static func keychainQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecAttrAccessGroup as String: appGroup,
    ]
  }
}
