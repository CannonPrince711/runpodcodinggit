# RunPod RTX A5000 — AI-Assisted Game Modding Workstation
### code-server + Aider + Qwen2.5-Coder

code-server is the only IDE. JupyterLab is not used, not exposed, and stopped on every boot.

> **Quick install:** run `curl -fsSL https://raw.githubusercontent.com/CannonPrince711/runpodcodinggit/main/install.sh | bash` in the pod's terminal (or paste the line from `install-oneliner.txt`). It writes `/workspace/install.sh` and runs it, doing sections 2–10 below in one go. Set your git name first if you like: `export GIT_NAME="Me" GIT_EMAIL="me@example.com"`.

---

## 0. The One Rule

The **Container Disk is ephemeral** — wiped on every restart, stop/start, reboot or pod recreation.
The **Network Volume (`/workspace`) is permanent**.

| Store on `/workspace` | Never store here |
|---|---|
| Mod projects, decompiled code, assets | OS / apt packages |
| Qwen model weights | System Python pip installs |
| Aider configs & git repos | `~/.bashrc` changes (back them up) |
| code-server settings & extensions | Temporary build artifacts |

If it matters and isn't on `/workspace`, it doesn't exist tomorrow.

---

## 1. Pod Configuration (RunPod Settings)

| Setting | Value |
|---|---|
| GPU | NVIDIA RTX A5000 (24 GB VRAM) |
| vCPU | 8–12 |
| RAM | 32–48 GB |
| **Container Disk** | **25 GB** (ephemeral) |
| **Network Volume** | **120 GB** (persistent, mounted at `/workspace`) |
| Template | RunPod PyTorch (remove port 8888 and any `JUPYTER_PASSWORD` env var from the template) |
| Exposed ports | 8080 (code-server) only. Do NOT expose 11434: Ollama has no auth and Aider reaches it on localhost |

### Storage justification

**Container Disk — 25 GB**
- Ubuntu OS + CUDA runtime
- System packages (`apt`): git, tmux, zip, dotnet-sdk, etc.
- code-server binary, Ollama binary
- Temporary build files

**Network Volume — 120 GB**

| Item | Size | Why |
|---|---|---|
| Qwen 14B weights | ~9 GB | Ollama blobs |
| Qwen 32B weights (optional) | ~20 GB | Future headroom |
| Node / build caches | 5–8 GB | npm, nuget |
| Aider repo maps | ~1 GB | `.aider.tags.cache` |
| code-server extensions & user data | 1–2 GB | C# Dev Kit, C++ tools, GitLens |
| Game modding tools | 5–10 GB | BepInEx, MelonLoader, UE4SS, ILSpy |
| Mod projects + decompiled assemblies | 15–25 GB | Grows fastest; multiple games |
| Docs, prompts, notes | 5 GB | Research, save-format findings |
| Headroom | ~45 GB | Decompiled Unity/Unreal games are huge |
| **Total** | **~120 GB** | |

---

## 2. Directory Layout

```bash
mkdir -p /workspace/{mods,tools,scripts,docs,downloads}
mkdir -p /workspace/ai/{aider,rules,prompts,context}
mkdir -p /workspace/models/{ollama,huggingface}
mkdir -p /workspace/dev-env
mkdir -p /workspace/code-server/{data,extensions}
mkdir -p /workspace/mods/shared-libraries
```

Per-game layout (one git repo per game):

```text
/workspace/mods/
├── Game_A/
│   ├── src/            # your mod source
│   ├── Decompiled/     # read-only game code for reference
│   ├── docs/           # findings, save-format notes
│   ├── refs/           # game DLLs for reference
│   └── .git/
├── Game_B/
└── shared-libraries/
```

---

## 3. Environment Variables

