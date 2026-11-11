# Agent Loop Audit — Phase 0

Status: audit and instrumentation only. The prompt, tool schemas, retry policy,
round limit and model request behavior were not changed in this phase.

Baseline before any Phase 0 edit:

```text
Flutter 3.24.5 / Dart 3.5.4
flutter test --reporter expanded
37 tests passed
```

The app is a Flutter Android application. There is no server component in this
repository.

## 1. Where the loop lives

`lib/core/agent.dart` — `Agent.run`.

One round is:

1. `Agent.run` builds the system prompt (`_systemPrompt`) and the conversation
   (`turns`).
2. It calls `AiClient.stream` with the current provider, model, system prompt,
   turns and tool specs.
3. The reply may contain text, reasoning and zero or more tool calls.
4. If there are no calls, the loop either finishes, asks for one corrective
   completion, or asks the model to continue after an output-limit cut.
5. If there are calls, the assistant turn is appended, then each call is
   executed in list order with `await _execute(call)`.
6. Each tool result is appended as an `AiTurn.tool`.
7. The next loop iteration sends the entire accumulated `turns` list again.

The loop caps at `maxRounds = 40` (changed in the previous polish pass from 24).
The output budget is `kDefaultMaxOutputTokens = 8192` in `lib/core/ai.dart`.

## 2. Provider abstraction and HTTP requests

`lib/core/ai.dart` — `AiClient`.

Every model HTTP request goes through one of these methods:

- `stream` — the normal agent path; sends a streaming SSE request.
- `complete` — non-streaming completion support.
- `listModels` — provider model discovery from the provider form.

The concrete HTTP calls are `_client.send`, `_client.post`, and `_client.get`
inside `AiClient`. OpenAI-compatible and Anthropic payloads are built by
`_openAiPayload` / `_anthropicPayload`; SSE parsing is `_consumeOpenAi` /
`_consumeAnthropic`.

Provider configuration is in `lib/models.dart` (`ProviderConfig`). The app
stores keys in `SharedPreferences` through `KVStore`; keys are never written to
the round log.

## 3. Tool calls: parsing, execution and ordering

- Streaming OpenAI tool fragments are assembled in `_consumeOpenAi` using a
  `_CallBuilder` per tool index.
- Anthropic `tool_use` blocks are assembled in `_consumeAnthropic`.
- `AiReply.calls` is the parsed list. Arguments are JSON-decoded by
  `_arguments`.
- `Agent._execute` dispatches `list_files`, `read_file`, `write_file`,
  `edit_file`, `install_skill`, `download_file`, `run_command`,
  `commit_and_push`, and `pull_latest`.
- Calls from one response are executed **sequentially, one at a time, in the
  order returned by the provider**. No two tools run concurrently. A later call
  in the same response sees the effects of an earlier call.
- The tool result is appended to the model conversation immediately. The full
  result is sent back to the model in the next request.

## 4. Tool result sizing and truncation today

- `read_file`: default 350 lines, hard cap 1,200 lines, and approximately
  15,000 characters per call. It reports `Next offset` and repeats of the same
  range are replaced with a warning.
- `run_command`: output is capped at 12,000 characters with
  `… output truncated`.
- `list_files`: unbounded list.
- System prompt project tree: first 120 entries.
- File contents in tool results are not otherwise compressed. There is no
  summarization of old tool results; every request re-sends the whole
  conversation.

## 5. Approvals

- File reads/writes, shell commands, downloads and skill installs do **not**
  prompt for approval.
- `commit_and_push` and `pull_latest` are gated by `onCommitAndPush` /
  `onPullLatest` in `AppState`. The agent tab supplies `confirmPrompt` and the
  action asks for confirmation before any Git request.
- Provider/key switching may prompt through `onProviderLimit` /
  `listLimitPrompt` when automatic switching is disabled.

## 6. Retry, errors and rate limits

- `AiProviderException.isLimit` is true for HTTP 402/429 and common quota or
  rate-limit messages (`lib/models.dart`).
