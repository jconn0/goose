import SwiftUI

enum CoachProviderType: String {
  case chatgpt
  case claude
  case gemini
  case custom

  var requiresOAuth: Bool { self == .chatgpt }
}

struct CoachSignInScreen: View {
  let providerType: CoachProviderType
  let loginStatus: String
  let deviceCode: CodexLoginDeviceCode?
  let errorMessage: String?
  let signIn: () -> Void
  let openSettings: (() -> Void)?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: iconName)
            .font(.title2.weight(.bold))
            .foregroundStyle(iconTint)
            .frame(width: 42, height: 42)
            .background(iconTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

          Text("Sign in to Coach")
            .font(.title2.bold())
          Text(providerType.requiresOAuth
            ? "Sign in to stream Coach replies and local Goose tool calls."
            : "Enter your API key in Coach Settings to get started.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        VStack(alignment: .leading, spacing: 12) {
          if providerType.requiresOAuth {
            oAuthContent
          } else {
            apiKeyProviderContent
          }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
  }

  @ViewBuilder
  private var oAuthContent: some View {
    CoachStatusLine(title: "Sign in", value: loginStatus)

    if let deviceCode {
      VStack(alignment: .leading, spacing: 8) {
        Text(deviceCode.userCode)
          .font(.title2.monospacedDigit().weight(.bold))
        Link(deviceCode.verificationURL.absoluteString, destination: deviceCode.verificationURL)
          .font(.footnote.weight(.semibold))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    if let errorMessage, !errorMessage.isEmpty {
      Label(errorMessage, systemImage: "exclamationmark.triangle")
        .font(.footnote)
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
    }

    Button(action: signIn) {
      Label("Continue", systemImage: "person.crop.circle.badge.checkmark")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)

    Text("Coach sends the question plus bounded local tool output after approval. Tokens are stored in Keychain.")
      .font(.footnote)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private var apiKeyProviderContent: some View {
    Text(providerType == .gemini
      ? "Add your Google AI Studio API key in Coach Settings."
      : providerType == .claude
        ? "Add your Anthropic API key in Coach Settings."
        : "Configure your endpoint and API key in Coach Settings.")
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

    if let openSettings {
      Button(action: openSettings) {
        Label("Open Settings", systemImage: "gearshape")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)

      if providerType == .gemini {
        Link("Get an API key from Google AI Studio", destination: URL(string: "https://aistudio.google.com/apikey")!)
          .font(.footnote)
      }
    }
  }

  private var iconName: String {
    switch providerType {
    case .chatgpt: return "bubble.left.and.bubble.right.fill"
    case .claude: return "sparkles"
    case .gemini: return "globe"
    case .custom: return "server.rack"
    }
  }

  private var iconTint: Color {
    switch providerType {
    case .chatgpt: return .green
    case .claude: return .orange
    case .gemini: return .blue
    case .custom: return .purple
    }
  }
}

private struct CoachStatusLine: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
  }
}
