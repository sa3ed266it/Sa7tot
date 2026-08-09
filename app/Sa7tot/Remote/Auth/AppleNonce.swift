import CryptoKit
import Foundation
import Security

public enum AppleNonceError: Error, Equatable, Sendable {
    case invalidLength
    case randomGenerationFailed(OSStatus)
}

public enum AppleNonce {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    public static func random(length: Int = 32) throws -> String {
        guard length > 0 else { throw AppleNonceError.invalidLength }

        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AppleNonceError.randomGenerationFailed(status)
        }

        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    public static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
