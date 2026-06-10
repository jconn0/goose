# Phase 50: Morning Band Sleep Sync - Research

**Researched:** 2026-06-10
**Domain:** Rust bridge gravity extraction, Swift async BLE coordination, Cole-Kripke sleep pipeline
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Gravity Extraction Path**
- Inline no V24History branch de `capture.import_frame_batch` em bridge.rs (análogo ao K10 accel extraction)
- Extrair gravity_x/y/z (já disponíveis em DataPacketBodySummary::V24History) e acumular no vector gravity; inserir via insert_gravity_rows no final do batch
- gravity2_x/y/z (bytes 49–60) inserir em gravity2_samples quando present
- device_id: usar active_device_id passado ao import_frame_batch (mesmo padrão que HR/RR)

**Morning Sync Trigger**
- Observer connectionState em GooseAppModel (padrão existente): quando muda para "connected" verificar condições
- Condições: hora local > 04:00 E Calendar.current.isDateInToday(lastSyncDate) == false (ou lastSyncDate == nil)
- UserDefaults key: `goose.swift.last_band_sleep_sync_date` (Data)
- Drop+reconnect mesmo dia: idempotente — não dispara se lastBandSleepSyncDate == hoje
- Escrita do UserDefaults: ao iniciar syncBandSleepHistory (não ao completar, para evitar retry loop)

**syncBandSleepHistory Flow**
- Localização: novo ficheiro GooseAppModel+SleepSync.swift
- Janela overnight: ontem 20:00 local → hoje 12:00 local (cobre a maioria dos padrões de sono)
- SQLite-first: chamar gravity_rows_between antes de pedir BLE. Se rows >= 100 → usar dados existentes, skip BLE request
- Se rows < 100: disparar ble.startHistoricalSync() e aguardar (observar historicalSyncStatus == "complete")
- Após dados disponíveis: chamar bridge metrics.sleep_staging → inserir em external_sleep_sessions via store.insert_external_sleep_session com source="band_ble"
- Coordenação com overnight guard: syncBandSleepHistory só corre quando overnightGuardActive == false
- Status updates via store.markBandSleepSyncRequested / markBandSleepSyncFailed

**Sleep V2 Dashboard Label**
- Usar bandSleepImportStatus existente (zero UI nova necessária)
- Quando sync completa com sucesso: bandSleepImportStatus = "Sincronizado da pulseira"
- Estado inicial / sem sync: "A aguardar sincronização" (substituir "No band sync yet" inicial)
- SleepV2BandSyncCard já exibe este campo — sem alterações de UI necessárias

### Claude's Discretion
- Staging method a usar no external_sleep_session.provenance_json: `{"source":"band_ble","auto_sync":true}`
- Se sleep_staging retornar staging_method "no_imu" (gravity vazia) → não inserir sessão, marcar como "A aguardar sincronização"
- Threshold de 100 gravity rows pode ser ajustado empiricamente

### Deferred Ideas (OUT OF SCOPE)
- gravity2_samples análise (segunda tripla) — inserir apenas, análise para fase futura
- Calibração do threshold de gravity rows (100 samples) — empírico, ajustar com dados reais
- UI adicional além do bandSleepImportStatus — card separado no dashboard principal
- K21 gravity extraction — deferred conforme comentário existente no bridge.rs
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SLP-SYNC-01 | `gravity_x/y/z` de frames K18/K24 (offsets 33–44) promovidos de CANDIDATE para produção no parser Rust — validados contra captura real com valores conhecidos | V24History struct já tem gravity_x/y/z parsed do offset correto; gap é que V24History branch em bridge.rs não acumula no vec `gravity` nem chama `store.insert_gravity_rows()` |
| SLP-SYNC-02 | Ao ligar o WHOOP de manhã, o app dispara automaticamente o pipeline "Sync from band" → gravity_samples nocturnos → Cole-Kripke → external_sleep_sessions | `handleBLEConnectionStateChange` em GooseAppModel+Lifecycle.swift é o ponto de injeção; `syncHistoricalPackets()` + `metrics.sleep_staging` + `sleep.import_external_history` bridge já existem |
| SLP-SYNC-03 | Dados de sono sincronizados visíveis no Sleep V2 com label "Sincronizado da pulseira" | `bandSleepImportStatus` @Published já exibido em SleepV2BandSyncCard; apenas alterar o valor string |
</phase_requirements>

## Summary

Esta phase tem três componentes distintos:

**Componente 1 — Rust: V24History gravity extraction (SLP-SYNC-01).** O struct `DataPacketBodySummary::V24History` em `protocol.rs` já extrai `gravity_x/y/z` dos offsets 33–44 (f32 LE) e `gravity2_x/y/z` dos offsets 49–60. O parser já funciona. O gap é no `upload_get_recent_decoded_streams_bridge` em `bridge.rs`: o branch V24History (linha ~3412) processa HR, RR, SpO2, skin_temp, resp mas ignora os campos gravity com `..`. É necessário adicionar o mesmo padrão do K10 branch: extrair `gravity_x/y/z` do struct e push para o vec `gravity`. Dado que V24History tem um único sample por frame (não um array como K10), o push é direto sem o loop K10_SAMPLE_RATE_HZ.

