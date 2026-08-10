# Authentication Foundation V1

The current authentication path is:

```text
SignInWithAppleButton → Supabase Auth (GoTrue) → Supabase access JWT → AuthTokenProvider → APIClient → FastAPI
```

The app uses a small URLSession-based GoTrue client because the project did not already contain a Supabase Swift package. Supabase is used by iOS only for authentication and session management. Financial data remains behind the existing FastAPI repositories.

## Public iOS configuration

Configure these public values in the app scheme/build environment or the app's local build configuration:

```text
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_PUBLISHABLE_KEY=<Supabase publishable key>
```

The iOS target must never receive `DATABASE_URL`, database credentials, a service-role key, or a JWT signing secret. `Info.plist` contains build-setting placeholders only.

## Apple and Supabase setup

1. In the Apple Developer account, enable Sign in with Apple for the app identifier and use the same team/bundle identifier as the Xcode target.
2. In Supabase Auth provider settings, enable Apple and configure the Apple credentials requested by the dashboard.
3. In Xcode, select the app target, choose the development team, and verify the Sign in with Apple capability is present.

The exact Apple Services ID, key ID, team ID, redirect URL, and private key are project-specific and are intentionally not guessed or committed.

## Session and request policy

Supabase sessions are stored in Keychain. Expired or near-expiry access tokens are refreshed through a single actor-owned refresh task. The APIClient remains unaware of Apple and Supabase; it requests a bearer token only through `AuthTokenProvider`.

The current API policy is to obtain a fresh token before each authenticated request and surface a FastAPI `401` without retrying it. This avoids an implicit retry loop; a later API-layer retry can be added as a separate, explicit policy if needed.

Authentication is handled through Sign in with Apple and Supabase Auth. The iOS app uses Supabase directly only for authentication and session management; application and financial data are accessed through the FastAPI backend backed by Supabase PostgreSQL. The app no longer relies on local Core Data or CloudKit for financial storage.
