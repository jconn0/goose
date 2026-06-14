use rusqlite::{OptionalExtension, params};
use serde::{Deserialize, Serialize};

use crate::{GooseError, GooseResult, protocol, store::GooseStore};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EcgSessionInput<'a> {
    pub session_id: &'a str,
    pub started_at: &'a str,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EcgSessionRow {
    pub session_id: String,
    pub status: String,
    pub started_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub finished_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_seconds: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avg_heart_rate_bpm: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub classification: Option<String>,
    #[serde(default)]
    pub symptoms_json: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EcgSessionFrameInput<'a> {
    pub session_id: &'a str,
    pub frame_id: &'a str,
    pub packet_type: i64,
    pub sample_count: i64,
    pub flags: Option<i64>,
    pub channels_gain: &'a str,
    pub captured_at: &'a str,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EcgSessionFrameRow {
    pub id: i64,
    pub session_id: String,
    pub frame_id: String,
    pub packet_type: i64,
    pub sample_count: i64,
    pub flags: Option<i64>,
    pub channels_gain: Option<String>,
    pub captured_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EcgSessionDetail {
    pub session: EcgSessionRow,
    pub frames: Vec<EcgSessionFrameRow>,
    pub sample_count_total: i64,
}

pub fn extract_labrador_samples_from_hex(
    hex_payload: &str,
) -> GooseResult<protocol::LabradorSamplesResult> {
    let payload = hex::decode(hex_payload)
        .map_err(|error| GooseError::message(format!("cannot decode payload hex: {error}")))?;
    protocol::extract_labrador_samples(&payload).ok_or_else(|| {
        GooseError::message("payload too short for Labrador frame".to_string())
    })
}

fn validate_required(name: &str, value: &str) -> GooseResult<()> {
    if value.trim().is_empty() {
        return Err(GooseError::message(format!("{name} must be non-empty")));
    }
    Ok(())
}