**Componente 2 — Swift: morning sync trigger + syncBandSleepHistory (SLP-SYNC-02).** O ponto de injeção é `handleBLEConnectionStateChange(_ state: String)` em `GooseAppModel+Lifecycle.swift`, que já observa `state == "ready"`. Após a ligação, um novo método `maybeScheduleMorningSleepSync()` verifica: `!overnightGuardActive`, hora local > 04:00, `lastBandSleepSyncDate != today`. Se condições OK, dispara `syncBandSleepHistory()` definido em novo ficheiro `GooseAppModel+SleepSync.swift`. O flow dentro de `syncBandSleepHistory` é: (a) escrever UserDefaults imediatamente, (b) chamar bridge `store.gravity_rows_between` para SQLite-first check, (c) se rows < 100 disparar `ble.syncHistoricalPackets(rangeFirst: true)` e aguardar via `withCheckedContinuation` + `onHistoricalSyncCompleted`, (d) chamar bridge `metrics.sleep_staging`, (e) se staging_method != "no_imu_data" chamar bridge `sleep.import_external_history`, (f) actualizar `bandSleepImportStatus`.

**Componente 3 — Rust: testes cargo (SLP-SYNC-03 indirectamente).** Três testes novos: (1) V24 gravity extraction via `capture.import_frame_batch` — usar `build_v5_payload_frame` com packet_type=47 (PACKET_TYPE_HISTORICAL_DATA) e packet_k=24, offsets de gravity preenchidos com f32 LE known values; verificar via `upload.get_recent_decoded_streams`. (2) insert `external_sleep_sessions` com source="band_ble". (3) idempotência — segundo insert com mesmo sleep_id retorna unchanged=1, não erro.

**Primary recommendation:** Implementar em 3 planos: (1) Rust V24History gravity extraction + testes, (2) Swift GooseAppModel+SleepSync.swift + trigger em Lifecycle, (3) String update `bandSleepImportStatus` inicial + smoke test.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Gravity extraction from V24 frames | Rust core (bridge) | — | Parsing lógica está em bridge.rs; store.rs já tem insert_gravity_rows |
| Morning sync trigger decision | Swift (GooseAppModel @MainActor) | — | connectionState observation é @MainActor; guard overnightGuardActive é state do GooseAppModel |
| BLE historical sync request | BLE layer (GooseBLEClient) | GooseAppModel coordinator | syncHistoricalPackets() é método do GooseBLEClient; coordenação via onHistoricalSyncCompleted callback |
| Sleep staging computation | Rust core (bridge) | — | metrics.sleep_staging bridge lê gravity table e corre Cole-Kripke |
| external_sleep_sessions insert | Rust core (bridge) | — | sleep.import_external_history bridge já implementado com transaction + idempotência |
| Status display | Swift UI layer | HealthDataStore | bandSleepImportStatus @Published em HealthDataStore; SleepV2BandSyncCard consome |

## Standard Stack

### Core (todos já presentes no projecto)

| Library/Module | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| `DataPacketBodySummary::V24History` | — | Struct com gravity_x/y/z já parsed | Protocol.rs linha 166; já tem os campos correctos nos offsets certos |
| `store.insert_gravity_rows()` | — | Persist gravity samples to SQLite | Método já em store.rs linha 6542; aceita `&[(f64,f64,f64,f64)]` |
| `metrics.sleep_staging` bridge | — | Cole-Kripke 4-class sleep staging | Já implementado; lê gravity table; retorna SleepStagingOutput com staging_method |
| `sleep.import_external_history` bridge | — | Insert external_sleep_sessions + stages | Já implementado; transaction-safe; idempotent on same sleep_id + same metadata |
| `store.gravity_rows_between` bridge | — | SQLite-first check (>= 100 rows) | Já implementado; bridge method "store.gravity_rows_between" |
| `ble.syncHistoricalPackets(rangeFirst:)` | — | Trigger BLE historical sync | Já em GooseBLEClient+UserActions.swift; canSyncHistorical guarda |
| `HealthDataStore.markBandSleepSyncRequested()` | — | Status update no início | Já em HealthDataStore.swift linha 274 |
| `HealthDataStore.markBandSleepSyncFailed()` | — | Status update no falhanço | Já em HealthDataStore.swift linha 282 |
| `build_v5_payload_frame` | — | Helper de teste para construir frames BLE | Já importado nos testes (bridge_tests.rs linha 26) |

### Supporting

| Module | Purpose | When to Use |
|--------|---------|-------------|
| `onHistoricalSyncCompleted` callback | Coordinar conclusão async do sync BLE | Usado em AppShellView; phase 50 precisará de equivalente inline em GooseAppModel+SleepSync |
| `GooseAppModel.overnightGuardActive` | Guard para não interferir com overnight guard | Verificar antes de disparar syncBandSleepHistory |
| `Calendar.current.isDateInToday()` | Verificação data last sync | Idempotência: não re-sync no mesmo dia |

**Installation:** Nenhum package novo — stack 100% existente no projecto.

## Package Legitimacy Audit

Nenhum package externo novo nesta phase. Stack é inteiramente composto por código já existente no projecto.

| Package | Verdict | Disposition |
|---------|---------|-------------|
| (nenhum novo) | — | N/A |

**Packages removed due to SLOP verdict:** nenhum
**Packages flagged as suspicious SUS:** nenhum

## Architecture Patterns

### System Architecture Diagram