```bash
cat >> ~/.bashrc << 'EOF'
export WORKSPACE=/workspace

# AI models — MUST be on persistent storage
export OLLAMA_MODELS=/workspace/models/ollama
export HF_HOME=/workspace/models/huggingface
export HUGGINGFACE_HUB_CACHE=/workspace/models/huggingface/hub
export OLLAMA_API_BASE=http://127.0.0.1:11434
export OLLAMA_KEEP_ALIVE=30m

# Caches — persistent
export npm_config_cache=/workspace/dev-env/npm-cache
export NUGET_PACKAGES=/workspace/dev-env/nuget


# Aider
export AIDER_MODEL_SETTINGS_FILE=/workspace/ai/aider/.aider.model.settings.yml
alias aider='/opt/aider-env/bin/aider --config /workspace/ai/aider/.aider.conf.yml'

# Shortcuts
alias mod='bash /workspace/scripts/mod.sh'
alias newmod='bash /workspace/scripts/newmod.sh'
alias newmod.sh='bash /workspace/scripts/newmod.sh'
alias ws='cd /workspace'
alias dl='cd /workspace/downloads'
alias cslog='tail -f /workspace/code-server.log'
alias ollog='tail -f /workspace/ollama.log'
EOF

source ~/.bashrc
mkdir -p $OLLAMA_MODELS $HF_HOME $npm_config_cache $NUGET_PACKAGES
```

---

## 4. System Dependencies

```bash
apt update && apt upgrade -y
apt install -y \
  git curl wget unzip zip tar jq tree \
  build-essential cmake pkg-config \
  htop nvtop ncdu ripgrep fd-find \
  nano vim micro tmux sqlite3 \
  python3-venv python3-pip \
  file ranger nnn mc p7zip-full zstd pciutils lshw
```

Optional but recommended for .NET/Unity modding:

```bash
apt install -y dotnet-sdk-8.0
```

---

## 5. Install code-server (Persistent)

```bash
curl -fsSL https://code-server.dev/install.sh | sh

mkdir -p /workspace/code-server/{data,extensions}

# Random password stored on the volume (read it with: cat /workspace/code-server/password)
[ -f /workspace/code-server/password ] || { openssl rand -base64 18 > /workspace/code-server/password 2>/dev/null; }
PASSWORD="$(cat /workspace/code-server/password)" nohup setsid code-server \
  --bind-addr 0.0.0.0:8080 \
  --auth password \
  --user-data-dir /workspace/code-server/data \
  --extensions-dir /workspace/code-server/extensions \
  /workspace > /workspace/code-server.log 2>&1 &
```

Access: **RunPod Connect → HTTP Services → port 8080**

### Install extensions (persisted via `--extensions-dir`)

```bash
EXT_DIR=/workspace/code-server/extensions

# code-server installs from Open VSX, not Microsoft's marketplace.
# C# Dev Kit and the MS C/C++ extension are not on Open VSX (license-restricted), so use the open equivalents:
code-server --extensions-dir $EXT_DIR --install-extension muhammad-sammy.csharp
code-server --extensions-dir $EXT_DIR --install-extension llvm-vs-code-extensions.vscode-clangd
code-server --extensions-dir $EXT_DIR --install-extension sumneko.lua
code-server --extensions-dir $EXT_DIR --install-extension ms-python.python
code-server --extensions-dir $EXT_DIR --install-extension eamodio.gitlens
code-server --extensions-dir $EXT_DIR --install-extension ms-vscode.hexeditor
code-server --extensions-dir $EXT_DIR --install-extension esbenp.prettier-vscode
```

### code-server settings

```bash
mkdir -p /workspace/code-server/data/User
cat > /workspace/code-server/data/User/settings.json << 'EOF'
{
  "editor.minimap.enabled": true,
  "files.autoSave": "afterDelay",
  "files.exclude": {
    "**/bin": true,
    "**/obj": true,
    "**/.git": true,
    "**/.aider.tags.cache.v*": true
  },
  "search.exclude": {
    "**/bin": true,
    "**/obj": true,
    "**/Decompiled": false
  },
  "git.enableSmartCommit": true,
  "terminal.integrated.defaultProfile.linux": "bash"
}
EOF
```

---

## 6. Install Ollama & Qwen

```bash
curl -fsSL https://ollama.com/install.sh | sh

# Start (models persist via OLLAMA_MODELS)
ollama serve > /workspace/ollama.log 2>&1 &
sleep 5
curl http://localhost:11434    # -> "Ollama is running"
```

### Pull Qwen models

