# Phase 47: Device ID Namespace Resolution - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-10
**Phase:** 47-device-id-namespace-resolution
**Areas discussed:** Persistência UUID↔model, Thread UUID→CaptureFrameWriteQueue, Lookup bidirecional no servidor, Backfill de rows NULL

---

## Persistência do mapeamento UUID↔model

| Option | Description | Selected |
|--------|-------------|----------|
| UserDefaults + regeneração automática | Mapa actualizado na próxima ligação se UUID mudou. Rows antigos mantêm UUID anterior (válido historicamente). | ✓ |
| SQLite (tabela device_identity) | Persistido na DB, sobrevive a reinstalações. Mais complexo. | |

**User's choice:** UserDefaults + regeneração automática

| Option | Description | Selected |
|--------|-------------|----------|
| `["uuid-str"]: "device_model"` dict | Dict simples UUID→model. Codable. O(1). | ✓ |
| Array de {uuid, model, last_seen} | Inclui timestamp. Mais complexo. | |

**User's choice:** Dict simples `[String: String]`

---

## Thread do UUID até CaptureFrameWriteQueue

| Option | Description | Selected |
|--------|-------------|----------|
| Propriedade em GooseBLEClient + GooseAppModel propaga | `connectedPeripheralUUID` em GooseBLEClient; GooseAppModel actualiza queue em didConnect. Mesmo padrão de device_model. | ✓ |
| Passado por parâmetro em cada frame | Mais explícito, mais verboso. | |

**User's choice:** Propriedade + propagação pelo GooseAppModel

| Option | Description | Selected |
|--------|-------------|----------|
| GooseAppModel actualiza queue em didConnect | Consistente com padrão existente. | ✓ |
| Queue acede directamente ao BLE client | Cria acoplamento indesejado. | |

**User's choice:** GooseAppModel actualiza em didConnect

---

## Lookup bidirecional no servidor (UUID vs device_model)

| Option | Description | Selected |
|--------|-------------|----------|
| Try UUID parse, fallback para device_model | UUID válido → query por device_uuid. Caso contrário → query por device_model. Zero config para caller. | ✓ |
| Query param ?id_type=uuid\|model | Caller especifica tipo. Verbose mas sem ambiguidade. | |
| Dois endpoints separados | /by-uuid/ e /by-model/. Quebra ROADMAP spec. | |

**User's choice:** Try UUID parse, fallback para device_model

---

## Backfill de rows existentes com device_uuid NULL

| Option | Description | Selected |
|--------|-------------|----------|
| Deixar NULL — sem backfill | NULL é semanticamente correcto para dados pré-migração. | ✓ |
| Backfill com device_model como proxy | Não fiável se UUID já mudou. | |
| Backfill partial com último UUID known | Complexo e potencialmente errado. | |

**User's choice:** Deixar NULL — sem backfill

---

## Claude's Discretion

- Nome da propriedade em structs Rust (`device_uuid: Option<String>`)
- Número de versão do schema para esta migração
- SQL exacto para lookup bidirecional no FastAPI (try/except UUID parse)

## Deferred Ideas

Nenhuma — discussão manteve-se dentro do scope da Phase 47.
