import Foundation
import SwiftUI
import UIKit

@MainActor
final class MoreRemoteServerViewModel: ObservableObject {
  @Published var serverURL: String
  @Published var bearerToken: String
  @Published var uploadEnabled: Bool
  @Published private(set) var urlValidationError: String?
  @Published var saveSuccess: Bool = false

  init() {
    serverURL = UserDefaults.standard.string(forKey: RemoteServerStorage.serverURL) ?? ""
    bearerToken = (try? RemoteServerKeychain.loadToken()) ?? ""
    uploadEnabled = UserDefaults.standard.bool(forKey: RemoteServerStorage.uploadEnabled)
  }

  func save() {
    guard RemoteServerURLValidator.validate(serverURL) else {
      urlValidationError = "Invalid URL. Use https://hostname for public servers, or http:// for local IPs and .local hostnames."
      return
    }
    urlValidationError = nil
    UserDefaults.standard.set(serverURL, forKey: RemoteServerStorage.serverURL)
    UserDefaults.standard.set(uploadEnabled, forKey: RemoteServerStorage.uploadEnabled)
    try? RemoteServerKeychain.saveToken(bearerToken)
    saveSuccess = true
  }
}

struct MoreRemoteServerView: View {
  @StateObject private var vm = MoreRemoteServerViewModel()
  @Environment(GooseAppModel.self) private var model

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f
  }()

  private var uploadIsActive: Bool {
    vm.uploadEnabled && !vm.serverURL.isEmpty
  }

  var body: some View {
    Form {
      Section("Server") {
        TextField("https://hostname:8770", text: $vm.serverURL)
          .keyboardType(.URL)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
        if let error = vm.urlValidationError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Section("Authentication") {
        SecureField("Bearer token (API key)", text: $vm.bearerToken)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
      }

      Section("Upload") {
        Toggle("Enable Upload", isOn: $vm.uploadEnabled)
      }

      if uploadIsActive {
        Section("Status") {
          // Row 1: Server reachability
          Label {
            switch model.serverReachable {
            case .none:
              Text("Checking...").foregroundStyle(.secondary)
            case .some(true):
              Text("Server reachable").foregroundStyle(.green)
            case .some(false):
              Text("Server unreachable").foregroundStyle(.red)
            }
          } icon: {
            switch model.serverReachable {
            case .none:
              ProgressView().scaleEffect(0.7)
            case .some(true):
              Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .some(false):
              Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
          }

          // Row 1b: Manual connection test (auth-validated)
          LabeledContent("Test Connection") {
            HStack(spacing: 8) {
              if model.connectionTestRunning {
                ProgressView().scaleEffect(0.7)
              } else if let result = model.connectionTestResult {
                Text(result)
                  .font(.caption)
                  .foregroundStyle(result.hasPrefix("✅") ? .green : result.hasPrefix("⚠️") ? .orange : .red)
                  .lineLimit(1)
                  .minimumScaleFactor(0.7)
              } else {
                Text("Not tested").foregroundStyle(.secondary)
              }
              Button("Test") {
                model.testServerConnection()
              }
              .buttonStyle(.bordered)
              .controlSize(.mini)
              .disabled(model.connectionTestRunning)
            }
          }

          // Row 2: Last sync + ACK count + manual trigger
          LabeledContent("Last sync") {
            HStack(spacing: 8) {
              if let lastUpload = model.lastUploadAt {
                VStack(alignment: .trailing, spacing: 1) {
                  Text(Self.relativeDateFormatter.localizedString(for: lastUpload, relativeTo: Date()))
                    .foregroundStyle(.secondary)
                  if let count = model.lastSyncedCount {
                    Text("\(count) records acked")
                      .font(.caption2)
                      .foregroundStyle(.green)
                  }
                }
              } else {
                Text("Never").foregroundStyle(.secondary)
              }
              Button("Now") {
                model.triggerManualUpload()
              }
              .buttonStyle(.bordered)
              .controlSize(.mini)
            }
          }

          // Row 3: Pending batch count
          LabeledContent("Pending batches") {
            Text("\(model.pendingBatchCount)")
              .foregroundStyle(model.pendingBatchCount > 0 ? .orange : .secondary)
          }

          // Row 4: Rows pending sync flag
          LabeledContent("Sync pendente") {
            HStack(spacing: 8) {
              if model.syncPendingRowCount > 0 {
                Text("\(model.syncPendingRowCount) rows")
                  .foregroundStyle(.orange)
              } else {
                Text("0 rows")
                  .foregroundStyle(.secondary)
              }
              Button("Backfill") {
                model.triggerBackfillAndUpload()
              }
              .buttonStyle(.bordered)
              .controlSize(.mini)
            }
          }

          // Row 5: Trust-chain import from server
          LabeledContent("Server import") {
            HStack(spacing: 8) {
              if model.serverImportInProgress {
                ProgressView().scaleEffect(0.7)
                Text("Importing…").foregroundStyle(.secondary)
              } else if let count = model.serverImportLastFrameCount {
                Text("\(count) frames").foregroundStyle(.green)
              } else {
                Text("Not run").foregroundStyle(.secondary)
              }
              Button("Import") {
                model.importHistoricalDataFromServer()
              }
              .buttonStyle(.bordered)
              .controlSize(.mini)
              .disabled(model.serverImportInProgress)
            }
          }
        }
      }

      Section {
        Button("Save") {
          vm.save()
          if vm.urlValidationError == nil {
            model.checkServerHealth()
          }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
      }
    }
    .navigationTitle("Remote Server")
    .navigationBarTitleDisplayMode(.inline)
    .listStyle(.insetGrouped)
    .gooseListBackground()
    .alert("Settings saved", isPresented: $vm.saveSuccess) {
      Button("OK") {}
    }
    .onAppear {
      model.refreshSyncPendingCount()
    }
  }
}

// MARK: - Previews

#Preview("Status — Checking") {
  NavigationStack {
    MoreRemoteServerView()
  }
  .environment({
    let m = GooseAppModel()
    m.serverReachable = nil
    m.lastUploadAt = nil
    m.pendingBatchCount = 0
    return m
  }())
}

#Preview("Status — Reachable") {
  NavigationStack {
    MoreRemoteServerView()
  }
  .environment({
    let m = GooseAppModel()
    m.serverReachable = true
    m.lastUploadAt = Date().addingTimeInterval(-120)
    m.pendingBatchCount = 0
    return m
  }())
}

