// Perch bridge for opencode.
//
// Installed by `./scripts/install-hooks.sh --opencode` into
// ~/.config/opencode/plugins/perch.js, next to a package.json marking `type: module` —
// the convention opencode's plugin loader expects for local plugins.
//
// Mirrors what Claude Code's hooks give perch-hook, built from opencode's own event
// stream, and forwards each mapped event to `perch-hook <Event> --source opencode` on
// stdin — same binary, same wire format (PerchKit/Wire.swift's ClaudeHookPayload), so the
// app doesn't need to know which CLI is talking to it.
//
// Ordinary lifecycle events are fire-and-forget. Permission and question events wait for
// Perch in a detached promise, then reply through opencode's local HTTP API. Every failure
// path leaves opencode's own prompt in charge, so a missing Perch never stalls a session.
//
// Event mapping:
//   session.created                        -> SessionStart
//   session.idle                           -> Stop
//   session.deleted                        -> SessionEnd
//   message.part.updated (text, buffered)
//     + message.updated (role: user)       -> UserPromptSubmit, with the buffered text
//   message.part.updated (tool, running)   -> PreToolUse
//   message.part.updated (tool, completed) -> PostToolUse
//   permission.asked / replied             -> PermissionRequest / PostToolUse
//   question.asked / replied / rejected    -> AskUserQuestion / PostToolUse
//
// Checks that need no running opencode:
//   node --check scripts/opencode-plugin/perch.js
//   node scripts/opencode-plugin/perch.js --self-test
//   PERCH_HOOK_BIN=/bin/cat node scripts/opencode-plugin/perch.js --self-test
//
// The self-test runs one fixture event of each kind through the same `mapEvent` the live
// plugin uses, spawns whatever PERCH_HOOK_BIN points at (default /bin/cat, which echoes
// stdin back), and checks the printed JSON has the shape perch-hook expects.

import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

/// Resolves perch-hook the way scripts/install-hooks.sh resolves the app bundle: the
/// shipped locations first, PERCH_HOOK_BIN as an override for tests and unusual installs.
function resolveHookBin() {
  if (process.env.PERCH_HOOK_BIN) return process.env.PERCH_HOOK_BIN;
  const candidates = [
    "/Applications/Perch.app/Contents/Resources/perch-hook",
    join(homedir(), "Applications/Perch.app/Contents/Resources/perch-hook"),
  ];
  return candidates.find(existsSync) ?? candidates[0];
}

/// Caps how many entries a buffering Map is allowed to hold, evicting the oldest one
/// first. `Map` iterates insertion order, so `.keys().next()` is always the oldest.
///
/// Both `pendingUserText` and `toolPartState` wait for a second event (`message.updated`,
/// a terminal tool state) that might never arrive — a message with no reply, a tool call
/// opencode never reports as finished. Without a cap, an hours-long session turns each
/// stray entry into an unbounded, monotonically growing retention of message text.
const MAX_BUFFERED_ENTRIES = 500;

function rememberBounded(map, key, value) {
  if (!map.has(key) && map.size >= MAX_BUFFERED_ENTRIES) {
    map.delete(map.keys().next().value);
  }
  map.set(key, value);
}

function displayToolName(value) {
  const name = typeof value === "string" ? value : "";
  return name ? name[0].toUpperCase() + name.slice(1) : "unknown";
}