```bash
# Primary — best balance for A5000
ollama pull qwen2.5-coder:14b-instruct

# Fast fallback for quick questions
ollama pull qwen2.5-coder:7b-instruct

# Optional — heavy, ~20 GB, only if you need max reasoning
# ollama pull qwen2.5-coder:32b-instruct

ollama list
```

---

## 7. Install Aider

```bash
# Git identity (aider auto-commits — required)
git config --global user.name  "YourName"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
git config --global --add safe.directory '*'

# The venv lives on the container disk (/opt): the network volume refuses chmod, which pip needs.
# post_restart.sh saves it to /workspace/dev-env/cache/aider.tar and restores it after each restart.
python3 -m venv /opt/aider-env
/opt/aider-env/bin/pip install --no-cache-dir --upgrade pip
/opt/aider-env/bin/pip install --no-cache-dir aider-chat

/opt/aider-env/bin/aider --version
```

### Model settings — critical context override

Ollama's default context is small (2048–4096 depending on version). Without this, Aider truncates silently.

```bash
cat > /workspace/ai/aider/.aider.model.settings.yml << 'EOF'
- name: ollama/qwen2.5-coder:14b-instruct
  edit_format: diff
  use_repo_map: true
  examples_as_sys_msg: true
  extra_params:
    num_ctx: 32768

- name: ollama/qwen2.5-coder:7b-instruct
  edit_format: whole
  use_repo_map: true
  extra_params:
    num_ctx: 16384

- name: ollama/qwen2.5-coder:32b-instruct
  edit_format: diff
  use_repo_map: true
  extra_params:
    num_ctx: 8192   # 32B q4 is ~20 GB; bigger ctx spills to CPU on a 24 GB card
EOF
```

### Aider config

```bash
cat > /workspace/ai/aider/.aider.conf.yml << 'EOF'
model: ollama/qwen2.5-coder:14b-instruct
model-settings-file: /workspace/ai/aider/.aider.model.settings.yml

read:
  - /workspace/ai/rules/MODDING_RULES.md

auto-commits: true
attribute-author: false
gitignore: true
dark-mode: true
stream: true
cache-prompts: true
EOF
```

### Standing modding rules (loaded into every session)

```bash
cat > /workspace/ai/rules/MODDING_RULES.md << 'EOF'
# Game Modding Rules

## Role
Expert game modding engineer. Languages: C#, C++, Lua, Python.
Frameworks: BepInEx, MelonLoader, HarmonyX, MonoMod, UE4SS, Doorstop.

## Hard rules
1. Read existing code before modifying it. Never invent APIs or method signatures.
2. If a game method signature is unknown, say so and ask for the decompiled source.
3. Harmony patches: prefer Postfix. Use Prefix only when the original must be skipped, and state why.
4. Never break save compatibility. Flag anything that touches serialized state.
5. Null-check everything returned by game APIs. Modded runtimes fail silently.
6. Wrap patch bodies in try/catch and log via the plugin logger — an unhandled exception in a patch can hard-crash the game.
7. All tunables go in a BepInEx ConfigEntry, not hardcoded constants.
8. Keep namespaces unique per mod. Never reuse a game's own namespace.
9. One feature per change. Do not refactor unrelated code.

## Output
- Complete compilable files, not fragments.
- Include required `using` directives.
- Note any new assembly references needed in the .csproj.
- State target framework if it matters (netstandard2.1 / net472 / net6.0).
EOF
```

---

## 8. Helper Scripts

### `/workspace/scripts/newmod.sh` — create a game mod workspace

```bash
cat > /workspace/scripts/newmod.sh << 'EOF'
#!/bin/bash
# Usage: newmod.sh <GameName>
set -e
[ -z "$1" ] && { echo "usage: newmod.sh <GameName>"; exit 1; }
DIR="/workspace/mods/$1"
mkdir -p "$DIR"/{src,Decompiled,docs,refs}
cd "$DIR"

cat > .gitignore << 'IGN'
bin/
obj/
*.user
*.suo
*.dll
*.pdb
*.mdb
Decompiled/
refs/
.aider.tags.cache.v*/
.aider.chat.history.md
.aider.input.history
IGN

cat > CONVENTIONS.md << CONV
# $1 — Mod Notes

- Engine / version:
- Mod loader:
- Target framework:
- Key assemblies:
- Decompiled source: ./Decompiled  (read-only reference)
- Source: ./src
CONV

git init -q
git add -A
git commit -qm "init: $1 mod workspace"
echo "Created $DIR"
EOF
```