```
WHOOP BLE Device
      |
      | BLE notification (K18/K24 frames, PACKET_TYPE_HISTORICAL_DATA=47)
      v
GooseBLEClient.syncHistoricalPackets()
      |
      | frames via NotificationFrameParsing → CaptureFrameWriteQueue
      v
capture.import_frame_batch bridge (bridge.rs)
      |
      +---> raw_evidence table (SQLite)
      +---> decoded_frames table (SQLite)
      |     [V24History body_summary parsed, gravity_x/y/z available]
      |
      | [NOVO] V24History branch: extrair gravity_x/y/z → push to gravity vec
      v                          → store.insert_gravity_rows()
gravity table (SQLite)          → store.insert_gravity2_batch() se gravity2 present
      |
      | metrics.sleep_staging bridge
      | (reads gravity WHERE device_id AND ts BETWEEN sleep_start AND sleep_end)
      v
SleepStagingOutput { staging_method, epochs, stage_minutes, efficiency, ... }
      |
      | [if staging_method != "no_imu_data"]
      v
sleep.import_external_history bridge
      |
      +---> external_sleep_sessions (source="band_ble", platform="goose_ble")
      +---> external_sleep_stages (per epoch)
      v
HealthDataStore.bandSleepImportStatus = "Sincronizado da pulseira"
      |
      v
SleepV2BandSyncCard (SwiftUI) — already reads bandSleepImportStatus
```

**Morning sync trigger flow:**
```
iOS app launch / WHOOP reconnection
      |
      v
handleBLEConnectionStateChange(state: "ready")  [GooseAppModel+Lifecycle.swift]
      |
      +-- overnightGuardActive == true → return (guard active, skip)
      |
      +-- overnightGuardActive == false
            |
            v
      maybeScheduleMorningSleepSync()  [GooseAppModel+SleepSync.swift]
            |
            +-- Date().hour < 4 → skip (não é período matinal)
            |
            +-- Calendar.isDateInToday(lastBandSleepSyncDate) → skip (já sincronizado hoje)
            |
            +-- conditions OK
                  |
                  v
            syncBandSleepHistory()  [async Task]
                  |
                  1. Write UserDefaults "goose.swift.last_band_sleep_sync_date" = Date()
                  2. store.markBandSleepSyncRequested(automatic: true, ...)
                  3. store.gravity_rows_between(device_id, overnight_start_ts, overnight_end_ts)
                  |
                  +-- rows.count >= 100 → use existing gravity, skip BLE
                  |
                  +-- rows.count < 100
                        |
                        v
                  ble.syncHistoricalPackets(rangeFirst: true)
                  await withCheckedContinuation { cont in
                      onHistoricalSyncCompleted = { cont.resume() }
                  }
                  |
                  4. bridge metrics.sleep_staging(device_id, sleep_start_ts, sleep_end_ts)
                  |
                  +-- staging_method == "no_imu_data" → bandSleepImportStatus = "A aguardar sincronização"
                  |
                  +-- staging_method == "actigraphy_uncalibrated"
                        |
                        5. bridge sleep.import_external_history(sessions, stages)
                        6. bandSleepImportStatus = "Sincronizado da pulseira"
```

### Recommended Project Structure

```
GooseSwift/
├── GooseAppModel+SleepSync.swift    # NOVO — syncBandSleepHistory() + maybeScheduleMorningSleepSync()
├── GooseAppModel+Lifecycle.swift    # MODIFICAR — injetar maybeScheduleMorningSleepSync() em handleBLEConnectionStateChange
└── HealthDataStore.swift            # MODIFICAR — bandSleepImportStatus initial value

Rust/core/src/
└── bridge.rs                        # MODIFICAR — V24History branch: adicionar gravity accumulation

Rust/core/tests/
└── bridge_tests.rs                  # MODIFICAR — 3 novos testes gravity V24 + external_sleep + idempotência
```

### Pattern 1: V24History Gravity Extraction (análogo ao K10)

**What:** Adicionar gravity_x/y/z ao vec `gravity` no match arm V24History em `upload_get_recent_decoded_streams_bridge` em bridge.rs. Diferença vs K10: K10 tem 100 samples/frame (loop), V24History tem 1 sample/frame (push directo).

**When to use:** Este padrão é o correcto para o V24History branch porque cada frame K18/K24 contém um único snapshot de gravity (f32 LE nos offsets 33–44 do body V24).

```rust
// Source: bridge.rs ~linha 3412 (modificação do match arm existente)
DataPacketBodySummary::V24History {
    hr: v24_hr,
    rr_intervals_ms,
    skin_contact,
    spo2_red,
    spo2_ir,
    skin_temp_raw,
    resp_raw,
    gravity_x,    // ADD: bind these fields instead of ..
    gravity_y,
    gravity_z,
    gravity2_x,
    gravity2_y,
    gravity2_z,
    ..
} => {
    // ... existing HR/RR/SpO2/skin_temp/resp code unchanged ...

    // NOVO: gravity_x/y/z — single sample per V24 frame (no loop needed unlike K10)
    if let (Some(ts), Some(x), Some(y), Some(z)) =
        (ts_unix, *gravity_x, *gravity_y, *gravity_z)
    {
        gravity.push(json!({
            "ts": ts,
            "x": x as f64,
            "y": y as f64,
            "z": z as f64,
        }));
    }

    // NOVO: gravity2 — optional second triplet (bytes 49–60), insert if present
    if let (Some(ts), Some(x2), Some(y2), Some(z2)) =
        (ts_unix, *gravity2_x, *gravity2_y, *gravity2_z)
    {
        gravity2.push(json!({
            "ts": ts,
            "x": x2 as f64,
            "y": y2 as f64,
            "z": z2 as f64,
        }));
    }
}
```

