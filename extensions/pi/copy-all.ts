import { execFileSync, spawn } from "node:child_process";
import { openSync, writeSync, closeSync } from "node:fs";
import { platform } from "node:os";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const OSC52_LIMIT = 99_000;

function textFromContent(content: unknown) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";

  return content
    .map((block) => {
      if (!block || typeof block !== "object") return "";
      if (!("type" in block)) return "";

      if (
        block.type === "text" &&
        "text" in block &&
        typeof block.text === "string"
      ) {
        return block.text;
      }

      if (block.type === "image") return "[image]";

      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function findLinuxDisplayClipboardCmd(): string[] | null {
  if (process.env.WAYLAND_DISPLAY) {
    try {
      execFileSync("which", ["wl-copy"], { stdio: "ignore" });
      return ["wl-copy"];
    } catch {
      // not found
    }
    try {
      execFileSync("command", ["-v", "wl-copy"], { stdio: "ignore" });
      return ["wl-copy"];
    } catch {
      // not found
    }
  }

  if (process.env.DISPLAY) {
    const candidates: [string, string[]][] = [
      ["xclip", ["-selection", "clipboard"]],
      ["xsel", ["--clipboard", "--input"]],
    ];
    for (const [bin, args] of candidates) {
      for (const checker of ["which", "command"] as const) {
        try {
          const checkerArgs = checker === "command" ? ["-v", bin] : [bin];
          execFileSync(checker, checkerArgs, { stdio: "ignore" });
          return [bin, ...args];
        } catch {
          // not found
        }
      }
    }
  }

  return null;
}

function copyViaOSC52(text: string): Promise<string | undefined> {
  return new Promise((resolve, reject) => {
    const b64 = Buffer.from(text).toString("base64");
    const warning =
      b64.length > OSC52_LIMIT
        ? `Text is large (${b64.length} base64 chars); some terminals cap OSC52 at ~100 KB and may silently drop it.`
        : undefined;

    const inTmux = Boolean(process.env.TMUX);
    const tmuxHint = inTmux
      ? ' For tmux passthrough, ensure your tmux config includes: set -g allow-passthrough on'
      : undefined;

    const combinedWarning =
      warning || tmuxHint
        ? [warning, tmuxHint].filter(Boolean).join(" ")
        : undefined;

    // Build the raw OSC52 sequence
    const seq = `\x1b]52;c;${b64}\x07`;

    // Wrap in tmux DCS passthrough if inside tmux
    const payload = inTmux
      ? `\x1bPtmux;${seq.replace(/\x1b/g, "\x1b\x1b")}\x1b\\`
      : seq;

    let fd: number | null = null;
    try {
      fd = openSync("/dev/tty", "w");
      writeSync(fd, payload);
      closeSync(fd);
    } catch {
      if (fd !== null) {
        try { closeSync(fd); } catch { /* ignore */ }
      }
      // /dev/tty not available — fall back to stdout
      try {
        process.stdout.write(payload);
      } catch (err) {
        reject(err);
        return;
      }
    }

    resolve(combinedWarning);
  });
}

function copyViaNativeCmd(text: string, cmd: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args);
    let stderr = "";

    child.stderr.on("data", (chunk) => {
      stderr += String(chunk);
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(stderr.trim() || `${cmd} exited with code ${code}`));
      }
    });

    child.stdin.end(text);
  });
}

/**
 * Copy text to clipboard.
 * Returns a warning string when the OSC52 path was used and there are caveats
 * (large payload, tmux config hint), or undefined on clean success.
 */
function copyToClipboard(text: string): Promise<string | undefined> {
  if (platform() === "darwin") {
    return copyViaNativeCmd(text, "pbcopy", []).then(() => undefined);
  }

  // Linux: only use native tools when a display server is plausibly present
  const found = findLinuxDisplayClipboardCmd();
  if (found) {
    const [cmd, ...args] = found;
    return copyViaNativeCmd(text, cmd, args).then(() => undefined);
  }

  // Headless / SSH / tmux — use OSC52
  return copyViaOSC52(text);
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("copy-all", {
    description:
      "Copy all previous user and assistant messages in this thread to the clipboard",
    handler: async (_args, ctx) => {
      await ctx.waitForIdle();

      const messages = ctx.sessionManager
        .getBranch()
        .filter((entry) => entry.type === "message")
        .map((entry) => entry.message)
        .filter(
          (message) => message.role === "user" || message.role === "assistant",
        );

      const text = messages
        .map((message) => {
          const content = textFromContent(message.content).trim();
          return `${message.role.toUpperCase()}:\n${content}`;
        })
        .filter((section) => !section.endsWith(":\n"))
        .join("\n\n---\n\n");

      if (!text) {
        ctx.ui.notify("No user or assistant messages to copy", "info");
        return;
      }

      const usedOSC52 =
        platform() !== "darwin" && !findLinuxDisplayClipboardCmd();

      const warning = await copyToClipboard(text);

      const baseMsg = usedOSC52
        ? `Copied ${messages.length} messages via OSC52 (terminal clipboard)`
        : `Copied ${messages.length} messages to clipboard`;

      const notifyMsg = warning ? `${baseMsg}. ${warning}` : baseMsg;
      ctx.ui.notify(notifyMsg, "info");
    },
  });
}