### `/workspace/scripts/mod.sh` — launch Aider inside tmux

```bash
cat > /workspace/scripts/mod.sh << 'EOF'
#!/bin/bash
# Usage: mod <GameName>  [-- attach to tmux session ]
GAME="$1"
[ -z "$GAME" ] && { echo "usage: mod <GameName>"; exit 1; }
DIR="/workspace/mods/$GAME"
[ ! -d "$DIR" ] && { echo "no such mod: $GAME (run: newmod.sh $GAME)"; exit 1; }

SESSION="mod-$GAME"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  exec tmux attach -t "$SESSION"
fi

tmux new-session -s "$SESSION" -c "$DIR" \
  "/opt/aider-env/bin/aider \
   --config /workspace/ai/aider/.aider.conf.yml \
   --read ./CONVENTIONS.md"
EOF
```

Usage:

```bash
newmod.sh Game_A      # scaffold once
mod Game_A            # opens Aider in a detached-safe tmux session
```

**Why tmux:** if your network drops or code-server restarts, `mod Game_A` reattaches you to the exact Aider session. Nothing is lost.

---

## 9. File Access — The Easy Ways

### A. code-server Explorer (primary)

Open code-server on **port 8080**.

| Action | Method |
|---|---|
| Browse files | `Ctrl+Shift+E` (left sidebar) |
| Quick open | `Ctrl+P`, type filename |
| Upload | Drag from desktop into file tree |
| Download file | Right-click → **Download…** |
| Download folder | Zip in terminal first, then right-click → Download |
| Search all mods | `Ctrl+Shift+F` |
| Terminal | `Ctrl+\`` (backtick) |
| Reveal in terminal | Right-click file → **Open in Integrated Terminal** |
| New folder | Right-click → New Folder |

### B. Terminal file managers

```bash
ranger          # vim keys: hjkl, yy, pp, dd
mc              # midnight commander (mouse-friendly)
nnn             # minimal
```

### C. Bulk transfer via zip

```bash
# Upload: drag zip into code-server, then:
cd /workspace/downloads
unzip MyGameMods.zip -d /workspace/mods/

# Download:
cd /workspace/mods/Game_A
zip -r /workspace/downloads/Game_A.zip . -x "*.git*" "bin/*" "obj/*"
```

Then download `/workspace/downloads/Game_A.zip` via the code-server explorer.

### D. SCP (if you enabled SSH keys)

```bash
# From your local machine
scp -P <port> -r ./MyMods root@<pod-ip>:/workspace/mods/
scp -P <port> -r root@<pod-ip>:/workspace/mods/Game_A ./backups/
```

---

## 10. `post_restart.sh` — Recovery Script

Run this after **every** pod start. It restores everything the container disk lost.