**Note:** O vec `gravity2` também precisa de ser declarado antes do loop (análogo ao `gravity` vec) e inserido via `store.insert_gravity2_batch()` no final do batch.

**Note crítica:** A gravidade não usa unidade de conversão LSB→g aqui (ao contrário do K10), porque o protocol.rs já parseia diretamente como `f32` em unidades de g (os campos são `Option<f32>`, não `Option<i16>`). [VERIFIED: protocol.rs linha 171-173]

### Pattern 2: Swift async historical sync coordination

**What:** Usar `withCheckedContinuation` para aguardar a conclusão do BLE historical sync antes de correr o pipeline.

**When to use:** Quando precisamos de awaitar um callback-based API (`onHistoricalSyncCompleted`) numa função `async`.

```swift
// Source: GooseAppModel+SleepSync.swift (novo ficheiro, padrão estabelecido)
// Nota: onHistoricalSyncCompleted é var (() -> Void)? em GooseAppModel.swift linha 72

func syncBandSleepHistory() async {
    guard !overnightGuardActive else { return }

    let dbPath = HealthDataStore.defaultDatabasePath()
    let deviceId = ble.activeDeviceIdentifier?.uuidString ?? ""

    // 1. Write UserDefaults imediatamente (evita retry loop em drop+reconnect)
    UserDefaults.standard.set(Date(), forKey: GooseAppModel.DefaultsKey.lastBandSleepSyncDate)

    await healthStore.markBandSleepSyncRequested(automatic: true, canSync: ble.canSyncHistorical, detail: "")

    // 2. Overnight window: yesterday 20:00 → today 12:00 local
    let (overnightStart, overnightEnd) = Self.overnightWindow()

    // 3. SQLite-first check
    let gravityCount = await gravityRowCount(dbPath: dbPath, deviceId: deviceId,
                                              startTs: overnightStart, endTs: overnightEnd)
    if gravityCount < 100 {
        guard ble.canSyncHistorical else {
            await healthStore.markBandSleepSyncFailed("BLE sync unavailable: \(ble.historicalSyncStatus)")
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            onHistoricalSyncCompleted = {
                self.onHistoricalSyncCompleted = nil
                continuation.resume()
            }
            ble.syncHistoricalPackets(rangeFirst: true)
        }
    }

    // 4. Run sleep staging
    let stagingResult = try? await bridge.requestAsync(method: "metrics.sleep_staging", args: [
        "database_path": dbPath,
        "device_id": deviceId,
        "sleep_start_ts": overnightStart,
        "sleep_end_ts": overnightEnd,
    ])
    let stagingMethod = stagingResult?["staging_method"] as? String ?? "no_imu_data"
    guard stagingMethod != "no_imu_data" else {
        bandSleepImportStatus = "A aguardar sincronização"
        return
    }

    // 5. Insert external_sleep_session + stages
    // ... build sessions/stages from stagingResult, call sleep.import_external_history ...

    bandSleepImportStatus = "Sincronizado da pulseira"
}
```

### Pattern 3: Construir frame K24 para testes Rust

**What:** Construir um frame BLE completo de K24 (PACKET_TYPE_HISTORICAL_DATA=47, packet_k=24, body V24) para usar nos testes de `capture.import_frame_batch`.

**When to use:** Nos testes do bridge para verificar que a gravity extraction funciona end-to-end.

```rust
// Source: bridge_tests.rs — padrão análogo ao historical_k18_frame_hex() linha 8875
fn historical_k24_frame_hex_with_gravity(gx: f32, gy: f32, gz: f32) -> String {
    // V24 body: mínimo 77 bytes de data após os 3 bytes de header do payload
    // payload layout: [0]=packet_type(47), [1]=packet_k(24), [2]=version(1),
    //                 [3..]=body (data offset 0 começa aqui)
    // data[33..37] = gravity_x f32 LE
    // data[37..41] = gravity_y f32 LE
    // data[41..45] = gravity_z f32 LE
    let mut payload = vec![0u8; 3 + 79]; // 3 header + 79 body = 82 bytes
    payload[0] = PACKET_TYPE_HISTORICAL_DATA; // 47
    payload[1] = 24u8;  // packet_k = 24 (K24)
    payload[2] = 1u8;   // version

    // timestamp bytes (data[0..4] = device epoch seconds, little-endian)
    // leave as 0 for test predictability

    // gravity_x at data offset 33 = payload offset 3+33 = 36
    let gx_bytes = gx.to_le_bytes();
    payload[3 + 33..3 + 37].copy_from_slice(&gx_bytes);
    let gy_bytes = gy.to_le_bytes();
    payload[3 + 37..3 + 41].copy_from_slice(&gy_bytes);
    let gz_bytes = gz.to_le_bytes();
    payload[3 + 41..3 + 45].copy_from_slice(&gz_bytes);

    // skin_contact = 1 (data offset 48) so HR/SpO2 gates pass
    payload[3 + 48] = 1u8;

    hex::encode(build_v5_payload_frame(&payload))
}
```