/// Maps one opencode event to a Claude-shaped hook payload, or null if this event carries
/// nothing perch-hook understands. Kept pure and exported so the live plugin and
/// --self-test run the exact same mapping.
export function mapEvent(event, { directory, sessionCwd, pendingUserText, toolPartState }) {
  const type = event?.type;
  const properties = event?.properties || {};
  const cwdFor = (sessionId) => sessionCwd.get(sessionId) || directory;
  const base = (sessionId, extra) => ({
    session_id: sessionId,
    cwd: cwdFor(sessionId),
    ...extra,
  });

  switch (type) {
    case "session.created": {
      if (!properties.info?.id) return null;
      sessionCwd.set(properties.info.id, properties.info.directory || directory);
      return {
        hookEvent: "SessionStart",
        payload: base(properties.info.id, { hook_event_name: "SessionStart" }),
      };
    }

    case "session.status":
      if (properties.sessionID && properties.status?.type === "idle") {
        return { hookEvent: "Stop", payload: base(properties.sessionID, { hook_event_name: "Stop" }) };
      }
      return null;

    case "session.idle": {
      if (!properties.sessionID) return null;
      return { hookEvent: "Stop", payload: base(properties.sessionID, { hook_event_name: "Stop" }) };
    }

    case "session.deleted": {
      if (!properties.info?.id) return null;
      const mapped = {
        hookEvent: "SessionEnd",
        payload: base(properties.info.id, { hook_event_name: "SessionEnd" }),
      };
      sessionCwd.delete(properties.info.id);
      return mapped;
    }

    case "message.part.updated": {
      const part = properties.part;
      if (!part) return null;

      if (part.type === "text" && part.messageID) {
        // opencode only reveals the message's role on `message.updated`, not here — hold
        // the text until that arrives.
        rememberBounded(pendingUserText, part.messageID, { sessionID: part.sessionID, text: part.text || "" });
        return null;
      }

      if (part.type === "tool" && part.sessionID) {
        const status = part.state?.status;
        const toolName = displayToolName(part.tool);
        // opencode reports a running tool call through several part updates — one per
        // streamed state change, not one per call. Only the first pending/running and the
        // first completed/error are worth a hook, so the transition is tracked per part
        // rather than trusting each update to be a new event.
        const key = part.id || `${part.sessionID}:${part.messageID}:${toolName}`;
        const lastPhase = toolPartState.get(key);

        if ((status === "pending" || status === "running") && lastPhase !== "pre") {
          rememberBounded(toolPartState, key, "pre");
          return {
            hookEvent: "PreToolUse",
            payload: base(part.sessionID, {
              hook_event_name: "PreToolUse",
              tool_name: toolName,
              tool_input: part.state?.input || {},
            }),
          };
        }
        if ((status === "completed" || status === "error") && lastPhase !== "post") {
          // Recorded, not deleted: opencode can send more than one update after a part
          // reaches its terminal state (output/metadata filling in), and a deleted key
          // would make every one of those look like a fresh transition again. The entry
          // ages out through the same bound as everything else in this Map.
          rememberBounded(toolPartState, key, "post");
          return {
            hookEvent: "PostToolUse",
            payload: base(part.sessionID, { hook_event_name: "PostToolUse", tool_name: toolName }),
          };
        }
      }
      return null;
    }

    case "message.updated": {
      // The buffer is released for every message, not only user ones — an assistant
      // message that never gets read here would otherwise sit in `pendingUserText` for
      // the rest of the process's life.
      const messageId = properties.info?.id;
      if (!messageId) return null;
      const pending = pendingUserText.get(messageId);
      pendingUserText.delete(messageId);
      if (properties.info?.role !== "user" || !pending?.text) return null;
      const sessionId = properties.info.sessionID || pending.sessionID;
      return {
        hookEvent: "UserPromptSubmit",
        payload: base(sessionId, { hook_event_name: "UserPromptSubmit", prompt: pending.text }),
      };
    }

    case "permission.asked": {
      if (!properties.sessionID) return null;
      const patterns = properties.patterns || [];
      const toolName = displayToolName(properties.permission);
      const toolInput = { patterns, metadata: properties.metadata };
      if (properties.permission === "bash" && patterns.length > 0) {
        toolInput.command = patterns.join(" && ");
      }
      if ((properties.permission === "edit" || properties.permission === "write")
        && patterns.length > 0) {
        toolInput.file_path = patterns[0];
      }
      return {
        hookEvent: "PermissionRequest",
        payload: base(properties.sessionID, {
          hook_event_name: "PermissionRequest",
          tool_name: toolName,
          tool_input: toolInput,
        }),
        replyRequest: properties.id ? { kind: "permission", id: properties.id } : null,
      };
    }

    case "permission.replied": {
      if (!properties.sessionID) return null;
      return {
        hookEvent: "PostToolUse",
        payload: base(properties.sessionID, {
          hook_event_name: "PostToolUse",
          tool_name: "Permission",
        }),
      };
    }

    case "question.asked": {
      if (!properties.id || !properties.sessionID) return null;
      const questions = (properties.questions || []).map((question) => ({
        question: question.question || "",
        header: question.header || "",
        options: (question.options || []).map((option) => ({
          label: option.label || "",
          description: option.description || "",
        })),
        multiSelect: question.multiple || false,
      }));
      return {
        hookEvent: "PermissionRequest",
        payload: base(properties.sessionID, {
          hook_event_name: "PermissionRequest",
          tool_name: "AskUserQuestion",
          tool_use_id: properties.id,
          tool_input: { questions },
        }),
        replyRequest: { kind: "question", id: properties.id },
      };
    }

    case "question.replied":
    case "question.rejected": {
      if (!properties.sessionID) return null;
      return {
        hookEvent: "PostToolUse",
        payload: base(properties.sessionID, {
          hook_event_name: "PostToolUse",
          tool_name: "AskUserQuestion",
          tool_use_id: properties.requestID,
        }),
      };
    }

    default:
      return null;
  }
}