```bash
cat > /workspace/scripts/post_restart.sh << 'EOF'
#!/bin/bash
set -e
echo "==> Restoring RunPod environment"

# --- 1. Env vars ---
grep -q OLLAMA_MODELS ~/.bashrc 2>/dev/null || cat >> ~/.bashrc << 'VARS'
export WORKSPACE=/workspace
export OLLAMA_MODELS=/workspace/models/ollama
export HF_HOME=/workspace/models/huggingface
export HUGGINGFACE_HUB_CACHE=/workspace/models/huggingface/hub
export OLLAMA_API_BASE=http://127.0.0.1:11434
export OLLAMA_KEEP_ALIVE=30m
export npm_config_cache=/workspace/dev-env/npm-cache
export NUGET_PACKAGES=/workspace/dev-env/nuget
export AIDER_MODEL_SETTINGS_FILE=/workspace/ai/aider/.aider.model.settings.yml
alias aider='/opt/aider-env/bin/aider --config /workspace/ai/aider/.aider.conf.yml'
alias mod='bash /workspace/scripts/mod.sh'
alias newmod='bash /workspace/scripts/newmod.sh'
alias newmod.sh='bash /workspace/scripts/newmod.sh'
alias ws='cd /workspace'
alias dl='cd /workspace/downloads'
alias cslog='tail -f /workspace/code-server.log'
alias ollog='tail -f /workspace/ollama.log'
VARS
# Also export for the processes this script starts (.bashrc returns early in non-interactive shells)
export OLLAMA_MODELS=/workspace/models/ollama
export OLLAMA_KEEP_ALIVE=30m
export HF_HOME=/workspace/models/huggingface

# --- 2. Git ---
# Identity is saved on the volume by install.sh (edit /workspace/dev-env/git-identity to change it)
[ -f /workspace/dev-env/git-identity ] && . /workspace/dev-env/git-identity
git config --global user.name  "${GIT_NAME:-YourName}"
git config --global user.email "${GIT_EMAIL:-you@example.com}"
git config --global init.defaultBranch main
git config --global --add safe.directory '*'

# --- 3. System packages + .NET: downloaded once, kept on /workspace ---
# The .deb files are saved to /workspace/dev-env/cache/debs on first install.
# After a restart they're installed straight from there: no apt update, no downloads.
# To update them, delete that folder and re-run this script.
export DEBIAN_FRONTEND=noninteractive
DEBS=/workspace/dev-env/cache/debs
PKGS="git curl wget unzip zip tar jq tree build-essential cmake pkg-config \
  htop nvtop ncdu ripgrep fd-find nano vim micro tmux sqlite3 \
  python3-venv python3-pip file ranger nnn mc p7zip-full zstd pciutils lshw \
  dotnet-sdk-8.0"
if ! command -v tmux >/dev/null || ! command -v dotnet >/dev/null || ! command -v lspci >/dev/null; then
  if ls "$DEBS"/*.deb >/dev/null 2>&1 && dpkg -i "$DEBS"/*.deb >/dev/null 2>&1 && command -v dotnet >/dev/null; then
    echo "    restored system packages + .NET from /workspace"
  else
    echo "    downloading system packages + .NET..."
    apt-get update -qq
    apt-get -f install -y -qq >/dev/null 2>&1 || true   # repair a partial restore
    mkdir -p /var/cache/rp-debs/partial
    # shellcheck disable=SC2086
    apt-get install -y -qq --download-only -o Dir::Cache::archives=/var/cache/rp-debs $PKGS
    # shellcheck disable=SC2086
    apt-get install -y -qq -o Dir::Cache::archives=/var/cache/rp-debs $PKGS
    mkdir -p "$DEBS"
    cp /var/cache/rp-debs/*.deb "$DEBS"/ 2>/dev/null && echo "    saved packages to $DEBS" \
      || echo "    WARN: could not save packages to /workspace"
  fi
fi

# --- 3b. No JupyterLab: stop it if the template started it ---
pkill -f jupyter-lab 2>/dev/null || true
pkill -f jupyter-notebook 2>/dev/null || true

# --- 4-6. Ollama, Aider, code-server: installed once, kept on /workspace ---
# The network volume refuses chmod, so programs can't run from it directly.
# Instead each install is saved to /workspace/dev-env/cache as a .tar and
# unpacked onto the container disk after a restart: no downloads, ~seconds.
# To update one, delete its .tar and re-run this script.
CACHE=/workspace/dev-env/cache
mkdir -p "$CACHE"
restore() { [ -f "$CACHE/$1.tar" ] && echo "    restoring $1 from /workspace" && tar -xf "$CACHE/$1.tar" -C /; }
save() {   # save <name> <abs paths...>
  local name=$1; shift; local rel=()
  for p in "$@"; do [ -e "$p" ] && rel+=("${p#/}"); done
  if [ ${#rel[@]} -gt 0 ] && tar -cf "$CACHE/$name.tar.tmp" -C / "${rel[@]}" && mv -f "$CACHE/$name.tar.tmp" "$CACHE/$name.tar"; then
    echo "    saved $name to $CACHE/$name.tar"
  else
    echo "    WARN: could not save $name to /workspace"
  fi
}

# Ollama
if ! command -v ollama >/dev/null; then
  restore ollama || true
  if ! command -v ollama >/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
    OLLAMA_BIN=$(command -v ollama)
    save ollama "$OLLAMA_BIN" "$(dirname "$(dirname "$OLLAMA_BIN")")/lib/ollama"
  fi
fi
pgrep -x ollama >/dev/null || nohup setsid ollama serve > /workspace/ollama.log 2>&1 &

# Aider (venv at /opt/aider-env)
if ! /opt/aider-env/bin/aider --version >/dev/null 2>&1; then
  restore aider || true
  if ! /opt/aider-env/bin/aider --version >/dev/null 2>&1; then
    echo "    installing aider..."
    python3 -m venv --clear /opt/aider-env
    /opt/aider-env/bin/pip install -q --no-cache-dir --upgrade pip
    /opt/aider-env/bin/pip install -q --no-cache-dir aider-chat
    save aider /opt/aider-env
  fi
fi

# code-server (settings, extensions and password already live in /workspace/code-server)
if ! command -v code-server >/dev/null; then
  restore code-server || true
  if ! command -v code-server >/dev/null; then
    curl -fsSL https://code-server.dev/install.sh | sh
    save code-server /usr/lib/code-server /usr/bin/code-server "$HOME/.local/lib/code-server" "$HOME/.local/bin/code-server"
  fi
fi

mkdir -p /workspace/code-server/{data,extensions}
# Keep the password in a file on the volume instead of hardcoding it here
[ -f /workspace/code-server/password ] || { openssl rand -base64 18 > /workspace/code-server/password 2>/dev/null; }
pgrep -f "code-server.*--bind-addr" >/dev/null || \
  PASSWORD="$(cat /workspace/code-server/password)" nohup setsid code-server \
     --bind-addr 0.0.0.0:8080 --auth password \
     --user-data-dir /workspace/code-server/data \
     --extensions-dir /workspace/code-server/extensions \
     /workspace > /workspace/code-server.log 2>&1 &

# --- 7. Directories ---
mkdir -p /workspace/downloads /workspace/mods /workspace/docs

sleep 6
echo "==> Status"
ollama list 2>/dev/null || echo "    ollama: starting..."
echo "    code-server: :8080 (password in /workspace/code-server/password)"
echo "    run: source ~/.bashrc   (to load aliases in this shell)"
echo "==> Ready."
EOF
```

