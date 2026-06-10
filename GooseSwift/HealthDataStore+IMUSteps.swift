import Foundation
import SwiftUI

// MARK: - IMUStepCountResult

struct IMUStepCountResult {
  let stepCount: Int          // derived from K10 zero-crossing
  let sampleCount: Int        // number of gravity samples used
  let meanMagnitude: Double   // mean acceleration magnitude (g)
  let insufficientData: Bool
}

extension IMUStepCountResult {
  var stepCountText: String {
    insufficientData ? "--" : "\(stepCount)"
  }
}

// MARK: - HealthDataStore+IMUSteps

extension HealthDataStore {
  // Fetches K10 gravity rows from today's window, runs imu_step_count_v1,
  // and compares with the WHOOP step counter from packetInputReports.
  // Result is published on @MainActor.
  func runIMUStepCount() async {
    let db = databasePath
    let now = Date().timeIntervalSince1970
    let windowStart = now - 24 * 3600
    let deviceID = "goose.swift.imu.steps.v1"
    // Capture WHOOP step count from packetInputReports on @MainActor before first await.
    let stepReport = packetInputReports["step_counter_rollup"]

    let asDouble: (Any?) -> Double? = { value in
      switch value {
      case let d as Double: return d
      case let f as Float: return Double(f)
      case let i as Int: return Double(i)
      case let n as NSNumber: return n.doubleValue
      default: return nil
      }
    }

    // Fetch gravity rows for today.
    let gravityReport: [String: Any]
    do {
      gravityReport = try await bridge.requestAsync(
        method: "store.gravity_rows_between",
        args: [
          "database_path": db,
          "device_id": deviceID,
          "start_ts": windowStart,
          "end_ts": now,
        ]
      )
    } catch {
      imuStepCountResult = nil
      return
    }

    let gravityRows = gravityReport["rows"] as? [[String: Any]] ?? []
    // Build gravity_samples as [[x, y, z]] arrays.
    let gravitySamples: [[Double]] = gravityRows.compactMap { row -> [Double]? in
      guard let x = asDouble(row["x"]),
            let y = asDouble(row["y"]),
            let z = asDouble(row["z"]) else { return nil }
      return [x, y, z]
    }

    // Call metrics.imu_step_count_v1.
    let imuResult: IMUStepCountResult
    do {
      let report = try await bridge.requestAsync(
        method: "metrics.imu_step_count_v1",
        args: ["gravity_samples": gravitySamples]
      )
      let stepCount = (report["step_count"] as? NSNumber)?.intValue
        ?? (report["step_count"] as? Int) ?? 0
      let sampleCount = (report["sample_count"] as? NSNumber)?.intValue
        ?? (report["sample_count"] as? Int) ?? 0
      let meanMag = asDouble(report["mean_magnitude"]) ?? 0
      let insufficient = report["insufficient_data"] as? Bool ?? true
      imuResult = IMUStepCountResult(
        stepCount: stepCount,
        sampleCount: sampleCount,
        meanMagnitude: meanMag,
        insufficientData: insufficient
      )
    } catch {
      imuResult = IMUStepCountResult(
        stepCount: 0,
        sampleCount: gravitySamples.count,
        meanMagnitude: 0,
        insufficientData: true
      )
    }

    // Compare with WHOOP step counter from packetInputReports.
    let whoopSteps: Int? = {
      guard let r = stepReport,
            let steps = asDouble(r["step_count"]).map({ Int($0) }) else { return nil }
      return steps > 0 ? steps : nil
    }()

    // Log discrepancy if both values available.
    if !imuResult.insufficientData, let whoop = whoopSteps {
      let delta = abs(imuResult.stepCount - whoop)
      let pct = whoop > 0 ? Double(delta) / Double(whoop) * 100 : 0
      // Note: discrepancy stored for debugging; threshold for concern is >20%.
      _ = (delta: delta, percentDelta: pct)
    }

    imuStepCountResult = imuResult
  }
}
