using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services.Contracts;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class StateStoreService : IStateStore, IDisposable
{
    private const int SchemaVersion = 3;
    private static readonly TimeSpan PruneInterval = TimeSpan.FromHours(12);
    private readonly SemaphoreSlim _dbGate = new(1, 1);
    private readonly string _connectionString;
    private volatile bool _initialized;

    public string DatabasePath { get; }

    public StateStoreService()
    {
        var root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsGameRuntimeASUSSelfHealing",
            "State");
        DatabasePath = Path.Combine(root, "state-v1.db");
        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = DatabasePath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Private,
            Pooling = true
        }.ToString();
    }

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        if (_initialized) return;
        await ExecuteAsync(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = """
                PRAGMA journal_mode=WAL;
                PRAGMA synchronous=NORMAL;
                PRAGMA foreign_keys=ON;
                PRAGMA busy_timeout=5000;
                PRAGMA wal_autocheckpoint=256;
                PRAGMA journal_size_limit=4194304;

                CREATE TABLE IF NOT EXISTS metadata (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_utc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS event_cursors (
                    stream TEXT PRIMARY KEY,
                    cursor_utc TEXT NOT NULL,
                    updated_utc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS event_sync_state (
                    stream TEXT PRIMARY KEY,
                    last_attempt_utc TEXT NOT NULL,
                    last_success_utc TEXT NOT NULL,
                    last_new_count INTEGER NOT NULL,
                    last_error TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS crash_events (
                    event_key TEXT PRIMARY KEY,
                    occurred_utc TEXT NOT NULL,
                    log_name TEXT NOT NULL,
                    record_id INTEGER NOT NULL,
                    category TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    provider TEXT NOT NULL,
                    event_id INTEGER NOT NULL,
                    process_name TEXT NOT NULL,
                    message TEXT NOT NULL,
                    first_seen_utc TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_crash_events_occurred ON crash_events(occurred_utc DESC);
                CREATE INDEX IF NOT EXISTS ix_crash_events_grouping ON crash_events(category, provider, event_id, process_name, occurred_utc DESC);

                CREATE TABLE IF NOT EXISTS dump_analyses (
                    analysis_id TEXT PRIMARY KEY,
                    file_name TEXT NOT NULL,
                    file_path TEXT NOT NULL,
                    file_size_bytes INTEGER NOT NULL,
                    exception_code TEXT NOT NULL,
                    exception_name TEXT NOT NULL,
                    exception_address TEXT NOT NULL,
                    faulting_module TEXT NOT NULL,
                    category TEXT NOT NULL,
                    confidence TEXT NOT NULL,
                    core_reason TEXT NOT NULL,
                    evidence TEXT NOT NULL,
                    analyzed_utc TEXT NOT NULL,
                    report_path TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_dump_analyses_time ON dump_analyses(analyzed_utc DESC);

                CREATE TABLE IF NOT EXISTS component_state (
                    component_key TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    installed TEXT NOT NULL,
                    target TEXT NOT NULL,
                    runtime TEXT NOT NULL,
                    error_code TEXT NOT NULL,
                    status TEXT NOT NULL,
                    detail TEXT NOT NULL,
                    component_group TEXT NOT NULL,
                    observed_utc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS repair_transactions (
                    transaction_id TEXT PRIMARY KEY,
                    type TEXT NOT NULL,
                    component_group TEXT NOT NULL,
                    label TEXT NOT NULL,
                    state TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    last_detail TEXT NOT NULL,
                    cached_utc TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_transactions_updated ON repair_transactions(updated_at DESC);

                CREATE TABLE IF NOT EXISTS incidents (
                    incident_key TEXT PRIMARY KEY,
                    code TEXT NOT NULL,
                    component TEXT NOT NULL,
                    confidence TEXT NOT NULL,
                    score TEXT NOT NULL,
                    evidence TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    observed_utc TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_incidents_observed ON incidents(observed_utc DESC);

                CREATE TABLE IF NOT EXISTS observations (
                    observation_id TEXT PRIMARY KEY,
                    transaction_id TEXT NOT NULL,
                    state TEXT NOT NULL,
                    detail TEXT NOT NULL,
                    observed_utc TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_observations_tx ON observations(transaction_id, observed_utc DESC);

                CREATE TABLE IF NOT EXISTS workflow_state (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    phase INTEGER NOT NULL,
                    type TEXT NOT NULL,
                    component_group TEXT NOT NULL,
                    eligible INTEGER NOT NULL,
                    state TEXT NOT NULL,
                    detail TEXT NOT NULL,
                    updated_utc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS workflow_history (
                    history_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    phase INTEGER NOT NULL,
                    type TEXT NOT NULL,
                    component_group TEXT NOT NULL,
                    eligible INTEGER NOT NULL,
                    state TEXT NOT NULL,
                    detail TEXT NOT NULL,
                    observed_utc TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_workflow_history_observed ON workflow_history(observed_utc DESC);
                """;
            command.ExecuteNonQuery();

            SetMetadata(connection, "schema_version", SchemaVersion.ToString(CultureInfo.InvariantCulture));
            return 0;
        }, cancellationToken).ConfigureAwait(false);
        _initialized = true;
    }

    public async Task<DateTimeOffset?> GetEventCursorAsync(string stream, CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        return await ExecuteAsync<DateTimeOffset?>(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT cursor_utc FROM event_cursors WHERE stream=$stream LIMIT 1;";
            command.Parameters.AddWithValue("$stream", stream);
            return ParseDateTimeOffset(command.ExecuteScalar()?.ToString());
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task SetEventCursorAsync(string stream, DateTimeOffset cursorUtc, CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO event_cursors(stream, cursor_utc, updated_utc)
                VALUES($stream, $cursor, $updated)
                ON CONFLICT(stream) DO UPDATE SET cursor_utc=excluded.cursor_utc, updated_utc=excluded.updated_utc;
                """;
            command.Parameters.AddWithValue("$stream", stream);
            command.Parameters.AddWithValue("$cursor", cursorUtc.ToUniversalTime().ToString("O"));
            command.Parameters.AddWithValue("$updated", DateTimeOffset.UtcNow.ToString("O"));
            command.ExecuteNonQuery();
            return 0;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task RecordEventSyncAsync(
        string stream,
        DateTimeOffset attemptedUtc,
        bool success,
        int newEventCount,
        string error = "",
        CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection =>
        {
            var previousSuccess = "";
            using (var read = connection.CreateCommand())
            {
                read.CommandText = "SELECT last_success_utc FROM event_sync_state WHERE stream=$stream LIMIT 1;";
                read.Parameters.AddWithValue("$stream", stream);
                previousSuccess = read.ExecuteScalar()?.ToString() ?? "";
            }

            using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO event_sync_state(stream, last_attempt_utc, last_success_utc, last_new_count, last_error)
                VALUES($stream, $attempt, $success, $count, $error)
                ON CONFLICT(stream) DO UPDATE SET
                    last_attempt_utc=excluded.last_attempt_utc,
                    last_success_utc=excluded.last_success_utc,
                    last_new_count=excluded.last_new_count,
                    last_error=excluded.last_error;
                """;
            command.Parameters.AddWithValue("$stream", stream);
            command.Parameters.AddWithValue("$attempt", attemptedUtc.ToUniversalTime().ToString("O"));
            command.Parameters.AddWithValue("$success", success ? attemptedUtc.ToUniversalTime().ToString("O") : previousSuccess);
            command.Parameters.AddWithValue("$count", Math.Max(0, newEventCount));
            command.Parameters.AddWithValue("$error", success ? "" : error);
            command.ExecuteNonQuery();
            return 0;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<int> UpsertCrashEventsAsync(IEnumerable<CrashEventRecord> events, CancellationToken cancellationToken = default)
    {
        var rows = events.ToArray();
        if (rows.Length == 0) return 0;
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        return await ExecuteAsync(connection =>
        {
            var inserted = 0;
            using var transaction = connection.BeginTransaction();
            foreach (var item in rows)
            {
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText = """
                    INSERT OR IGNORE INTO crash_events(
                        event_key, occurred_utc, log_name, record_id, category, severity,
                        provider, event_id, process_name, message, first_seen_utc)
                    VALUES($key, $time, $log, $record, $category, $severity,
                        $provider, $eventId, $process, $message, $seen);
                    """;
                command.Parameters.AddWithValue("$key", item.EventKey);
                command.Parameters.AddWithValue("$time", item.OccurredUtc.ToUniversalTime().ToString("O"));
                command.Parameters.AddWithValue("$log", item.LogName);
                command.Parameters.AddWithValue("$record", item.RecordId);
                command.Parameters.AddWithValue("$category", item.Category);
                command.Parameters.AddWithValue("$severity", item.Severity);
                command.Parameters.AddWithValue("$provider", item.Provider);
                command.Parameters.AddWithValue("$eventId", item.EventId);
                command.Parameters.AddWithValue("$process", item.ProcessName);
                command.Parameters.AddWithValue("$message", item.Message);
                command.Parameters.AddWithValue("$seen", DateTimeOffset.UtcNow.ToString("O"));
                inserted += command.ExecuteNonQuery();
            }
            transaction.Commit();
            return inserted;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<CrashEventItem>> ReadCrashEventGroupsAsync(int days = 7, int maxEvents = 120, CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        return await ExecuteAsync<IReadOnlyList<CrashEventItem>>(connection =>
        {
            var result = new List<CrashEventItem>();
            using var command = connection.CreateCommand();
            command.CommandText = """
                WITH ranked AS (
                    SELECT occurred_utc, category, severity, provider, event_id, process_name, message,
                           ROW_NUMBER() OVER (
                               PARTITION BY category, provider, event_id, process_name
                               ORDER BY occurred_utc DESC
                           ) AS rn,
                           COUNT(*) OVER (
                               PARTITION BY category, provider, event_id, process_name
                           ) AS event_count,
                           MAX(CASE WHEN severity='FAIL' THEN 2 WHEN severity='WARN' THEN 1 ELSE 0 END) OVER (
                               PARTITION BY category, provider, event_id, process_name
                           ) AS severity_rank
                    FROM crash_events
                    WHERE occurred_utc >= $since
                )
                SELECT occurred_utc, category,
                       CASE severity_rank WHEN 2 THEN 'FAIL' WHEN 1 THEN 'WARN' ELSE 'PASS' END,
                       provider, event_id, process_name, message, event_count
                FROM ranked
                WHERE rn=1
                ORDER BY occurred_utc DESC
                LIMIT $max;
                """;
            command.Parameters.AddWithValue("$since", DateTimeOffset.UtcNow.AddDays(-Math.Max(1, days)).ToString("O"));
            command.Parameters.AddWithValue("$max", Math.Clamp(maxEvents, 1, 500));
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                var rawTime = reader.GetString(0);
                var time = ParseDateTimeOffset(rawTime);
                result.Add(new CrashEventItem
                {
                    Time = time?.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss") ?? rawTime,
                    Category = reader.GetString(1),
                    Severity = reader.GetString(2),
                    Provider = reader.GetString(3),
                    Id = reader.GetInt32(4),
                    Process = reader.GetString(5),
                    Message = reader.GetString(6),
                    Count = checked((int)reader.GetInt64(7))
                });
            }
            return result;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task SaveDumpAnalysisAsync(DumpAnalysisResult result, CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO dump_analyses(
                    analysis_id, file_name, file_path, file_size_bytes, exception_code, exception_name,
                    exception_address, faulting_module, category, confidence, core_reason, evidence, analyzed_utc, report_path)
                VALUES($id, $name, $path, $size, $code, $exception, $address, $module, $category, $confidence, $reason, $evidence, $time, $report)
                ON CONFLICT(analysis_id) DO UPDATE SET
                    file_name=excluded.file_name, file_path=excluded.file_path, file_size_bytes=excluded.file_size_bytes,
                    exception_code=excluded.exception_code, exception_name=excluded.exception_name,
                    exception_address=excluded.exception_address, faulting_module=excluded.faulting_module,
                    category=excluded.category, confidence=excluded.confidence, core_reason=excluded.core_reason,
                    evidence=excluded.evidence, analyzed_utc=excluded.analyzed_utc, report_path=excluded.report_path;
                """;
            command.Parameters.AddWithValue("$id", result.Id);
            command.Parameters.AddWithValue("$name", result.FileName);
            command.Parameters.AddWithValue("$path", result.FilePath);
            command.Parameters.AddWithValue("$size", result.FileSizeBytes);
            command.Parameters.AddWithValue("$code", result.ExceptionCode);
            command.Parameters.AddWithValue("$exception", result.ExceptionName);
            command.Parameters.AddWithValue("$address", result.ExceptionAddress);
            command.Parameters.AddWithValue("$module", result.FaultingModule);
            command.Parameters.AddWithValue("$category", result.Category);
            command.Parameters.AddWithValue("$confidence", result.Confidence);
            command.Parameters.AddWithValue("$reason", result.CoreReason);
            command.Parameters.AddWithValue("$evidence", result.Evidence);
            command.Parameters.AddWithValue("$time", result.AnalyzedUtc.ToUniversalTime().ToString("O"));
            command.Parameters.AddWithValue("$report", result.ReportPath);
            command.ExecuteNonQuery();
            return 0;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<DumpAnalysisResult>> ReadDumpAnalysesAsync(int maxItems = 30, CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        return await ExecuteAsync<IReadOnlyList<DumpAnalysisResult>>(connection =>
        {
            var rows = new List<DumpAnalysisResult>();
            using var command = connection.CreateCommand();
            command.CommandText = """
                SELECT analysis_id, file_name, file_path, file_size_bytes, exception_code, exception_name,
                       exception_address, faulting_module, category, confidence, core_reason, evidence, analyzed_utc, report_path
                FROM dump_analyses
                ORDER BY analyzed_utc DESC
                LIMIT $max;
                """;
            command.Parameters.AddWithValue("$max", Math.Clamp(maxItems, 1, 200));
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                rows.Add(new DumpAnalysisResult
                {
                    Id = reader.GetString(0),
                    FileName = reader.GetString(1),
                    FilePath = reader.GetString(2),
                    FileSizeBytes = reader.GetInt64(3),
                    ExceptionCode = reader.GetString(4),
                    ExceptionName = reader.GetString(5),
                    ExceptionAddress = reader.GetString(6),
                    FaultingModule = reader.GetString(7),
                    Category = reader.GetString(8),
                    Confidence = reader.GetString(9),
                    CoreReason = reader.GetString(10),
                    Evidence = reader.GetString(11),
                    AnalyzedUtc = ParseDateTimeOffset(reader.GetString(12)) ?? DateTimeOffset.UtcNow,
                    ReportPath = reader.GetString(13)
                });
            }
            return rows;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task UpsertComponentStatesAsync(IEnumerable<ComponentItem> items, CancellationToken cancellationToken = default)
    {
        var rows = items.ToArray();
        if (rows.Length == 0) return;
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection =>
        {
            using var transaction = connection.BeginTransaction();
            foreach (var item in rows)
            {
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText = """
                    INSERT INTO component_state(component_key, name, installed, target, runtime, error_code, status, detail, component_group, observed_utc)
                    VALUES($key, $name, $installed, $target, $runtime, $error, $status, $detail, $group, $observed)
                    ON CONFLICT(component_key) DO UPDATE SET
                        name=excluded.name, installed=excluded.installed, target=excluded.target,
                        runtime=excluded.runtime, error_code=excluded.error_code, status=excluded.status,
                        detail=excluded.detail, component_group=excluded.component_group, observed_utc=excluded.observed_utc;
                    """;
                command.Parameters.AddWithValue("$key", item.Key);
                command.Parameters.AddWithValue("$name", item.Name);
                command.Parameters.AddWithValue("$installed", item.Installed);
                command.Parameters.AddWithValue("$target", item.Target);
                command.Parameters.AddWithValue("$runtime", item.Runtime);
                command.Parameters.AddWithValue("$error", item.ErrorCode);
                command.Parameters.AddWithValue("$status", item.Status);
                command.Parameters.AddWithValue("$detail", item.Detail);
                command.Parameters.AddWithValue("$group", item.Group);
                command.Parameters.AddWithValue("$observed", DateTimeOffset.UtcNow.ToString("O"));
                command.ExecuteNonQuery();
            }
            transaction.Commit();
            return 0;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<ComponentItem>> ReadComponentStatesAsync(string group = "", CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        return await ExecuteAsync<IReadOnlyList<ComponentItem>>(connection =>
        {
            var rows = new List<ComponentItem>();
            using var command = connection.CreateCommand();
            command.CommandText = string.IsNullOrWhiteSpace(group)
                ? "SELECT component_key, name, installed, target, runtime, error_code, status, detail, component_group FROM component_state ORDER BY name;"
                : "SELECT component_key, name, installed, target, runtime, error_code, status, detail, component_group FROM component_state WHERE component_group=$group ORDER BY name;";
            if (!string.IsNullOrWhiteSpace(group)) command.Parameters.AddWithValue("$group", group);
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                rows.Add(new ComponentItem
                {
                    Key = reader.GetString(0), Name = reader.GetString(1), Installed = reader.GetString(2), Target = reader.GetString(3),
                    Runtime = reader.GetString(4), ErrorCode = reader.GetString(5), Status = reader.GetString(6), Detail = reader.GetString(7), Group = reader.GetString(8)
                });
            }
            return rows;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task UpsertTransactionsAsync(IEnumerable<TransactionItem> items, CancellationToken cancellationToken = default)
    {
        var rows = items.ToArray();
        if (rows.Length == 0) return;
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection =>
        {
            using var transaction = connection.BeginTransaction();
            foreach (var item in rows)
            {
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText = """
                    INSERT INTO repair_transactions(transaction_id, type, component_group, label, state, started_at, updated_at, last_detail, cached_utc)
                    VALUES($id, $type, $group, $label, $state, $started, $updated, $detail, $cached)
                    ON CONFLICT(transaction_id) DO UPDATE SET
                        type=excluded.type, component_group=excluded.component_group, label=excluded.label,
                        state=excluded.state, started_at=excluded.started_at, updated_at=excluded.updated_at,
                        last_detail=excluded.last_detail, cached_utc=excluded.cached_utc;
                    """;
                command.Parameters.AddWithValue("$id", item.TransactionId);
                command.Parameters.AddWithValue("$type", item.Type);
                command.Parameters.AddWithValue("$group", item.Group);
                command.Parameters.AddWithValue("$label", item.Label);
                command.Parameters.AddWithValue("$state", item.State);
                command.Parameters.AddWithValue("$started", item.StartedAt);
                command.Parameters.AddWithValue("$updated", item.UpdatedAt);
                command.Parameters.AddWithValue("$detail", item.LastDetail);
                command.Parameters.AddWithValue("$cached", DateTimeOffset.UtcNow.ToString("O"));
                command.ExecuteNonQuery();
            }
            transaction.Commit();
            return 0;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<TransactionItem>> ReadTransactionsAsync(int maxTransactions = 50, CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        return await ExecuteAsync<IReadOnlyList<TransactionItem>>(connection =>
        {
            var rows = new List<TransactionItem>();
            using var command = connection.CreateCommand();
            command.CommandText = """
                SELECT transaction_id, type, component_group, label, state, started_at, updated_at, last_detail
                FROM repair_transactions
                ORDER BY updated_at DESC
                LIMIT $max;
                """;
            command.Parameters.AddWithValue("$max", Math.Clamp(maxTransactions, 1, 200));
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                rows.Add(new TransactionItem
                {
                    TransactionId = reader.GetString(0),
                    Type = reader.GetString(1),
                    Group = reader.GetString(2),
                    Label = reader.GetString(3),
                    State = reader.GetString(4),
                    StartedAt = reader.GetString(5),
                    UpdatedAt = reader.GetString(6),
                    LastDetail = reader.GetString(7)
                });
            }
            return rows;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task UpsertIncidentsAsync(IEnumerable<JsonElement> incidents, CancellationToken cancellationToken = default)
    {
        var rows = incidents.Select(x => x.Clone()).ToArray();
        if (rows.Length == 0) return;
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection =>
        {
            using var transaction = connection.BeginTransaction();
            foreach (var item in rows)
            {
                var raw = item.GetRawText();
                var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(raw))).ToLowerInvariant();
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText = """
                    INSERT INTO incidents(incident_key, code, component, confidence, score, evidence, payload_json, observed_utc)
                    VALUES($key, $code, $component, $confidence, $score, $evidence, $payload, $observed)
                    ON CONFLICT(incident_key) DO UPDATE SET observed_utc=excluded.observed_utc, payload_json=excluded.payload_json;
                    """;
                command.Parameters.AddWithValue("$key", key);
                command.Parameters.AddWithValue("$code", item.String("Code"));
                command.Parameters.AddWithValue("$component", item.String("Component"));
                command.Parameters.AddWithValue("$confidence", item.String("Confidence"));
                command.Parameters.AddWithValue("$score", item.String("Score"));
                command.Parameters.AddWithValue("$evidence", item.String("Evidence"));
                command.Parameters.AddWithValue("$payload", raw);
                command.Parameters.AddWithValue("$observed", DateTimeOffset.UtcNow.ToString("O"));
                command.ExecuteNonQuery();
            }
            transaction.Commit();
            return 0;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task RecordWorkflowAsync(RepairWorkflowSnapshot snapshot, CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection =>
        {
            using var transaction = connection.BeginTransaction();
            using (var command = connection.CreateCommand())
            {
                command.Transaction = transaction;
                command.CommandText = """
                    INSERT INTO workflow_state(id, phase, type, component_group, eligible, state, detail, updated_utc)
                    VALUES(1, $phase, $type, $group, $eligible, $state, $detail, $updated)
                    ON CONFLICT(id) DO UPDATE SET phase=excluded.phase, type=excluded.type,
                        component_group=excluded.component_group, eligible=excluded.eligible,
                        state=excluded.state, detail=excluded.detail, updated_utc=excluded.updated_utc;
                    """;
                AddWorkflowParameters(command, snapshot);
                command.ExecuteNonQuery();
            }
            using (var history = connection.CreateCommand())
            {
                history.Transaction = transaction;
                history.CommandText = """
                    INSERT INTO workflow_history(phase, type, component_group, eligible, state, detail, observed_utc)
                    VALUES($phase, $type, $group, $eligible, $state, $detail, $updated);
                    """;
                AddWorkflowParameters(history, snapshot);
                history.ExecuteNonQuery();
            }
            transaction.Commit();
            return 0;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<RepairWorkflowSnapshot?> GetWorkflowAsync(CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        return await ExecuteAsync<RepairWorkflowSnapshot?>(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT phase, type, component_group, eligible, state, detail, updated_utc FROM workflow_state WHERE id=1 LIMIT 1;";
            using var reader = command.ExecuteReader();
            if (!reader.Read()) return null;
            var rawPhase = reader.GetInt32(0);
            var phase = Enum.IsDefined(typeof(RepairWorkflowPhase), rawPhase)
                ? (RepairWorkflowPhase)rawPhase
                : RepairWorkflowPhase.Idle;
            return new RepairWorkflowSnapshot(
                phase,
                reader.GetString(1),
                reader.GetString(2),
                reader.GetInt32(3) != 0,
                reader.GetString(4),
                reader.GetString(5),
                ParseDateTimeOffset(reader.GetString(6)) ?? DateTimeOffset.UtcNow);
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task<StateStoreStatus> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        return await ExecuteAsync(connection =>
        {
            static long Count(SqliteConnection c, string table)
            {
                using var command = c.CreateCommand();
                command.CommandText = $"SELECT COUNT(*) FROM {table};";
                return Convert.ToInt64(command.ExecuteScalar() ?? 0, CultureInfo.InvariantCulture);
            }

            using var journal = connection.CreateCommand();
            journal.CommandText = "PRAGMA journal_mode;";
            var mode = journal.ExecuteScalar()?.ToString() ?? "unknown";
            var bytes = FileLength(DatabasePath) + FileLength(DatabasePath + "-wal") + FileLength(DatabasePath + "-shm");

            DateTimeOffset? lastSync = null;
            var lastError = "";
            using (var sync = connection.CreateCommand())
            {
                sync.CommandText = "SELECT last_success_utc, last_error FROM event_sync_state WHERE stream='crash-eventlog-v1' LIMIT 1;";
                using var reader = sync.ExecuteReader();
                if (reader.Read())
                {
                    lastSync = ParseDateTimeOffset(reader.GetString(0));
                    lastError = reader.GetString(1);
                }
            }

            var workflowState = "IDLE";
            using (var workflow = connection.CreateCommand())
            {
                workflow.CommandText = "SELECT state FROM workflow_state WHERE id=1 LIMIT 1;";
                workflowState = workflow.ExecuteScalar()?.ToString() ?? "IDLE";
            }

            return new StateStoreStatus(
                DatabasePath,
                bytes,
                Count(connection, "crash_events"),
                Count(connection, "component_state"),
                Count(connection, "repair_transactions"),
                Count(connection, "incidents"),
                Count(connection, "dump_analyses"),
                mode,
                SchemaVersion,
                lastSync,
                lastError,
                workflowState);
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task PruneAsync(CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection =>
        {
            var lastPrune = GetMetadataDateTimeOffset(connection, "last_prune_utc");
            if (lastPrune.HasValue && DateTimeOffset.UtcNow - lastPrune.Value < PruneInterval) return 0;

            using var command = connection.CreateCommand();
            command.CommandText = """
                DELETE FROM crash_events WHERE occurred_utc < $crashCutoff;
                DELETE FROM incidents WHERE observed_utc < $incidentCutoff;
                DELETE FROM observations WHERE observed_utc < $observationCutoff;
                DELETE FROM workflow_history WHERE observed_utc < $workflowCutoff;
                DELETE FROM dump_analyses WHERE analyzed_utc < $dumpCutoff;
                PRAGMA wal_checkpoint(PASSIVE);
                """;
            command.Parameters.AddWithValue("$crashCutoff", DateTimeOffset.UtcNow.AddDays(-30).ToString("O"));
            command.Parameters.AddWithValue("$incidentCutoff", DateTimeOffset.UtcNow.AddDays(-90).ToString("O"));
            command.Parameters.AddWithValue("$observationCutoff", DateTimeOffset.UtcNow.AddDays(-90).ToString("O"));
            command.Parameters.AddWithValue("$workflowCutoff", DateTimeOffset.UtcNow.AddDays(-90).ToString("O"));
            command.Parameters.AddWithValue("$dumpCutoff", DateTimeOffset.UtcNow.AddDays(-180).ToString("O"));
            command.ExecuteNonQuery();
            SetMetadata(connection, "last_prune_utc", DateTimeOffset.UtcNow.ToString("O"));
            return 0;
        }, cancellationToken).ConfigureAwait(false);
    }

    public async Task ClearVolatileCacheAsync(CancellationToken cancellationToken = default)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = """
                DELETE FROM crash_events;
                DELETE FROM event_cursors;
                DELETE FROM event_sync_state;
                DELETE FROM component_state;
                PRAGMA wal_checkpoint(TRUNCATE);
                """;
            command.ExecuteNonQuery();
            return 0;
        }, cancellationToken).ConfigureAwait(false);
    }

    private async Task<T> ExecuteAsync<T>(Func<SqliteConnection, T> operation, CancellationToken cancellationToken)
    {
        await _dbGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            return await Task.Run(() =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                Directory.CreateDirectory(Path.GetDirectoryName(DatabasePath)!);
                using var connection = new SqliteConnection(_connectionString);
                connection.Open();
                using var pragma = connection.CreateCommand();
                pragma.CommandText = "PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON; PRAGMA wal_autocheckpoint=256; PRAGMA journal_size_limit=4194304;";
                pragma.ExecuteNonQuery();
                return operation(connection);
            }, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _dbGate.Release();
        }
    }

    private static void AddWorkflowParameters(SqliteCommand command, RepairWorkflowSnapshot snapshot)
    {
        command.Parameters.AddWithValue("$phase", (int)snapshot.Phase);
        command.Parameters.AddWithValue("$type", snapshot.Type);
        command.Parameters.AddWithValue("$group", snapshot.Group);
        command.Parameters.AddWithValue("$eligible", snapshot.Eligible ? 1 : 0);
        command.Parameters.AddWithValue("$state", snapshot.State);
        command.Parameters.AddWithValue("$detail", snapshot.Detail);
        command.Parameters.AddWithValue("$updated", snapshot.UpdatedUtc.ToUniversalTime().ToString("O"));
    }

    private static void SetMetadata(SqliteConnection connection, string key, string value)
    {
        using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO metadata(key, value, updated_utc)
            VALUES($key, $value, $updated)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_utc=excluded.updated_utc;
            """;
        command.Parameters.AddWithValue("$key", key);
        command.Parameters.AddWithValue("$value", value);
        command.Parameters.AddWithValue("$updated", DateTimeOffset.UtcNow.ToString("O"));
        command.ExecuteNonQuery();
    }

    private static DateTimeOffset? GetMetadataDateTimeOffset(SqliteConnection connection, string key)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT value FROM metadata WHERE key=$key LIMIT 1;";
        command.Parameters.AddWithValue("$key", key);
        return ParseDateTimeOffset(command.ExecuteScalar()?.ToString());
    }

    private static DateTimeOffset? ParseDateTimeOffset(string? value)
        => DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed)
            ? parsed
            : null;

    private static long FileLength(string path)
    {
        try { return File.Exists(path) ? new FileInfo(path).Length : 0; }
        catch { return 0; }
    }

    public void Dispose() => _dbGate.Dispose();
}