/// Fire-and-forget: never awaited, and every failure path is swallowed. A missing or
/// wedged Perch must never break an opencode session.
function sendHook(hookEvent, payload) {
  try {
    const child = spawn(resolveHookBin(), [hookEvent, "--source", "opencode"], {
      stdio: ["pipe", "ignore", "ignore"],
    });
    child.on("error", () => {}); // e.g. binary not found — look exactly like no hook at all
    // `child.on("error")` above does not cover this: if perch-hook exits before draining
    // stdin (killed, replaced mid-update, or just a payload bigger than the pipe buffer),
    // the stream itself emits EPIPE. Unhandled, that throws asynchronously and kills the
    // host process — exactly what this file promises never to do.
    child.stdin.on("error", () => {});
    child.stdin.write(JSON.stringify(payload));
    child.stdin.end();
  } catch {
    // same contract, for the synchronous half of spawn
  }
}

function sendHookAndWait(hookEvent, payload, timeoutMs = 300_000) {
  return new Promise((resolve) => {
    let settled = false;
    let output = "";
    const settle = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(value);
    };

    let child;
    try {
      child = spawn(resolveHookBin(), [hookEvent, "--source", "opencode"], {
        stdio: ["pipe", "pipe", "ignore"],
      });
    } catch {
      resolve(null);
      return;
    }

    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      settle(null);
    }, timeoutMs);
    child.on("error", () => settle(null));
    child.stdout.on("data", (chunk) => {
      if (output.length < 1_000_000) output += chunk.toString();
    });
    child.on("close", (code) => {
      if (code !== 0 || !output.trim()) {
        settle(null);
        return;
      }
      try {
        settle(JSON.parse(output));
      } catch {
        settle(null);
      }
    });
    child.stdin.on("error", () => settle(null));
    child.stdin.end(JSON.stringify(payload));
  });
}

export function openCodeQuestionAnswers(questions, updatedInput) {
  const answers = updatedInput?.answers;
  if (!answers || typeof answers !== "object") return null;

  const result = questions.map((question) => {
    const value = answers[question.id] ?? answers[question.question] ?? answers[question.header];
    if (Array.isArray(value)) return value.map(String).filter(Boolean);
    if (typeof value !== "string" || !value) return [];
    return question.multiSelect ? value.split(", ").filter(Boolean) : [value];
  });
  return result.every((answer) => answer.length > 0) ? result : null;
}