- `Agent.run` catches a limit error inside the request loop and calls
  `onProviderLimit`; it may switch up to three times to another key/provider and
  retry the **same** model request.
- There is no exponential backoff, no `Retry-After` parsing, and no timed
  retry of a transient network error. A non-limit failure is rethrown to
  `AppState.send`, which writes an error entry.
- Output-limit replies get up to two “continue without reasoning” nudges.
- A change request with no mutation gets up to two corrective nudges.
- Repeating the exact same tool call four times stops the loop.
- A request that exceeds 40 tool rounds stops with an error.

## 7. Existing logging, telemetry and storage

- No general application logger exists. Only one `debugPrint`/`print` call site
  is present (in generated scaffold text, not runtime logging).
- `lib/core/usage.dart` stores `UsageEvent` records (provider, key index, model,
  prompt/completion tokens) in `SharedPreferences` under `praxis.usage`. This is
  accounting, not a round trace.
- `lib/core/store.dart` is the key-value seam (`SharedPreferences` in the app,
  memory in tests).
- Project files and chat transcripts are local. There is no telemetry or
  remote log upload.
- Phase 0 adds `lib/core/round_log.dart`, a JSONL store under the app support
  directory (`praxis/logs/agent_rounds.jsonl`). It records only task id,
  round index, timestamp, provider id/name, model, provider-reported tokens
  (null when absent), tool names/count, round type, repeated-call flag and final
  outcome. It never records prompts, tool arguments, file contents, API keys or
  tokens.

## 8. Summary view

Settings → **Logs** (bottom of the Settings list) opens `lib/screens/logs_screen.dart`.

It shows:

- aggregate task and request counts, rounds by type, repeated calls, average
  rounds before the first edit, reported input/output tokens and outcomes;
- per task: request count, type counts, repeated calls, first-edit position,
  outcome and one compact row per request;
- the task id, so a task can be matched to a project/session.

No prompt or file content is displayed or persisted by this view.

## 9. Tests and baseline

Run from the repository root:

```bash
export PATH=/tmp/flutter/bin:$PATH
flutter pub get
flutter test --reporter expanded
```

Baseline result before the Phase 0 changes: **37 tests passed**.

Final result after the Phase 0 changes: **43 tests passed**, and
`flutter analyze` reported no issues. The added tests cover the actual
`Agent.run` request path, not only the log model.

- one log entry per model request, including null token fields when the
  provider does not report usage;
- round classification (`explore`, `edit`, `other`);
- repeated identical calls across a task;
- task outcomes (`completed`, `quota_error`);
- JSONL persistence and clearing;
- the Settings log view renders the aggregate and a task row in a widget smoke
  test.

## 10. Problems found in the loop

1. **Tool calls are sequential.** Multiple calls in one response are awaited one
   by one. This is safe for dependent edits but adds latency for independent
   reads/searches.
2. **Full history is re-sent every round.** The entire `turns` list, including
   every prior tool result, is sent on each request. Long tasks therefore grow
   input tokens and quota use quickly. There is no old-result compaction.
3. **No 429 backoff.** A limit switches key/provider immediately, with no
   `Retry-After` handling and no delay. If no alternate key exists, the error is
   surfaced and the task stops.
4. **No transient-network retry.** A timeout or client exception is surfaced
   after the request timeout; only provider-limit errors get a failover.
5. **Approvals are narrow.** Shell commands and file mutations are not generally
   approval-gated; only Git actions are. This is intentional for the current
   product, but it means “approval” is not a general safety boundary.
6. **No request-level trace existed.** Token usage recorded totals only; it was
   impossible to see rounds, tool names, repeated calls or where a task died.
7. **Round type is heuristic.** `classifyRound` uses tool names and shell
   command patterns; it is intentionally simple and does not inspect arguments
   beyond the command string, and it must not store that string.
8. **The shell has no package manager.** Praxis uses Android `/system/bin/sh`;
   Node, npm, Python and Git are not bundled. A future “full shell” feature
   needs a bundled native runtime/rootfs or a supported Termux bridge; adding a
   `pkg` alias alone would only pretend to install packages.