impl GooseStore {
    pub fn ensure_ecg_tables(&self) -> GooseResult<()> {
        self.conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS ecg_sessions (
                session_id TEXT PRIMARY KEY,
                status TEXT NOT NULL DEFAULT 'recording',
                started_at TEXT NOT NULL,
                finished_at TEXT,
                duration_seconds REAL,
                avg_heart_rate_bpm INTEGER,
                classification TEXT,
                symptoms_json TEXT NOT NULL DEFAULT '[]',
                notes TEXT,
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
            );

            CREATE TABLE IF NOT EXISTS ecg_session_frames (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL REFERENCES ecg_sessions(session_id) ON DELETE CASCADE,
                frame_id TEXT NOT NULL REFERENCES decoded_frames(frame_id) ON DELETE CASCADE,
                packet_type INTEGER NOT NULL,
                sample_count INTEGER NOT NULL,
                flags INTEGER,
                channels_gain BLOB,
                captured_at TEXT NOT NULL,
                UNIQUE(session_id, frame_id)
            );

            CREATE INDEX IF NOT EXISTS idx_ecg_session_frames_session
                ON ecg_session_frames(session_id);
            "#,
        )?;
        Ok(())
    }

    pub fn start_ecg_session(&self, input: EcgSessionInput<'_>) -> GooseResult<bool> {
        validate_required("session_id", input.session_id)?;
        validate_required("started_at", input.started_at)?;
        self.ensure_ecg_tables()?;
        let changed = self.conn.execute(
            "INSERT OR IGNORE INTO ecg_sessions(session_id, started_at) VALUES (?1, ?2)",
            params![input.session_id, input.started_at],
        )?;
        Ok(changed > 0)
    }

    pub fn record_ecg_frame(&self, input: EcgSessionFrameInput<'_>) -> GooseResult<bool> {
        validate_required("session_id", input.session_id)?;
        validate_required("frame_id", input.frame_id)?;
        self.ensure_ecg_tables()?;

        let channels_gain_blob = if input.channels_gain.is_empty() {
            None
        } else {
            Some(hex::decode(input.channels_gain).unwrap_or_default())
        };

        let changed = self.conn.execute(
            "INSERT OR IGNORE INTO ecg_session_frames(session_id, frame_id, packet_type, sample_count, flags, channels_gain, captured_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                input.session_id,
                input.frame_id,
                input.packet_type,
                input.sample_count,
                input.flags,
                channels_gain_blob,
                input.captured_at,
            ],
        )?;
        Ok(changed > 0)
    }

    pub fn finish_ecg_session(
        &self,
        session_id: &str,
        finished_at: &str,
        avg_heart_rate_bpm: Option<i64>,
        classification: Option<&str>,
    ) -> GooseResult<EcgSessionRow> {
        validate_required("session_id", session_id)?;
        self.ensure_ecg_tables()?;

        let duration: Option<f64> = self.conn.query_row(
            "SELECT (julianday(?1) - julianday(started_at)) * 86400.0 FROM ecg_sessions WHERE session_id = ?2",
            params![finished_at, session_id],
            |row| row.get(0),
        ).optional()?.flatten();

        self.conn.execute(
            "UPDATE ecg_sessions SET status = 'completed', finished_at = ?2, duration_seconds = ?3, avg_heart_rate_bpm = ?4, classification = ?5 WHERE session_id = ?1",
            params![session_id, finished_at, duration, avg_heart_rate_bpm, classification],
        )?;

        self.ecg_session(session_id)?.ok_or_else(|| {
            GooseError::message(format!("ecg session {session_id} not found after finish"))
        })
    }

    pub fn ecg_session(&self, session_id: &str) -> GooseResult<Option<EcgSessionRow>> {
        validate_required("session_id", session_id)?;
        self.conn.query_row(
            "SELECT session_id, status, started_at, finished_at, duration_seconds, avg_heart_rate_bpm, classification, symptoms_json, notes
             FROM ecg_sessions WHERE session_id = ?1",
            params![session_id],
            |row| {
                Ok(EcgSessionRow {
                    session_id: row.get(0)?,
                    status: row.get(1)?,
                    started_at: row.get(2)?,
                    finished_at: row.get(3)?,
                    duration_seconds: row.get(4)?,
                    avg_heart_rate_bpm: row.get(5)?,
                    classification: row.get(6)?,
                    symptoms_json: row.get::<_, String>(7).unwrap_or_else(|_| "[]".to_string()),
                    notes: row.get(8)?,
                })
            },
        ).optional()
    }

    pub fn list_ecg_sessions(&self) -> GooseResult<Vec<EcgSessionRow>> {
        self.ensure_ecg_tables()?;
        let mut stmt = self.conn.prepare(
            "SELECT session_id, status, started_at, finished_at, duration_seconds, avg_heart_rate_bpm, classification, symptoms_json, notes
             FROM ecg_sessions ORDER BY started_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(EcgSessionRow {
                session_id: row.get(0)?,
                status: row.get(1)?,
                started_at: row.get(2)?,
                finished_at: row.get(3)?,
                duration_seconds: row.get(4)?,
                avg_heart_rate_bpm: row.get(5)?,
                classification: row.get(6)?,
                symptoms_json: row.get::<_, String>(7).unwrap_or_else(|_| "[]".to_string()),
                notes: row.get(8)?,
            })
        })?;
        let mut sessions = Vec::new();
        for row in rows {
            sessions.push(row?);
        }
        Ok(sessions)
    }

    pub fn get_ecg_session_detail(&self, session_id: &str) -> GooseResult<Option<EcgSessionDetail>> {
        let session = match self.ecg_session(session_id)? {
            Some(s) => s,
            None => return Ok(None),
        };

        let mut stmt = self.conn.prepare(
            "SELECT id, session_id, frame_id, packet_type, sample_count, flags, channels_gain, captured_at
             FROM ecg_session_frames WHERE session_id = ?1 ORDER BY captured_at ASC",
        )?;
        let rows = stmt.query_map(params![session_id], |row| {
            Ok(EcgSessionFrameRow {
                id: row.get(0)?,
                session_id: row.get(1)?,
                frame_id: row.get(2)?,
                packet_type: row.get(3)?,
                sample_count: row.get(4)?,
                flags: row.get(5)?,
                channels_gain: row.get::<_, Option<Vec<u8>>>(6)?.map(|b| hex::encode(b)),
                captured_at: row.get(7)?,
            })
        })?;
        let mut frames = Vec::new();
        let mut sample_count_total: i64 = 0;
        for row in rows {
            let frame = row?;
            sample_count_total += frame.sample_count;
            frames.push(frame);
        }

        Ok(Some(EcgSessionDetail {
            session,
            frames,
            sample_count_total,
        }))
    }

    pub fn set_ecg_session_classification(
        &self,
        session_id: &str,
        classification: &str,
    ) -> GooseResult<Option<EcgSessionRow>> {
        validate_required("session_id", session_id)?;
        self.conn.execute(
            "UPDATE ecg_sessions SET classification = ?2 WHERE session_id = ?1",
            params![session_id, classification],
        )?;
        self.ecg_session(session_id)
    }

    pub fn set_ecg_session_symptoms_notes(
        &self,
        session_id: &str,
        symptoms_json: &str,
        notes: Option<&str>,
    ) -> GooseResult<Option<EcgSessionRow>> {
        validate_required("session_id", session_id)?;
        self.conn.execute(
            "UPDATE ecg_sessions SET symptoms_json = ?2, notes = ?3 WHERE session_id = ?1",
            params![session_id, symptoms_json, notes],
        )?;
        self.ecg_session(session_id)
    }

    pub fn delete_ecg_session(&self, session_id: &str) -> GooseResult<bool> {
        validate_required("session_id", session_id)?;
        let changed = self.conn.execute(
            "DELETE FROM ecg_sessions WHERE session_id = ?1",
            params![session_id],
        )?;
        Ok(changed > 0)
    }
}
