import SwiftUI

/// Signs in to an account on this device, or creates one. Passwords are
/// checked against a salted hash in the Keychain.
struct SignInSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case createAccount = "Create Account"
        var id: Self { self }
    }

    @Environment(UserStore.self) private var store
    @State private var mode: Mode
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case username, password, confirmation }

    init(mode: Mode? = nil) {
        _mode = State(initialValue: mode ?? .signIn)
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
            && (mode == .signIn || !confirmation.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(store.pending == nil
                         ? "An account lets you like, favorite, comment on, and make collections."
                         : "Sign in to finish what you started.")
                }

                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .username)
                        .onSubmit { focus = .password }
                        .accessibilityIdentifier("UsernameField")
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .submitLabel(mode == .signIn ? .go : .next)
                        .focused($focus, equals: .password)
                        .onSubmit {
                            if mode == .signIn { submit() } else { focus = .confirmation }
                        }
                        .accessibilityIdentifier("PasswordField")
                    if mode == .createAccount {
                        SecureField("Confirm Password", text: $confirmation)
                            .textContentType(.newPassword)
                            .submitLabel(.go)
                            .focused($focus, equals: .confirmation)
                            .onSubmit(submit)
                            .accessibilityIdentifier("ConfirmPasswordField")
                    }
                } footer: {
                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("SignInError")
                    } else if mode == .createAccount {
                        Text("Usernames are 3–20 letters, numbers, or underscores. Passwords need at least 8 characters.")
                    }
                }
            }
            .navigationTitle(mode.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.cancelSignIn() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .signIn ? "Sign In" : "Create", action: submit)
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("SubmitAccount")
                }
            }
            .onChange(of: mode) {
                error = nil
                confirmation = ""
            }
            .onChange(of: username) { error = nil }
            .onChange(of: password) { error = nil }
            .onChange(of: confirmation) { error = nil }
            .onAppear {
                // First account on this device? Start on Create Account.
                if !store.hasAccounts { mode = .createAccount }
                focus = .username
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        do {
            switch mode {
            case .signIn:
                try store.signIn(username: username, password: password)
            case .createAccount:
                guard password == confirmation else {
                    error = "The passwords don't match."
                    return
                }
                try store.createAccount(username: username, password: password)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Presents the sign-in sheet when `UserStore` asks for it.
///
/// Apply it at the root and inside any sheet that can trigger a gated action.
/// Only the most recently shown gate presents, because a view that's already
/// presenting a sheet can't present another one.
private struct SignInGate: ViewModifier {
    /// Runs after the sheet finishes dismissing, whether the user signed in or cancelled.
    let onDismiss: () -> Void

    @Environment(UserStore.self) private var store
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { store.signInGates.append(id) }
            .onDisappear { store.signInGates.removeAll { $0 == id } }
            .sheet(isPresented: isPresented, onDismiss: onDismiss) {
                SignInSheet()
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { store.isRequestingSignIn && store.signInGates.last == id },
            set: { if !$0 && store.isRequestingSignIn { store.cancelSignIn() } }
        )
    }
}

extension View {
    func signInGate(onDismiss: @escaping () -> Void = {}) -> some View {
        modifier(SignInGate(onDismiss: onDismiss))
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        SignInSheet()
    }
    .environment(UserStore(persistence: InMemoryUserStatePersistence()))
}
