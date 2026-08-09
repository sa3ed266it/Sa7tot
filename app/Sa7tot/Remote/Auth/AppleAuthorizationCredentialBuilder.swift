import AuthenticationServices
import Foundation

public enum AppleAuthorizationCredentialBuilder {
    public static func build(
        from credential: ASAuthorizationAppleIDCredential,
        rawNonce: String
    ) throws -> AppleAuthorizationCredential {
        guard !rawNonce.isEmpty else { throw SupabaseAuthError.invalidAppleCredential }
        guard let identityToken = credential.identityToken,
              let identityTokenString = String(data: identityToken, encoding: .utf8),
              !identityTokenString.isEmpty else {
            throw SupabaseAuthError.missingIdentityToken
        }

        let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        return AppleAuthorizationCredential(
            identityToken: identityTokenString,
            authorizationCode: authorizationCode,
            userIdentifier: credential.user,
            rawNonce: rawNonce
        )
    }
}
