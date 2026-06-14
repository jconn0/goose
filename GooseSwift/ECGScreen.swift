import SwiftUI

struct ECGScreen: View {
  var store: HealthDataStore
  @State private var controller = ECGSessionController.shared
  @State private var selectedSession: ECGSession?

  var body: some View {
    List {
      Section {
        Button {
          Task {
            let success = await controller.startRecording()
            if !success {
              await controller.loadRecentSessions()
            }
          }
        } label: {
          Label("Take an ECG", systemImage: "waveform.path.ecg")
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(controller.isRecording)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }

      Section {
        if controller.isLoadingSessions {
          HStack {
            Spacer()
            ProgressView("Loading sessions...")
            Spacer()
          }
        } else if controller.recentSessions.isEmpty {
          Text("No ECG recordings yet")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        } else {
          ForEach(controller.recentSessions) { session in
            Button {
              selectedSession = session
            } label: {
              ECGSessionRow(session: session)
            }
            .buttonStyle(.plain)
          }
        }
      } header: {
        Text("Past Recordings")
      }
    }
    .navigationTitle("ECG")
    .task {
      await controller.loadRecentSessions()
    }
    .sheet(item: $selectedSession) { session in
      NavigationStack {
        ECGSessionDetailView(session: session)
      }
    }
    .sheet(isPresented: Binding(
      get: { controller.isRecording },
      set: { if !$0 { Task { await controller.cancelRecording() } } }
    )) {
      NavigationStack {
        ECGLiveRecordingView()
      }
    }
  }
}

struct ECGSessionRow: View {
  let session: ECGSession

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: session.classification == "sinus_rhythm" ? "heart.fill" : "waveform.path.ecg")
        .font(.title3)
        .foregroundStyle(session.status == "completed" ? .green : .orange)
        .frame(width: 32)

      VStack(alignment: .leading, spacing: 2) {
        Text(session.startedDate?.formatted(date: .abbreviated, time: .shortened) ?? session.startedAt)
          .font(.subheadline.weight(.medium))
        HStack(spacing: 6) {
          Text(session.durationFormatted)
            .font(.caption)
            .foregroundStyle(.secondary)
          if let hr = session.avgHeartRateBpm {
            Text("\(hr) BPM")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      Spacer()

      Text(session.classificationLabel)
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }
    .padding(.vertical, 4)
  }
}

struct ECGSessionDetailView: View {
  let session: ECGSession

  var body: some View {
    List {
      Section("Recording Info") {
        LabeledContent("Status", value: session.status.capitalized)
        if let hr = session.avgHeartRateBpm {
          LabeledContent("Avg Heart Rate", value: "\(hr) BPM")
        }
        LabeledContent("Duration", value: session.durationFormatted)
        if let start = session.startedDate {
          LabeledContent("Date", value: start.formatted(date: .long, time: .shortened))
        }
      }

      Section("Result") {
        LabeledContent("Classification", value: session.classificationLabel)
      }

      if !session.symptoms.isEmpty {
        Section("Symptoms") {
          ForEach(session.symptoms, id: \.self) { symptom in
            Text(symptom)
          }
        }
      }

      if let notes = session.notes, !notes.isEmpty {
        Section("Notes") {
          Text(notes)
        }
      }
    }
    .navigationTitle("ECG Result")
  }
}

struct ECGLiveRecordingView: View {
  @State private var controller = ECGSessionController.shared

  var body: some View {
    VStack(spacing: 0) {
      TimelineView(.animation) { context in
        VStack(spacing: 16) {
          Text("\(Int(controller.recordingDuration - controller.recordingElapsed))s")
            .font(.system(size: 48, weight: .bold, design: .monospaced))
            .foregroundStyle(controller.recordingElapsed > 25 ? .green : .primary)

          Text(controller.signalQuality.label)
            .font(.subheadline)
            .foregroundStyle(.secondary)

          if let hr = controller.currentHeartRate {
            Text("\(hr) BPM")
              .font(.title2.weight(.medium))
              .foregroundStyle(.red)
          }
        }
      }

      Spacer()

      Text("Recording in progress...")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 16)

      Button(role: .destructive) {
        Task { await controller.cancelRecording() }
      } label: {
        Label("Cancel Recording", systemImage: "xmark.circle")
      }
      .padding(.bottom, 32)
    }
    .navigationTitle("Recording ECG")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          Task { await controller.cancelRecording() }
        }
      }
    }
  }
}