#Preview("Status — Unreachable") {
  NavigationStack {
    MoreRemoteServerView()
  }
  .environment({
    let m = GooseAppModel()
    m.serverReachable = false
    m.lastUploadAt = nil
    m.pendingBatchCount = 2
    return m
  }())
}

// Cronometer connection settings — enter email/password to link your
// Cronometer account. Credentials are stored in the iOS Keychain and
// used to fetch daily nutrition totals for correlation with WHOOP data.
struct MoreCronometerSettingsView: View {
  @State private var email = ""
  @State private var password = ""
  @State private var isTesting = false
  @State private var statusMessage = ""
  @State private var isConnected = CronometerKeychain.hasCredentials()

  var body: some View {
    Form {
      Section {
        if isConnected {
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text("Connected to Cronometer")
              .font(.subheadline)
          }
          Button("Disconnect", role: .destructive) {
            try? CronometerKeychain.deleteCredentials()
            isConnected = false
            email = ""
            password = ""
            statusMessage = ""
          }
        } else {
          TextField("Email", text: $email)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
          SecureField("Password", text: $password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
      } header: {
        Text("Account")
      } footer: {
        Text("Your credentials are stored in the iOS Keychain. They are never sent to the Goose server — only directly to Cronometer to fetch nutrition totals.")
      }

      if !isConnected {
        Section {
          Button(action: connect) {
            HStack {
              if isTesting {
                ProgressView().scaleEffect(0.8)
              }
              Text("Connect")
                .frame(maxWidth: .infinity)
            }
          }
          .disabled(email.isEmpty || password.isEmpty || isTesting)
        }
      }

      if !isConnected && !statusMessage.isEmpty {
        Section {
          Text(statusMessage)
            .font(.caption)
            .foregroundStyle(statusMessage.hasPrefix("Success") ? .green : .red)
        }
      }
    }
    .navigationTitle("Cronometer")
    .navigationBarTitleDisplayMode(.inline)
    .listStyle(.insetGrouped)
    .gooseListBackground()
  }

  private func connect() {
    guard !email.isEmpty, !password.isEmpty else { return }
    isTesting = true
    statusMessage = ""
    Task {
      do {
        let result = try await GooseCronometerAuth.verifyCredentials(
          email: email, password: password)
        await MainActor.run {
          try? CronometerKeychain.saveCredentials(email: email, password: password)
          isConnected = true
          statusMessage = "Success — logged in as \(result["name"] as? String ?? email)"
        }
      } catch {
        await MainActor.run {
          statusMessage = "Connection failed: \(error.localizedDescription)"
        }
      }
      await MainActor.run { isTesting = false }
    }
  }
}
