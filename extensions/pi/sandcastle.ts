import { execFile as execFileCb } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { StringEnum } from "@mariozechner/pi-ai";
import { Type } from "@sinclair/typebox";

const execFile = promisify(execFileCb);

function asErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

function defaultBranch(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const date =
    `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
    `-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  return `sandcastle/${date}`;
}

function sanitizeBranchForPath(branch: string): string {
  return branch.replace(/[^a-zA-Z0-9._-]/g, "_");
}

function readDefaultModel(): string | undefined {
  try {
    const settingsPath = join(homedir(), ".pi", "agent", "settings.json");
    const text = readFileSync(settingsPath, "utf8");
    const parsed = JSON.parse(text);
    return typeof parsed?.defaultModel === "string" ? parsed.defaultModel : undefined;
  } catch {
    return undefined;
  }
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "sandcastle_run",
    label: "Sandcastle Run",
    description: "Run an AFK agent in a Docker sandbox + git worktree; see the sandcastle skill for usage.",
    promptGuidelines: [
      "Load the sandcastle skill before first use to understand options and output format.",
      "Reserve for hand-off implementation tasks requiring multiple steps, not quick edits.",
    ],
    parameters: Type.Object({
      task: Type.String({ description: "The full prompt for the sandboxed agent." }),
      model: Type.Optional(Type.String({ description: "Model to use. Defaults to defaultModel from ~/.pi/agent/settings.json." })),
      repoPath: Type.Optional(Type.String({ description: "Host repo directory. Defaults to process.cwd(). Must contain a .git file or directory." })),
      branch: Type.Optional(Type.String({ description: "Branch name for agent commits. Defaults to sandcastle/<yyyymmdd-hhmmss>." })),
      merge: Type.Optional(Type.Boolean({ description: "If true, merge agent branch back to HEAD automatically. Default false." })),
      maxIterations: Type.Optional(Type.Number({ description: "Max agent iterations. Default 1, min 1, max 5.", minimum: 1, maximum: 5 })),
      thinking: Type.Optional(StringEnum(["off", "minimal", "low", "medium", "high", "xhigh"] as const)),
    }),
    async execute(_toolCallId, params, signal, onUpdate) {
      // 1. Preflight: docker available?
      try {
        await execFile("docker", ["version"], { timeout: 10_000 });
      } catch (err) {
        return {
          content: [{ type: "text", text: `Docker not available/running: ${asErrorMessage(err)}. Ensure Docker Desktop is running and try again.` }],
          details: { error: asErrorMessage(err) },
          isError: true,
        };
      }

      // Validate repoPath
      const repoPath = params.repoPath ?? process.cwd();
      const gitPath = join(repoPath, ".git");
      if (!existsSync(gitPath)) {
        return {
          content: [{ type: "text", text: `repoPath "${repoPath}" does not contain a .git entry. Provide the root of a git repo or worktree.` }],
          details: { repoPath },
          isError: true,
        };
      }

      // 2. Resolve model
      const model = params.model ?? readDefaultModel();
      if (!model) {
        return {
          content: [{ type: "text", text: "No model specified and no defaultModel found in ~/.pi/agent/settings.json. Pass the model parameter or set defaultModel in settings." }],
          details: {},
          isError: true,
        };
      }

      // 3. Build mounts and passthrough env
      const piDir = join(homedir(), ".pi", "agent");
      const authHostPath = join(piDir, "auth.json");
      const modelsHostPath = join(piDir, "models.json");

      const mounts: Array<{ hostPath: string; sandboxPath: string; readonly?: boolean }> = [];
      if (existsSync(authHostPath)) {
        mounts.push({ hostPath: authHostPath, sandboxPath: "/home/agent/.pi/agent/auth.json", readonly: true });
      }
      if (existsSync(modelsHostPath)) {
        mounts.push({ hostPath: modelsHostPath, sandboxPath: "/home/agent/.pi/agent/models.json", readonly: true });
      }

      const API_KEY_NAMES = [
        "ANTHROPIC_API_KEY",
        "OPENAI_API_KEY",
        "GOOGLE_API_KEY",
        "GEMINI_API_KEY",
        "OPENROUTER_API_KEY",
        "GROQ_API_KEY",
        "XAI_API_KEY",
        "DEEPSEEK_API_KEY",
        "MISTRAL_API_KEY",
        "CEREBRAS_API_KEY",
      ] as const;

      const passthroughEnv: Record<string, string> = {};
      for (const key of API_KEY_NAMES) {
        if (process.env[key]) passthroughEnv[key] = process.env[key]!;
      }

      // Resolve branch and logging path
      const branch = params.branch ?? defaultBranch();
      const logDir = join(repoPath, ".sandcastle", "logs");
      try {
        mkdirSync(logDir, { recursive: true });
      } catch {
        // ignore — run() will create it if needed
      }
      const logPath = join(logDir, `${sanitizeBranchForPath(branch)}.log`);

      const branchStrategy =
        params.merge === true
          ? ({ type: "merge-to-head" } as const)
          : ({ type: "branch", branch } as const);

      // Dynamic import — extension loads even when dep is absent
      let sandcastleMod: typeof import("@ai-hero/sandcastle");
      let dockerMod: { docker: (opts?: { mounts?: typeof mounts; env?: Record<string, string> }) => unknown };
      try {
        sandcastleMod = await import("@ai-hero/sandcastle") as typeof import("@ai-hero/sandcastle");
        dockerMod = await import("@ai-hero/sandcastle/sandboxes/docker") as typeof dockerMod;
      } catch (err) {
        return {
          content: [{ type: "text", text: `@ai-hero/sandcastle is not installed. Re-run install.sh (which runs npm install in ~/.pi/agent/extensions) and try again. Error: ${asErrorMessage(err)}` }],
          details: { error: asErrorMessage(err) },
          isError: true,
        };
      }

      const { run, pi: piProvider } = sandcastleMod;
      const { docker } = dockerMod;

      onUpdate?.({
        content: [{ type: "text", text: `Launching sandcastle agent on branch "${branch}" in ${repoPath} (model: ${model}, maxIterations: ${params.maxIterations ?? 1})…` }],
        details: undefined,
      });

      // Throttle onUpdate: only forward toolCall events, at most one per 5s
      let lastUpdateTime = 0;
      const THROTTLE_MS = 5_000;

      try {
        const result = await run({
          agent: piProvider(model, {
            thinking: params.thinking,
            env: Object.keys(passthroughEnv).length > 0 ? passthroughEnv : undefined,
          }),
          sandbox: docker({ mounts, env: Object.keys(passthroughEnv).length > 0 ? passthroughEnv : undefined }),
          cwd: repoPath,
          prompt: params.task,
          maxIterations: params.maxIterations ?? 1,
          branchStrategy,
          signal,
          logging: {
            type: "file",
            path: logPath,
            onAgentStreamEvent: (event) => {
              if (event.type !== "toolCall") return;
              const now = Date.now();
              if (now - lastUpdateTime < THROTTLE_MS) return;
              lastUpdateTime = now;
              onUpdate?.({
                content: [{ type: "text", text: `[iter ${event.iteration}] tool: ${event.name} ${event.formattedArgs.slice(0, 120)}` }],
                details: undefined,
              });
            },
          },
        });

        const commitSummary =
          result.commits.length === 0
            ? "no commits"
            : `${result.commits.length} commit${result.commits.length > 1 ? "s" : ""} (${result.commits.map((c) => c.sha.slice(0, 8)).join(", ")})`;

        const summary = [
          `branch: ${result.branch}`,
          `commits: ${commitSummary}`,
          `iterations: ${result.iterations.length}`,
          `completion signal: ${result.completionSignal ?? "none"}`,
          `log: ${result.logFilePath ?? logPath}`,
        ].join(" | ");

        return {
          content: [{ type: "text", text: summary }],
          details: result,
        };
      } catch (error) {
        const msg = asErrorMessage(error);
        const hint =
          /image|pull|not found|No such image/i.test(msg)
            ? " Hint: build the Docker image once with `npx @ai-hero/sandcastle docker build-image`."
            : "";
        return {
          content: [{ type: "text", text: `sandcastle_run failed: ${msg}${hint}` }],
          details: { error: msg },
          isError: true,
        };
      }
    },
  });
}
