import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { spawn } from "node:child_process";

const hook = "__PERCH_HOOK__";

export default function activate(pi: ExtensionAPI): void {
  const sessionId = (ctx: any): string => {
    const value = ctx?.sessionManager?.getSessionId?.() ?? `process-${process.pid}`;
    return String(value).startsWith("pi-") ? String(value) : `pi-${value}`;
  };
  const childId = (): string | undefined => {
    if (process.env.PI_SUBAGENT_CHILD !== "1") return undefined;
    const run = process.env.PI_SUBAGENT_RUN_ID;
    const index = process.env.PI_SUBAGENT_CHILD_INDEX;
    return run && index ? `${run}:${index}` : undefined;
  };
  const send = (event: string, ctx: any, extra: Record<string, unknown> = {}): void => {
    const child = spawn(hook, [event, "--source", "pi"], {
      stdio: ["pipe", "ignore", "ignore"],
    });
    child.on("error", () => {});
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify({
      hook_event_name: event,
      session_id: sessionId(ctx),
      cwd: ctx?.cwd ?? ctx?.sessionManager?.getCwd?.(),
      ...extra,
    }));
  };
  const lifecycle = (rootEvent: string, childEvent: string, ctx: any): void => {
    const id = childId();
    send(id ? childEvent : rootEvent, ctx, id ? {
      agent_id: id,
      agent_type: process.env.PI_SUBAGENT_CHILD_AGENT ?? "Pi child",
      tool_input: { description: process.env.PI_SUBAGENT_CHILD_AGENT ?? "Pi child" },
    } : {});
  };

  pi.on("session_start", (_event, ctx) => lifecycle("SessionStart", "SubagentStart", ctx));
  pi.on("before_agent_start", (event: any, ctx) => {
    if (childId()) return;
    send("UserPromptSubmit", ctx, { prompt: event?.prompt });
  });
  pi.on("tool_execution_start", (event: any, ctx) => {
    send("PreToolUse", ctx, { tool_name: event?.toolName ?? event?.tool });
  });
  pi.on("tool_execution_end", (event: any, ctx) => {
    send("PostToolUse", ctx, { tool_name: event?.toolName ?? event?.tool });
  });
  pi.on("agent_end", (_event, ctx) => lifecycle("Stop", "SubagentStop", ctx));
  pi.on("session_shutdown", (_event, ctx) => {
    if (!childId()) send("SessionEnd", ctx);
  });
}
