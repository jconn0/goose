import CoreBluetooth
import Foundation


// Thread contract: all methods on this class must be called from the main thread.
// This is enforced by convention — every call site either runs on the @MainActor or
// dispatches via dispatchCoreBluetoothDelegateToMainIfNeeded before calling transition().
// Do NOT call transition() or access bondingState from a background queue.
final class GooseBLEBondingManager {
  private(set) var bondingState: GooseBLEBondingState = .notStarted

  // Callback invoked on every state transition (on main thread).
  var onBondingStateChange: ((GooseBLEBondingState) -> Void)?

  // UserDefaults keys owned by this manager.
  static let bondingStateKey = "goose.swift.ble.bondingState"
  static let bondingDeviceIDKey = "goose.swift.ble.bondingDeviceID"

  init() {
    loadPersistedState()
  }

  func transition(to newState: GooseBLEBondingState) {
    guard newState != bondingState else { return }
    bondingState = newState
    persistState()
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.onBondingStateChange?(self.bondingState)
    }
  }

  private func persistState() {
    UserDefaults.standard.set(bondingState.persistenceKey, forKey: Self.bondingStateKey)
    if case .completed(let id) = bondingState {
      UserDefaults.standard.set(id.uuidString, forKey: Self.bondingDeviceIDKey)
    }
  }

  private func loadPersistedState() {
    let key = UserDefaults.standard.string(forKey: Self.bondingStateKey) ?? ""
    switch key {
    case "completed":
      if let uuidString = UserDefaults.standard.string(forKey: Self.bondingDeviceIDKey),
         let uuid = UUID(uuidString: uuidString) {
        bondingState = .completed(deviceID: uuid)
      }
    default:
      bondingState = .notStarted
    }
  }
}