**Nota importante:** O `timestamp_seconds` em DataPacket vem do device epoch, não de um timestamp absoluto. Para testes, usar `captured_at` no frame de import como fonte de tempo — o bridge usa `captured_at` como fallback quando `timestamp_seconds` é 0 ou ausente. [ASSUMED — verificar comportamento exato do timestamp fallback no bridge]

### Anti-Patterns to Avoid

- **Chamar bridge na @MainActor:** `metrics.sleep_staging` e `sleep.import_external_history` são operações Rust sincronas bloqueantes — SEMPRE usar `bridge.requestAsync()` (Task.detached) nunca `bridge.request()` no @MainActor. Padrão estabelecido na Phase 49. [VERIFIED: GooseRustBridge.swift linha 83-88]

- **Re-usar onHistoricalSyncCompleted sem nil-guard:** O callback `onHistoricalSyncCompleted` é `var (() -> Void)?` em GooseAppModel. É necessário fazer nil-guard e restaurar para nil após invocar, para não interferir com o callback do AppShellView que também usa este campo.

- **Assumir que capture.import_frame_batch insere na gravity table:** `capture.import_frame_batch` apenas insere em `raw_evidence` e `decoded_frames`. A extracção de gravity para a tabela `gravity` acontece em `upload_get_recent_decoded_streams_bridge` que lê `decoded_frames` e retorna a gravity no payload de upload — mas NÃO persiste na gravity table. A inserção na gravity table é feita separadamente via `store.insert_gravity_rows`. [VERIFIED: capture_import.rs — sem referência a insert_gravity_rows; bridge.rs ~linha 3519: gravity retornado em JSON mas não persisted via insert_gravity_rows nesse path]

  **Implicação crítica:** A decisão do CONTEXT.md de "inserir via insert_gravity_rows no final do batch" em `upload_get_recent_decoded_streams_bridge` é o padrão correcto. Confirmar com o utilizador: a gravity deve ser persistida DENTRO de `upload_get_recent_decoded_streams_bridge` (que já tem acesso ao store), não em `capture_import.rs`.

- **Usar gravity2 para sleep staging:** `metrics.sleep_staging` lê apenas a tabela `gravity`, não `gravity2_samples`. Inserir gravity2 é correcto mas não afecta o pipeline Cole-Kripke desta phase.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sleep staging algoritmo | Custom Cole-Kripke | `metrics.sleep_staging` bridge | Já implementado na Phase 26; 4-class com HR feature; reading from gravity table |
| External sleep session insert com idempotência | INSERT OR IGNORE custom | `sleep.import_external_history` bridge | Já implementado com transaction + conflict detection + stage cascade |
| Gravity SQLite insert | Custom SQL | `store.insert_gravity_rows()` | Já em store.rs; `INSERT OR IGNORE` on (device_id, ts) já garante dedup |
| UserDefaults date key naming | Ad-hoc String | `static let` em `GooseAppModel.DefaultsKey` ou struct análoga | Padrão do projecto: reverse-DNS estático no tipo |
| BLE historical sync aguardar | Polling loop | `onHistoricalSyncCompleted` + `withCheckedContinuation` | Callback já existe; evita busy-wait; pattern consistente com AppShellView |

**Key insight:** Toda a infraestrutura (gravity table, sleep staging bridge, external_sleep_sessions bridge, BLE sync callback) já existe. Esta phase é essencialmente wiring de componentes existentes + um gap cirúrgico no V24History branch.

## Common Pitfalls

### Pitfall 1: active_device_id ausente na gravity extraction

**What goes wrong:** `store.insert_gravity_rows()` requer `device_id != ""`. Se `active_device_id` não for passado ao `upload_get_recent_decoded_streams_bridge`, a gravity não pode ser persistida com o device_id correcto.

**Why it happens:** `upload_get_recent_decoded_streams_bridge` recebe `device_id` como arg mas o CaptureImportFrameBatchArgs tem `active_device_id: Option<String>`. A bridge `upload.get_recent_decoded_streams` já recebe `device_id` como parâmetro distinto.

**How to avoid:** Na bridge `upload_get_recent_decoded_streams_bridge`, usar o `args.device_id` para inserir gravity rows. Para `capture.import_frame_batch`, a gravity deve ser extraída e inserida usando `active_device_id` (que pode ser None — usar fallback para `device_model` do frame se necessário).

**Warning signs:** `gravity_rows_between` retorna 0 rows mesmo após import de K24 frames.

### Pitfall 2: V24History timestamp é device epoch (não Unix)

**What goes wrong:** `DataPacket.timestamp_seconds` em V24History é um device epoch counter, não Unix timestamp absoluto. Se usado directamente como ts na gravity table, os rows ficam com timestamps incorrectos (~0 ou valor muito baixo).

**Why it happens:** O WHOOP usa um epoch interno relativo ao boot ou ao RTC. O bridge já lida com isto para HR/RR via `ts_unix: Option<f64> = timestamp_seconds.map(|s| s as f64)` — o valor pode ser 0 se não houver RTC sync.