---

## 11. Daily Workflow

1. **Start pod** on RunPod.
2. **Recover** — open terminal, run:
   ```bash
   bash /workspace/scripts/post_restart.sh
   ```
3. **Open code-server** — Connect → HTTP Services → port 8080. Log in with the password from `cat /workspace/code-server/password`.
4. **Scaffold a new game** (once per game):
   ```bash
   newmod.sh Game_A
   ```
5. **Launch Aider** in the code-server terminal:
   ```bash
   mod Game_A
   ```
   - Wraps Aider in tmux. If you close the tab, reconnect later with the same command.
6. **Load context** inside Aider:
   ```
   /read-only Decompiled/PlayerController.cs
   /read-only docs/save_format.md
   /add src/Patches/DamagePatch.cs
   ```
7. **Plan first:**
   ```
   /ask How does damage get applied here, and what's the safest hook point?
   ```
8. **Implement:**
   ```
   Add a Harmony Postfix that halves damage when ConfigBind<bool>.Section, "HalveDamage" is true.
   ```
9. **Verify:**
   ```
   /run dotnet build
   ```
   Build errors stream straight back to Qwen.
10. **Review & undo:**
    ```
    /diff
    /undo          # if wrong — instantly reverts last auto-commit
    ```
11. **Drop context** before next feature to save tokens:
    ```
    /drop Decompiled/PlayerController.cs
    /tokens
    ```
12. **Research** (if needed) — open the hex editor in code-server (or a Python script in the terminal) for binary save formats, then save findings to `docs/` and `/read-only` them in Aider.

---

## 12. Aider Cheat Sheet

