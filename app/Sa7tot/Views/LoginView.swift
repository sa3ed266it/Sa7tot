import AuthenticationServices
import SwiftUI
import UIKit
import Lottie

struct LoginView: View {
    @EnvironmentObject private var authService: SupabaseAuthService
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var rawNonce: String?
    @State private var didAppear = false

    let error: SupabaseAuthPresentationError?
    let isAuthenticating: Bool

    init(
        error: SupabaseAuthPresentationError? = nil,
        isAuthenticating: Bool = false
    ) {
        self.error = error
        self.isAuthenticating = isAuthenticating
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: max(28, proxy.size.height * 0.10))

                    WalletAnimationView(reduceMotion: accessibilityReduceMotion)
                        .frame(width: 168, height: 168)
                        .accessibilityHidden(true)

                    Text("Sa7tot")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.PrimaryText)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 6)

                    Text(AppLocalization.key("auth.login.tagline"))
                        .font(.body)
                        .foregroundStyle(Color.SubtitleText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)

                    Spacer(minLength: max(40, proxy.size.height * 0.12))

                    if let error {
                        Text(error.message)
                            .font(.callout)
                            .foregroundStyle(Color.SubtitleText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 14)
                    }

                    if isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.PrimaryText)
                            .frame(height: 50)
                            .accessibilityLabel(AppLocalization.key("auth.login.signIn"))
                    } else if error != .configuration {
                        SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: complete)
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 50)
                    }

                    Text(AppLocalization.key("auth.login.privacy"))
                        .font(.footnote)
                        .foregroundStyle(Color.SubtitleText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                        .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))
                }
                .frame(minHeight: max(proxy.size.height, 560))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
            }
        }
        .background(Color.AppPageBackground.ignoresSafeArea())
        .opacity(didAppear || accessibilityReduceMotion ? 1 : 0)
        .offset(y: didAppear || accessibilityReduceMotion ? 0 : 8)
        .scaleEffect(didAppear || accessibilityReduceMotion ? 1 : 0.985)
        .animation(.easeOut(duration: 0.32), value: didAppear)
        .onAppear {
            guard !accessibilityReduceMotion else {
                didAppear = true
                return
            }
            didAppear = true
        }
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
                    authService.handle(error: .invalidAppleCredential)
                    return
                }
                do {
                    let credential = try AppleAuthorizationCredentialBuilder.build(
                        from: credential,
                        rawNonce: rawNonce
                    )
                    await authService.signIn(with: credential)
                } catch let error as SupabaseAuthError {
                    authService.handle(error: error)
                } catch {
                    authService.handle(error: .invalidAppleCredential)
                }
            case let .failure(error as ASAuthorizationError) where error.code == .canceled:
                authService.handle(error: .userCancelled)
            case .failure:
                authService.handle(error: .invalidAppleCredential)
            }
        }
    }
}

private struct WalletAnimationView: UIViewRepresentable {
    let reduceMotion: Bool

    func makeUIView(context: Context) -> LottieAnimationView {
        let animationView = LottieAnimationView(name: "Wallet", bundle: .main)
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .playOnce

        if reduceMotion {
            animationView.currentProgress = 1
        } else {
            animationView.play(fromProgress: 0, toProgress: 1, loopMode: .playOnce)
        }

        return animationView
    }

    func updateUIView(_ animationView: LottieAnimationView, context: Context) {
        guard reduceMotion else { return }
        animationView.stop()
        animationView.currentProgress = 1
    }
}
