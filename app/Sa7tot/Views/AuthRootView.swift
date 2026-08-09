import SwiftUI

struct AuthRootView: View {
    @EnvironmentObject private var authService: SupabaseAuthService
    @EnvironmentObject private var remoteFinancialStore: FinancialRemoteStore

    @State private var hasResolvedInitialAuth = false
    @State private var isSigningIn = false

    var body: some View {
        Group {
            switch authService.state {
            case .restoring:
                if isSigningIn {
                    LoginView(isAuthenticating: true)
                } else {
                    Color.AppPageBackground
                        .ignoresSafeArea()
                }
            case .signedIn:
                GeometryReader { proxy in
                    let topSafeAreaOffset = max(
                        proxy.safeAreaInsets.top - proxy.frame(in: .global).minY,
                        0
                    )

                    ZStack(alignment: .top) {
                        ContentView()
                            .ignoresSafeArea()

                        AppToastView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, topSafeAreaOffset + 7)
                            .padding(.horizontal, 16)
                            .allowsHitTesting(false)
                            .zIndex(1000)
                    }
                }
            case .signedOut:
                LoginView()
            case let .error(error):
                LoginView(error: error)
            }
        }
        .task {
            await authService.restoreSession()
        }
        .onChange(of: authService.state) { state in
            switch state {
            case .restoring:
                if hasResolvedInitialAuth {
                    isSigningIn = true
                }
            case .signedOut:
                hasResolvedInitialAuth = true
                isSigningIn = false
            case .signedIn:
                hasResolvedInitialAuth = true
                isSigningIn = false
            case .error:
                hasResolvedInitialAuth = true
                isSigningIn = false
            }

            switch state {
            case .signedOut, .error:
                remoteFinancialStore.resetRemoteState()
            default:
                break
            }
        }
    }
}