| Command | Use |
|---|---|
| `/add <file>` | Make editable |
| `/read-only <file>` | Reference only — never edited |
| `/drop <file>` | Free context |
| `/ask <q>` | Question mode, no edits |
| `/architect` | Plan-then-edit for multi-file changes |
| `/run <cmd>` | Run command, feed output back to Qwen |
| `/diff` | Pending changes since last message |
| `/undo` | Revert last auto-commit |
| `/tokens` | Context usage |
| `/model ollama/qwen2.5-coder:32b-instruct` | Swap models |
| `/reset` | Clear session |

**Editing pattern for modding:**
- `/read-only` all decompiled game code
- `/add` only your own `src/` files
- Qwen sees the game API surface but can only write to your mod

---

## 13. Troubleshooting

| Problem | Fix |
|---|---|
| Aider ignores file contents | Check `AIDER_MODEL_SETTINGS_FILE` is exported; run `/tokens` |
| "Failed to apply edit" loops | Model too weak for diff format — switch to `edit_format: whole` |
| Ollama OOM / killed | Lower `num_ctx` to 16384; check `nvtop` |
| code-server won't start | Check `/workspace/code-server.log`; port 8080 in use |
| Extensions gone after restart | Confirm `--extensions-dir` points to `/workspace` |
| Aider not found | Run `post_restart.sh` to rebuild venv |
| Tmux session lost | Pod restart killed it; Aider state saved in git. `git log` to recover |
| Slow first response | `export OLLAMA_KEEP_ALIVE=30m` prevents model eviction |

---

## 14. Final Summary

| Component | Choice |
|---|---|
| **GPU** | RTX A5000 (24 GB) |
| **Container Disk** | 25 GB (ephemeral) |
| **Network Volume** | 120 GB (persistent → `/workspace`) |
| **IDE** | code-server (VS Code, browser, port 8080) |
| **AI Model** | Qwen2.5-Coder 14B via Ollama |
| **Coding Agent** | Aider (CLI, in tmux, inside code-server) |
| **Session Persistence** | tmux |
| **Git** | One repo per game, auto-commit via Aider |
| **File Access** | code-server explorer + drag/drop + zip + SCP |

**The loop:** code-server to browse and edit → Aider in the terminal to write patches → Qwen to reason about game code → git to undo mistakes → `/workspace` so it all survives tomorrow.

---

## 15. Save This Guide on the Pod

Upload this file into code-server (drag it into `/workspace/docs/`), or on the pod:

```bash
cat > /workspace/docs/setup-guide.md << 'GUIDE_EOF'
# [paste this whole guide here]
GUIDE_EOF
```

To download it again: right-click `docs/setup-guide.md` in code-server → **Download…**

If you copy scripts out of this guide on Windows, make sure the editor saves them with LF line endings, or bash fails with `$'\r': command not found`.

---

## 16. Changes From the Original Draft

| Area | Original | Now |
|---|---|---|
| JupyterLab | Jupyter extension, `notebooks/` folder | Removed; `post_restart.sh` stops it if the template starts it |
| `post_restart.sh` deps | No `apt-get update`, wrong package names (`rg`, `p7zip-full`), aborted under `set -e` | `apt-get update` then one install with correct package names |
| Helper scripts | `newmod.sh` not runnable; `chmod` fails on the network volume | No `chmod` anywhere; `mod`, `newmod`, `newmod.sh` are aliases that run the scripts with `bash` |
| Aider, code-server, Ollama, system packages, .NET | Reinstalled from the internet on every restart | Installed once, saved as .tar files in `/workspace/dev-env/cache`, unpacked in seconds after a restart |
| Extensions | C# Dev Kit, MS C/C++ (not on Open VSX) | `muhammad-sammy.csharp`, `clangd` |
| Aider config | `AIDER_CONFIG_FILE` (not read by Aider) | `aider` alias passes `--config` |
| Ollama port | 11434 exposed publicly, no auth | Not exposed; localhost only |
| code-server password | Hardcoded `modding123` | Random, stored in `/workspace/code-server/password` |
| Decompiled code | Committed to git | Gitignored (still usable via `/read-only`) |
| 32B model context | 16k (overflows 24 GB) | 8k |
| NuGet cache | Lost on restart | `NUGET_PACKAGES` on `/workspace` |
| Background services | Died with the terminal | Started with `nohup setsid` |
