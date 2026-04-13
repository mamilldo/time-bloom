//
//  LoginView.swift
//  TimeBloom
//
//  Minimal email/password form shown the first time the popover opens
//  (or after the refresh token is rejected). The popover stays open
//  while the request is in flight and switches to `TimerView` on
//  success because `PopoverRootView` observes `auth.isSignedIn`.
//

import SwiftUI

struct LoginView: View {

    let auth: AuthService

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    /// `@FocusState` lets us auto-focus the email field on appear and
    /// move focus to password when the user hits Tab/Return.
    @FocusState private var focused: Field?
    private enum Field { case email, password }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(Theme.brand)
                Text("Sign in to TimeBloom")
                    .font(.headline)
            }

            // Email
            VStack(alignment: .leading, spacing: 4) {
                Text("Email").font(.caption).foregroundStyle(.secondary)
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .focused($focused, equals: .email)
                    .onSubmit { focused = .password }
            }

            // Password
            VStack(alignment: .leading, spacing: 4) {
                Text("Password").font(.caption).foregroundStyle(.secondary)
                SecureField("••••••••", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .onSubmit { Task { await submit() } }
            }

            // Inline error banner
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Submit
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    }
                    Text(isSubmitting ? "Signing in…" : "Sign in")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
            .disabled(isSubmitting || email.isEmpty || password.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: Theme.popoverWidth)
        .onAppear { focused = .email }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await auth.signIn(email: email, password: password)
            // PopoverRootView observes `auth.isSignedIn` and swaps in
            // TimerView automatically — nothing to do here on success.
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
