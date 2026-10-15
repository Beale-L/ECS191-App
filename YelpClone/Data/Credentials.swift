import CommonCrypto
import Foundation
import Security

/// A stored password: a salted PBKDF2-SHA256 hash, never the password itself.
struct Credential: Codable, Equatable {
    /// The username as it was first created, which may differ in case from what's typed later.
    let username: String
    let salt: Data
    let hash: Data
    let iterations: Int

    /// Hashes a new password with a fresh random salt.
    static func make(username: String, password: String, iterations: Int) -> Credential {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        precondition(status == errSecSuccess, "Couldn't generate a salt")
        return Credential(username: username, salt: salt,
                          hash: pbkdf2(password, salt: salt, iterations: iterations), iterations: iterations)
    }

    func matches(_ password: String) -> Bool {
        let candidate = Self.pbkdf2(password, salt: salt, iterations: iterations)
        // Compare every byte so timing doesn't reveal how much matched.
        guard candidate.count == hash.count else { return false }
        return zip(candidate, hash).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func pbkdf2(_ password: String, salt: Data, iterations: Int) -> Data {
        let passwordBytes = Array(password.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { derivedBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                    derivedBuffer.bindMemory(to: UInt8.self).baseAddress, 32
                )
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return derived
    }
}

/// Where credentials live. Keys are lowercased usernames, so names are case-insensitive.
protocol CredentialStore {
    func credential(for username: String) -> Credential?
    func save(_ credential: Credential)
    func removeAll()
}

/// Keeps credentials in the iOS Keychain, separate from the app's data file.
struct KeychainCredentialStore: CredentialStore {
    var service = "edu.ucdavis.ecs191.YelpClone.accounts"

    private func query(for username: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let username { query[kSecAttrAccount as String] = username.lowercased() }
        return query
    }

    func credential(for username: String) -> Credential? {
        var lookup = query(for: username)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }

    func save(_ credential: Credential) {
        guard let data = try? JSONEncoder().encode(credential) else { return }
        let match = query(for: credential.username)
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(match as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            assert(status == errSecSuccess, "Couldn't save credential: \(status)")
        }
    }

    func removeAll() {
        SecItemDelete(query() as CFDictionary)
    }
}

final class InMemoryCredentialStore: CredentialStore {
    private var credentials: [String: Credential] = [:]

    func credential(for username: String) -> Credential? { credentials[username.lowercased()] }
    func save(_ credential: Credential) { credentials[credential.username.lowercased()] = credential }
    func removeAll() { credentials = [:] }
}
