// @i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now
// Perch lifecycle bridge for Amp.
import { spawnSync } from "node:child_process";

const hook = "__PERCH_HOOK__";

function send(event: string, payload: Record<string, unknown> = {}): void {
  spawnSync(hook, [event, "--source", "amp"], {
    input: JSON.stringify({ hook_event_name: event, ...payload }),
    timeout: 5_000,
    stdio: ["pipe", "ignore", "ignore"],
  });
}

export default (amp: { threadId?: string; on: (event: string, callback: (value?: any) => any) => void }): void => {
  const sessionId = (): string => amp.threadId ?? "";

  amp.on("session.start", () => {
    send("SessionStart", { session_id: sessionId(), cwd: process.cwd() });
  });
  amp.on("agent.start", () => {
    send("UserPromptSubmit", { session_id: sessionId(), cwd: process.cwd() });
  });
  amp.on("agent.end", () => {
    send("Stop", { session_id: sessionId() });
  });
  amp.on("tool.call", (value?: { tool?: string }) => {
    send("PreToolUse", { session_id: sessionId(), tool_name: value?.tool ?? "" });
    return { action: "allow" };
  });
  amp.on("tool.result", (value?: { tool?: string }) => {
    send("PostToolUse", { session_id: sessionId(), tool_name: value?.tool ?? "" });
    return { action: "allow" };
  });
};
