import { execFileSync, spawn } from "node:child_process";
import { platform } from "node:os";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

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

function findLinuxClipboardCmd(): string[] | null {
  const candidates: [string, string[]][] = [
    ["wl-copy", []],
    ["xclip", ["-selection", "clipboard"]],
    ["xsel", ["--clipboard", "--input"]],
  ];
  for (const [bin, args] of candidates) {
    try {
      execFileSync("command", ["-v", bin], { stdio: "ignore" });
      return [bin, ...args];
    } catch {
      // not available, try next
    }
  }
  // execFileSync("command", ...) may not work for shell builtins on all systems;
  // fall back to a which-style check.
  for (const [bin, args] of candidates) {
    try {
      execFileSync("which", [bin], { stdio: "ignore" });
      return [bin, ...args];
    } catch {
      // not found
    }
  }
  return null;
}

function copyToClipboard(text: string) {
  return new Promise<void>((resolve, reject) => {
    let cmd: string;
    let args: string[];

    if (platform() === "darwin") {
      cmd = "pbcopy";
      args = [];
    } else {
      const found = findLinuxClipboardCmd();
      if (!found) {
        reject(
          new Error(
            "No clipboard tool found. Install wl-copy (Wayland), xclip, or xsel.",
          ),
        );
        return;
      }
      [cmd, ...args] = found;
    }

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

      await copyToClipboard(text);
      ctx.ui.notify(`Copied ${messages.length} messages to clipboard`, "info");
    },
  });
}