export default async ({ client, serverUrl, directory }) => {
  const sessionCwd = new Map();
  const pendingUserText = new Map();
  const toolPartState = new Map();
  const serverOrigin = typeof serverUrl === "string"
    ? new URL(serverUrl).origin
    : serverUrl?.origin || "http://127.0.0.1:4096";

  const headers = (cwd) => {
    const result = { "Content-Type": "application/json" };
    const password = process.env.OPENCODE_SERVER_PASSWORD;
    if (password) {
      const username = process.env.OPENCODE_SERVER_USERNAME || "opencode";
      result.Authorization = `Basic ${Buffer.from(`${username}:${password}`).toString("base64")}`;
    }
    if (cwd || directory) result["x-opencode-directory"] = encodeURIComponent(cwd || directory);
    return result;
  };

  const postReply = async (path, body, cwd) => {
    try {
      const response = await fetch(`${serverOrigin}${path}`, {
        method: "POST", headers: headers(cwd), body: JSON.stringify(body),
      });
      if (response.ok) return true;
    } catch {}

    try {
      const rawClient = client?._client;
      if (!rawClient?.post) return false;
      await rawClient.post({ url: path, headers: headers(cwd), body });
      return true;
    } catch {
      return false;
    }
  };

  const dispatch = (mapped) => {
    if (!mapped?.replyRequest) {
      sendHook(mapped.hookEvent, mapped.payload);
      return;
    }

    sendHookAndWait(mapped.hookEvent, mapped.payload).then(async (response) => {
      if (!response) return;
      const requestId = encodeURIComponent(mapped.replyRequest.id);
      const cwd = mapped.payload.cwd;

      if (mapped.replyRequest.kind === "question") {
        const answers = openCodeQuestionAnswers(
          mapped.payload.tool_input?.questions || [],
          response?.hookSpecificOutput?.decision?.updatedInput);
        if (answers) await postReply(`/question/${requestId}/reply`, { answers }, cwd);
        return;
      }

      const decision = response?.hookSpecificOutput?.decision;
      if (!decision?.behavior) return;
      const remembers = Array.isArray(decision.updatedPermissions)
        && decision.updatedPermissions.length > 0;
      const reply = decision.behavior === "allow" ? (remembers ? "always" : "once") : "reject";
      await postReply(
        `/permission/${requestId}/reply`, { reply, message: decision.message }, cwd);
    });
  };

  return {
    event: async ({ event }) => {
      let mapped;
      try {
        mapped = mapEvent(event, { directory, sessionCwd, pendingUserText, toolPartState });
      } catch {
        return; // an event shape we don't understand must never break the session
      }
      if (mapped) dispatch(mapped);
    },
  };
};

// --- self-test -----------------------------------------------------------------------