**How to avoid:** Para testes, usar `captured_at` do frame como base temporal (ISO-8601) convertido via `unix_from_iso8601`. Em produção, os frames terão timestamp válido via RTC sync (Phase 12 wired clock sync). O padrão actual no bridge já usa `timestamp_seconds.map(|s| s as f64)` — seguir o mesmo.

**Warning signs:** Testes de `gravity_rows_between` com janela overnight retornam 0 rows porque as gravity rows ficaram com ts=0.

### Pitfall 3: onHistoricalSyncCompleted conflito com AppShellView

**What goes wrong:** `AppShellView` também seta `model.onHistoricalSyncCompleted` (linha 21) para chamar `healthStore.runPacketInputs()`. Se `syncBandSleepHistory` sobrescrever este callback sem restaurar, o AppShellView behavior quebra.

**Why it happens:** `onHistoricalSyncCompleted` é uma `var (() -> Void)?` em GooseAppModel — um único slot de callback.

**How to avoid:** Em `syncBandSleepHistory`, guardar o callback anterior, restaurar após uso. Ou usar um mecanismo diferente (e.g., Task que observa `ble.historicalSyncStatus` mudando para "complete"). O CONTEXT.md descreve observar `historicalSyncStatus == "complete"` — esta abordagem evita o conflito de callback.

**Warning signs:** Após morning sync, o AppShellView não actualiza os packet inputs quando o utilizador dispara historical sync manualmente.

### Pitfall 4: sleep_id não-determinístico causa duplicados

**What goes wrong:** Se `syncBandSleepHistory` for chamado duas vezes (e.g., após drop+reconnect), o segundo insert gera um novo `sleep_id` (UUID aleatório) e insere um segundo `external_sleep_session` duplicado para a mesma noite.

**Why it happens:** `store.insert_external_sleep_session` usa `UNIQUE(platform, platform_record_id)` como constraint de deduplicação — mas se `platform_record_id` for None ou diferente, o UNIQUE constraint não previne duplicados.

**How to avoid:** Construir um `sleep_id` determinístico baseado em `device_id + date(overnightStart)`, e.g., `"band_ble.{device_id}.{date_string}"`. O UserDefaults guard (escrever `lastBandSleepSyncDate` no início, verificar no trigger) é a primeira linha de defesa — mas o sleep_id determinístico é a garantia de idempotência ao nível Rust.

**Warning signs:** Múltiplos `external_sleep_sessions` com source="band_ble" para a mesma noite.

### Pitfall 5: gravity vec declarado mas gravity2 vec não

**What goes wrong:** O vec `gravity` já existe no `upload_get_recent_decoded_streams_bridge`. O vec `gravity2` precisa de ser declarado separadamente. Se esquecido, o compilador Rust dará erro ao tentar fazer push para `gravity2`.

**How to avoid:** Declarar `let mut gravity2: Vec<serde_json::Value> = Vec::new();` no mesmo bloco que os outros vecs, e adicionar o insert via `store.insert_gravity2_batch()` no final.

## Code Examples

### Exemplo: Construir sleep_id determinístico

```swift
// Source: established pattern in project (UUID-based IDs throughout)
// Para evitar duplicados, sleep_id é baseado em device_id + data da noite
static func bandSleepId(deviceId: String, overnightStartDate: Date) -> String {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.timeZone = TimeZone.current
  let dateStr = formatter.string(from: overnightStartDate)
  return "band_ble.\(deviceId).\(dateStr)"
}
```

### Exemplo: Janela overnight (yesterday 20:00 → today 12:00)

```swift
// Source: CONTEXT.md decision — 20:00→12:00 overnight window
static func overnightWindow() -> (Double, Double) {
  let calendar = Calendar.current
  let now = Date()
  // today 12:00 local
  var todayNoonComponents = calendar.dateComponents([.year, .month, .day], from: now)
  todayNoonComponents.hour = 12
  todayNoonComponents.minute = 0
  todayNoonComponents.second = 0
  let todayNoon = calendar.date(from: todayNoonComponents) ?? now

  // yesterday 20:00 local
  let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
  var yesterdayEveningComponents = calendar.dateComponents([.year, .month, .day], from: yesterday)
  yesterdayEveningComponents.hour = 20
  yesterdayEveningComponents.minute = 0
  yesterdayEveningComponents.second = 0
  let yesterdayEvening = calendar.date(from: yesterdayEveningComponents) ?? yesterday

  return (yesterdayEvening.timeIntervalSince1970, todayNoon.timeIntervalSince1970)
}
```

### Exemplo: Verificação hora matinal

```swift
// Source: CONTEXT.md decision — trigger only after 04:00 local
func isMorningWindowActive() -> Bool {
  let hour = Calendar.current.component(.hour, from: Date())
  return hour >= 4
}
```

### Exemplo: SleepStagingOutput → ExternalSleepSession input

