import SwiftUI
import DesignSystem

/// Email + password sign-in screen with Sign In / Create Account actions.
struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel: AuthViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NotovaSpacing.lg) {
                    header
                    if let viewModel {
                        form(viewModel)
                    } else {
                        ProgressView()
                    }
                }
                .padding(NotovaSpacing.lg)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("signIn.screen")
        .onAppear {
            if viewModel == nil {
                viewModel = AuthViewModel(session: session)
            }
        }
    }

    private var header: some View {
        VStack(spacing: NotovaSpacing.sm) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(NotovaColor.accent)
            Text("Sign in to Notova")
                .font(NotovaFont.title)
            Text("Accounts, integrations, and metadata sync run through the Notova backend. Your audio and AI stay on device.")
                .font(NotovaFont.caption)
                .foregroundStyle(NotovaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func form(_ viewModel: AuthViewModel) -> some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: NotovaSpacing.md) {
            TextField("Email", text: $viewModel.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("signIn.email")

            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("signIn.password")

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(NotovaFont.caption)
                    .foregroundStyle(NotovaColor.recording)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("signIn.error")
            }

            Button {
                Task { await viewModel.signIn() }
            } label: {
                buttonLabel("Sign In", busy: viewModel.isBusy)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("signIn.submit")

            Button {
                Task { await viewModel.createAccount() }
            } label: {
                Text("Create Account")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("signIn.createAccount")
        }
    }

    @ViewBuilder
    private func buttonLabel(_ title: String, busy: Bool) -> some View {
        HStack {
            if busy { ProgressView().tint(.white) }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}