function runSelfTest() {
  const directory = "/tmp/perch-opencode-self-test";
  const ctx = { directory, sessionCwd: new Map(), pendingUserText: new Map(), toolPartState: new Map() };
  const hookBin = process.env.PERCH_HOOK_BIN || "/bin/cat";

  const fixtures = [
    { type: "session.created", properties: { info: { id: "ses_1", directory } } },
    {
      type: "message.part.updated",
      properties: { part: { type: "text", messageID: "msg_1", sessionID: "ses_1", text: "hello" } },
      expectNull: true,
    },
    { type: "message.updated", properties: { info: { id: "msg_1", sessionID: "ses_1", role: "user" } } },
    // An assistant reply buffers text the same way a prompt does — it must not stay in
    // pendingUserText after message.updated, or every assistant turn leaks (MUST-FIX 1).
    {
      type: "message.part.updated",
      properties: { part: { type: "text", messageID: "msg_2", sessionID: "ses_1", text: "assistant reply" } },
      expectNull: true,
    },
    {
      type: "message.updated",
      properties: { info: { id: "msg_2", sessionID: "ses_1", role: "assistant" } },
      expectNull: true,
      after: () => assertAbsent("pendingUserText after assistant message.updated", ctx.pendingUserText, "msg_2"),
    },
    {
      type: "message.part.updated",
      properties: {
        part: { id: "part_1", type: "tool", sessionID: "ses_1", tool: "bash", state: { status: "pending", input: { command: "ls" } } },
      },
    },
    // Repeated streamed updates for the same part id while still running must not spawn
    // a second PreToolUse (MUST-FIX 3).
    {
      type: "message.part.updated",
      properties: {
        part: { id: "part_1", type: "tool", sessionID: "ses_1", tool: "bash", state: { status: "running", input: { command: "ls" } } },
      },
      expectNull: true,
    },
    {
      type: "message.part.updated",
      properties: { part: { id: "part_1", type: "tool", sessionID: "ses_1", tool: "bash", state: { status: "completed" } } },
      after: () => assertPhase("toolPartState after 1st completed update", ctx.toolPartState, "part_1", "post"),
    },
    // opencode can send more updates after a part is already terminal (output/metadata
    // filling in). A second completed update for the same part must not spawn a second
    // PostToolUse, and must not erase the recorded phase either.
    {
      type: "message.part.updated",
      properties: { part: { id: "part_1", type: "tool", sessionID: "ses_1", tool: "bash", state: { status: "completed" } } },
      expectNull: true,
      after: () => assertPhase("toolPartState after 2nd completed update", ctx.toolPartState, "part_1", "post"),
    },
    { type: "permission.asked", properties: { sessionID: "ses_1", permission: "bash", patterns: ["ls"] } },
    { type: "permission.replied", properties: { sessionID: "ses_1", requestID: "perm_1" } },
    {
      type: "question.asked",
      properties: {
        id: "question_1", sessionID: "ses_1",
        questions: [{ question: "Which database?", header: "Database", multiple: false,
          options: [{ label: "Postgres", description: "Relational" }] }],
      },
      expectedTool: "AskUserQuestion",
    },
    { type: "question.replied", properties: { sessionID: "ses_1", requestID: "question_1" } },
    { type: "session.status", properties: { sessionID: "ses_1", status: { type: "idle" } } },
    { type: "session.idle", properties: { sessionID: "ses_1" } },
    { type: "session.deleted", properties: { info: { id: "ses_1" } } },
  ];

  let failures = 0;

  function assertPhase(label, map, key, expected) {
    const actual = map.get(key);
    const ok = actual === expected;
    console.log(`${ok ? "PASS" : "FAIL"} ${label}: get(${key})=${actual}`);
    if (!ok) failures++;
  }

  function assertAbsent(label, map, key) {
    const ok = !map.has(key);
    console.log(`${ok ? "PASS" : "FAIL"} ${label}: has(${key})=${map.has(key)}`);
    if (!ok) failures++;
  }

  for (const event of fixtures) {
    const mapped = mapEvent(event, ctx);
    if (event.after) event.after();

    if (!mapped) {
      const label = event.expectNull ? "PASS (expected, buffered/deduped)" : "FAIL (no mapping)";
      console.log(`${label} ${event.type}`);
      if (!event.expectNull) failures++;
      continue;
    }
    if (event.expectNull) {
      console.log(`FAIL ${event.type}: expected no hook (dedup/buffer), got ${mapped.hookEvent}`);
      failures++;
      continue;
    }

    // No argv here on purpose: PERCH_HOOK_BIN=/bin/cat is a stand-in for "whatever
    // reads the payload off stdin", and cat treats extra args as filenames to open
    // rather than as the event/--source pair sendHook() really passes.
    const result = spawnSync(hookBin, [], {
      input: JSON.stringify(mapped.payload),
      encoding: "utf8",
    });
    const printed = (result.stdout || "").trim();
    let ok = false;
    try {
      const parsed = JSON.parse(printed);
      ok = parsed.hook_event_name === mapped.hookEvent
        && parsed.session_id === "ses_1"
        && "cwd" in parsed
        && (!event.expectedTool || parsed.tool_name === event.expectedTool);
    } catch {
      ok = false;
    }
    console.log(`${ok ? "PASS" : "FAIL"} ${event.type} -> ${mapped.hookEvent}: ${printed}`);
    if (!ok) failures++;
  }

  const openCodeAnswers = openCodeQuestionAnswers(
    [{ question: "Which database?", header: "Database", multiSelect: false }],
    { answers: { "Which database?": "Postgres" } });
  const answerOk = JSON.stringify(openCodeAnswers) === '[["Postgres"]]';
  console.log(`${answerOk ? "PASS" : "FAIL"} question answer conversion`);
  if (!answerOk) failures++;

  if (failures > 0) {
    console.error(`self-test: ${failures} failure(s)`);
    process.exit(1);
  }
  console.log("self-test: all payloads shaped correctly");
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain && process.argv.includes("--self-test")) {
  runSelfTest();
}