```swift
// Source: bridge.rs sleep.import_external_history args structure (linha 7408)
// staging_result vem de metrics.sleep_staging response
let sleepId = GooseAppModel.bandSleepId(deviceId: deviceId, overnightStartDate: overnightStartDate)
let stageMinutes = stagingResult["stage_minutes"] as? [String: Double] ?? [:]
let stageSummaryJson: [String: Any] = stageMinutes.mapValues { $0 }
let provenanceJson: [String: Any] = ["source": "band_ble", "auto_sync": true]

let sessionArgs: [String: Any] = [
  "sleep_id": sleepId,
  "source": "band_ble",
  "platform": "goose_ble",
  "start_time_unix_ms": Int64(overnightStart * 1000),
  "end_time_unix_ms": Int64(overnightEnd * 1000),
  "confidence": 0.7,
  "stage_summary": stageSummaryJson,
  "provenance": provenanceJson,
]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Gravity ignorada no V24History branch | Gravity extraída e persistida na tabela `gravity` | Phase 50 | Desbloqueia sleep staging com dados overnight da pulseira |
| Manual band sync via botão UI | Morning auto-sync na ligação WHOOP > 04:00 | Phase 50 | Zero friction — dados de sono disponíveis automaticamente |
| "No band sync yet" string inicial | "A aguardar sincronização" (pt-PT) | Phase 50 | Consistência linguística com o dashboard |

**Deprecated/outdated:**
- `"No band sync yet"` como valor inicial de `bandSleepImportStatus` → substituir por `"A aguardar sincronização"` (HealthDataStore.swift linha 16)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | O timestamp_seconds em V24History frames capturados durante overnight sync corresponde ao RTC real do device (não epoch 0), tornando a janela de gravity_rows_between correcta | Common Pitfalls #2, Code Examples | Se timestamps forem 0, gravity rows ficam fora da janela overnight e sleep staging retorna no_imu_data — sync falha silenciosamente |
| A2 | `upload_get_recent_decoded_streams_bridge` tem acesso ao store e pode chamar `store.insert_gravity_rows()` inline — a função não é read-only | Architecture Patterns, Pattern 1 | Se for read-only (e.g., sem write transaction), precisa de bridge separado ou de inserir via `capture_import.rs` |
| A3 | `onHistoricalSyncCompleted` pode ser usado temporariamente por `syncBandSleepHistory` sem quebrar `AppShellView` desde que seja restaurado a nil | Common Pitfalls #3 | Se AppShellView ou outro caller fizer set concorrente, pode haver race condition |
| A4 | A estrutura de stages para `sleep.import_external_history` pode ser construída directamente dos epochs do SleepStagingOutput — bridge aceita stages individuais | Code Examples | Se o bridge requerer um formato diferente de stages, o insert vai falhar com validation error |

**Se a tabela tem entradas:** Confirmar A1 e A2 com o utilizador antes da implementação; são os riscos de maior impacto.

## Open Questions (RESOLVED)

1. **Onde inserir gravity na tabela — upload bridge vs capture_import?**
   - What we know: `capture_import.rs` não insere gravity; `upload_get_recent_decoded_streams_bridge` tem o vec `gravity` mas retorna-o no JSON sem persistir
   - What's unclear: A decisão do CONTEXT.md diz "no final do batch em `capture.import_frame_batch`" mas tecnicamente a extracção de gravity está em `upload_get_recent_decoded_streams_bridge`. Os dois bridges são separados.
   - Recommendation: Adicionar a gravity extraction E insert em `upload_get_recent_decoded_streams_bridge` (onde o código já existe mas falta o insert) MAIS tornar o mesmo código acessível via `capture.import_frame_batch` (reutilizando store.insert_gravity_rows dentro do transaction). A opção mais simples é adicionar o insert dentro de `upload_get_recent_decoded_streams_bridge` porque é onde o vec gravity já está populado.
   - **RESOLVED (Plan 50-01):** Gravity extraction and `store.insert_gravity_rows()` call are placed inside `upload_get_recent_decoded_streams_bridge` where the `gravity` vec is already populated. This is the implementation path chosen by Plan 50-01.

2. **Como aguardar o histórico BLE sync sem conflito de callback?**
   - What we know: `onHistoricalSyncCompleted` é um único slot de callback; AppShellView usa-o
   - What's unclear: Se `syncBandSleepHistory` roda automaticamente na ligação (antes do AppShellView se registar), pode não haver conflito na prática
   - Recommendation: Usar observação de `ble.historicalSyncStatus` com `withTaskGroup` ou polling via Task, em vez de onHistoricalSyncCompleted, para evitar o conflito de callback por completo.
   - **RESOLVED (Plan 50-02):** BLE sync coordination uses `historicalSyncStatus` polling (Task.sleep loop, 1s intervals, max 120 attempts). `onHistoricalSyncCompleted` is NOT used — it remains exclusively owned by AppShellView to avoid single-slot callback conflict (Pitfall #3).

## Environment Availability

Nenhuma dependência externa nova. Esta phase é código/config apenas.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Rust toolchain | cargo test | ✓ | MSRV 1.94 | — |
| Xcode | Build Swift | ✓ | iOS 26.0 SDK | — |
| GooseStore gravity table | insert_gravity_rows | ✓ | Schema v19 (gravity table exists) | — |
| metrics.sleep_staging bridge | SLP-SYNC-02 | ✓ | Phase 26 implementado | — |
| sleep.import_external_history bridge | SLP-SYNC-02 | ✓ | Phase anterior implementado | — |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Rust built-in test runner (cargo test) |
| Config file | Rust/core/Cargo.toml |
| Quick run command | `cargo test -p goose-core 2>&1 | tail -20` |
| Full suite command | `cargo test -p goose-core` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SLP-SYNC-01 | gravity_x/y/z extraídos de K24 frame e presentes no resultado | unit (Rust) | `cargo test -p goose-core bridge_v24_gravity_extraction` | ❌ Wave 0 |
| SLP-SYNC-01 | gravity rows persistidos em SQLite após import K24 frame | unit (Rust) | `cargo test -p goose-core bridge_v24_gravity_insert_roundtrip` | ❌ Wave 0 |
| SLP-SYNC-02 | external_sleep_sessions inserido com source="band_ble" | unit (Rust) | `cargo test -p goose-core bridge_band_sleep_external_session_insert` | ❌ Wave 0 |
| SLP-SYNC-02 | segundo insert com mesmo sleep_id retorna unchanged, não erro | unit (Rust) | `cargo test -p goose-core bridge_band_sleep_no_duplicate` | ❌ Wave 0 |
| SLP-SYNC-03 | bandSleepImportStatus = "Sincronizado da pulseira" após sync | manual | build + simulator | N/A (manual) |

### Sampling Rate
- **Per task commit:** `cargo test -p goose-core 2>&1 | tail -20`
- **Per wave merge:** `cargo test -p goose-core`
- **Phase gate:** Full suite green antes do `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `Rust/core/tests/bridge_tests.rs` — adicionar: `bridge_v24_gravity_extraction`, `bridge_v24_gravity_insert_roundtrip`, `bridge_band_sleep_external_session_insert`, `bridge_band_sleep_no_duplicate`
- [ ] `GooseSwift/GooseAppModel+SleepSync.swift` — ficheiro novo; sem testes Swift automatizados (padrão do projecto)

