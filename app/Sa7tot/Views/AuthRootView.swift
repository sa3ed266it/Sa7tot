import AuthenticationServices
import SwiftUI

struct AuthRootView: View {
    @EnvironmentObject private var authService: SupabaseAuthService
    @EnvironmentObject private var remoteFinancialStore: FinancialRemoteStore

    var body: some View {
        Group {
            switch authService.state {
            case .restoring:
                ProgressView()
                    .tint(Color.PrimaryText)
            case .signedIn:
                ContentView()
            case .signedOut:
                AppleSignInView()
            case let .error(error):
                AppleSignInView(error: error)
            }
        }
        .task {
            await authService.restoreSession()
        }
        .onChange(of: authService.state) { state in
            if case .signedOut = state {
                remoteFinancialStore.resetRemoteState()
            }
        }
    }
}

private struct AppleSignInView: View {
    @EnvironmentObject private var authService: SupabaseAuthService
    @State private var rawNonce: String?
    let error: SupabaseAuthPresentationError?

    init(error: SupabaseAuthPresentationError? = nil) {
        self.error = error
    }

    var body: some View {
        VStack(spacing: 18) {
            if let error {
                Text(error.message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.SubtitleText)
                    .padding(.horizontal, 32)
            }

            if error != .configuration {
                SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: complete)
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.AppPageBackground)
    }

    private func configure(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try AppleNonce.random()
            rawNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleNonce.sha256(nonce)
        } catch {
            rawNonce = nil
        }
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        guard let rawNonce else { return }

        Task {
            switch result {
            case let .success(authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    await authService.handle(error: .invalidAppleCredential)
                    return
                }
                do {
                    let credential = try AppleAuthorizationCredentialBuilder.build(
                        from: credential,
                        rawNonce: rawNonce
                    )
                    await authService.signIn(with: credential)
                } catch let error as SupabaseAuthError {
                    await authService.handle(error: error)
                } catch {
                    await authService.handle(error: .invalidAppleCredential)
                }
            case let .failure(error as ASAuthorizationError) where error.code == .canceled:
                await authService.handle(error: .userCancelled)
            case .failure:
                await authService.handle(error: .invalidAppleCredential)
            }
        }
    }
}