## Security Domain

`security_enforcement: true` per config.json.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Rust bridge já valida `device_id != ""` em `insert_gravity_rows`; `validate_external_sleep_session_input` já implementado em store.rs |
| V6 Cryptography | no | — |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Gravity rows com device_id vazio | Tampering | `validate_required("device_id", ...)` já em `insert_gravity_rows` |
| Duplicate external_sleep_sessions | Tampering | sleep_id determinístico + `UNIQUE(platform, platform_record_id)` constraint |
| UserDefaults date guard bypass | Elevation | Guard é best-effort anti-spam; sleep_id determinístico é a garantia de idempotência real |

## Sources

### Primary (HIGH confidence)
- `Rust/core/src/protocol.rs` linha 166-190 — V24History struct com gravity_x/y/z/gravity2_x/y/z fields
- `Rust/core/src/protocol.rs` linha 725-732 — offsets de parsing: gravity_x=33, gravity_y=37, gravity_z=41 (f32 LE); gravity2 a partir de 49 se len>=60
- `Rust/core/src/bridge.rs` linha 3412-3464 — V24History branch em upload_get_recent_decoded_streams_bridge (não tem gravity extraction — gap confirmado)
- `Rust/core/src/bridge.rs` linha 3367-3398 — K10 accel extraction pattern (referência para implementar V24)
- `Rust/core/src/store.rs` linha 6542-6560 — insert_gravity_rows signature e insert pattern
- `Rust/core/src/store.rs` linha 6590-6608 — insert_gravity2_batch
- `Rust/core/src/store.rs` linha 4659-4716 — insert_external_sleep_session com idempotência
- `Rust/core/src/bridge.rs` linha 4136-4168 — sleep_staging_bridge: lê gravity_rows_between, corre 4-class, retorna SleepStagingOutput
- `Rust/core/src/sleep_staging.rs` linha 35 — STAGING_METHOD_NO_IMU = "no_imu_data"
- `Rust/core/src/sleep_staging.rs` linha 97-118 — SleepStagingOutput fields
- `GooseSwift/HealthDataStore.swift` linha 16, 274, 282, 286 — bandSleepImportStatus, markBandSleepSyncRequested, markBandSleepSyncFailed, refreshSleepAfterBandSync
- `GooseSwift/GooseAppModel+Lifecycle.swift` linha 115-165 — handleBLEConnectionStateChange (ponto de injeção)
- `GooseSwift/GooseAppModel.swift` linha 72 — onHistoricalSyncCompleted callback slot
- `GooseSwift/GooseBLEClient.swift` linha 870 — canSyncHistorical guard
- `GooseSwift/GooseBLEClient+UserActions.swift` — syncHistoricalPackets(rangeFirst:)
- `Rust/core/src/capture_import.rs` linha 258-373 — import_captured_frame_batch_with_output_options_in_transaction: não insere na gravity table
- `Rust/core/tests/v24_biometric_protocol_tests.rs` linha 7-103 — make_82_byte_payload() helper e offsets V24 confirmados
- `Rust/core/tests/bridge_tests.rs` linha 8875-8899 — historical_k18_frame_hex() como template para K24 frame builder

### Secondary (MEDIUM confidence)
- CONTEXT.md decisions — locked choices para gravity extraction path, sync trigger, SQLite-first threshold

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — todos os componentes verificados directamente no código
- Architecture: HIGH — gap confirmado no V24History branch, padrão K10 confirmado, bridges existentes verificados
- Pitfalls: HIGH — baseados em análise de código real; pitfall do timestamp marcado ASSUMED
- Open Questions: MEDIUM — questão da inserção de gravity requer confirmação do utilizador

**Research date:** 2026-06-10
**Valid until:** Estável — código Rust/Swift não muda frequentemente; válido por 30 dias
