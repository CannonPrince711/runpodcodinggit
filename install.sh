#!/bin/bash
# RunPod modding workstation installer: code-server + Ollama/Qwen + Aider. No JupyterLab.
# Safe to re-run. Optional: GIT_NAME="Me" GIT_EMAIL="me@x.com" PULL_7B=0 PULL_32B=1 bash install.sh
set -e
[ -d /workspace ] || { echo "ERROR: /workspace not found. Attach a network volume first."; exit 1; }
echo "==> Creating directories"
mkdir -p /workspace/{mods/shared-libraries,tools,scripts,docs,downloads}
mkdir -p /workspace/ai/{aider,rules,prompts,context}
mkdir -p /workspace/models/{ollama,huggingface}
mkdir -p /workspace/dev-env/{pip-cache,npm-cache,nuget}
mkdir -p /workspace/code-server/{data/User,extensions}

echo "==> Saving git identity"
if [ ! -f /workspace/dev-env/git-identity ] || [ -n "$GIT_NAME$GIT_EMAIL" ]; then
  printf 'GIT_NAME=%q\nGIT_EMAIL=%q\n' "${GIT_NAME:-YourName}" "${GIT_EMAIL:-you@example.com}" > /workspace/dev-env/git-identity
fi

echo "==> Writing scripts and configs"

cat > /workspace/scripts/post_restart.sh << '__RPEOF0__'
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
export PIP_CACHE_DIR=/workspace/dev-env/pip-cache
export npm_config_cache=/workspace/dev-env/npm-cache
export NUGET_PACKAGES=/workspace/dev-env/nuget
export AIDER_MODEL_SETTINGS_FILE=/workspace/ai/aider/.aider.model.settings.yml
export PATH=/workspace/scripts:$PATH
alias aider='/workspace/dev-env/aider-env/bin/aider --config /workspace/ai/aider/.aider.conf.yml'
alias mod='/workspace/scripts/mod.sh'
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

# --- 3. System deps (apt lists are wiped with the container disk, so update first) ---
export DEBIAN_FRONTEND=noninteractive
if ! command -v tmux >/dev/null || ! command -v dotnet >/dev/null; then
  apt-get update -qq
  apt-get install -y -qq \
    git curl wget unzip zip tar jq tree build-essential cmake pkg-config \
    htop nvtop ncdu ripgrep fd-find nano vim micro tmux sqlite3 \
    python3-venv python3-pip file ranger nnn mc p7zip-full zstd \
    dotnet-sdk-8.0
fi

# --- 3b. No JupyterLab: stop it if the template started it ---
pkill -f jupyter-lab 2>/dev/null || true
pkill -f jupyter-notebook 2>/dev/null || true

# --- 4. Ollama ---
command -v ollama >/dev/null || curl -fsSL https://ollama.com/install.sh | sh
pgrep -x ollama >/dev/null || nohup setsid ollama serve > /workspace/ollama.log 2>&1 &

# --- 5. Aider venv (rebuild only if missing or broken) ---
if ! /workspace/dev-env/aider-env/bin/aider --version >/dev/null 2>&1; then
  echo "    rebuilding aider venv..."
  rm -rf /workspace/dev-env/aider-env
  python3 -m venv /workspace/dev-env/aider-env
  /workspace/dev-env/aider-env/bin/pip install -q --upgrade pip
  /workspace/dev-env/aider-env/bin/pip install -q aider-chat
fi

# --- 6. code-server ---
command -v code-server >/dev/null || curl -fsSL https://code-server.dev/install.sh | sh
mkdir -p /workspace/code-server/{data,extensions}
# Keep the password in a file on the volume instead of hardcoding it here
[ -f /workspace/code-server/password ] || { openssl rand -base64 18 > /workspace/code-server/password; chmod 600 /workspace/code-server/password; }
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
__RPEOF0__

cat > /workspace/scripts/newmod.sh << '__RPEOF1__'
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
__RPEOF1__

cat > /workspace/scripts/mod.sh << '__RPEOF2__'
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
  "/workspace/dev-env/aider-env/bin/aider \
   --config /workspace/ai/aider/.aider.conf.yml \
   --read ./CONVENTIONS.md"
__RPEOF2__

cat > /workspace/ai/aider/.aider.model.settings.yml << '__RPEOF3__'
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
__RPEOF3__

cat > /workspace/ai/aider/.aider.conf.yml << '__RPEOF4__'
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
__RPEOF4__

cat > /workspace/ai/rules/MODDING_RULES.md << '__RPEOF5__'
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
__RPEOF5__

[ -f /workspace/code-server/data/User/settings.json ] || cat > /workspace/code-server/data/User/settings.json << '__RPEOF_S__'
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
__RPEOF_S__

chmod +x /workspace/scripts/*.sh

echo "==> Installing packages and starting services (post_restart.sh)"
bash /workspace/scripts/post_restart.sh

export OLLAMA_MODELS=/workspace/models/ollama
echo "==> Waiting for Ollama"
for i in $(seq 1 60); do curl -sf http://127.0.0.1:11434 >/dev/null && break; sleep 2; done
curl -sf http://127.0.0.1:11434 >/dev/null || { echo "ERROR: Ollama did not start; see /workspace/ollama.log"; exit 1; }

echo "==> Pulling Qwen models (first run downloads ~14 GB)"
ollama pull qwen2.5-coder:14b-instruct
[ "${PULL_7B:-1}" = "1" ] && ollama pull qwen2.5-coder:7b-instruct
[ "${PULL_32B:-0}" = "1" ] && ollama pull qwen2.5-coder:32b-instruct

echo "==> Installing code-server extensions"
for ext in muhammad-sammy.csharp llvm-vs-code-extensions.vscode-clangd sumneko.lua ms-python.python \
           eamodio.gitlens ms-vscode.hexeditor esbenp.prettier-vscode; do
  code-server --extensions-dir /workspace/code-server/extensions --install-extension "$ext" >/dev/null 2>&1 \
    && echo "    $ext" || echo "    WARN: could not install $ext"
done

echo
echo "==> Done."
echo "    code-server: RunPod Connect -> HTTP Services -> port 8080"
echo "    password:    $(cat /workspace/code-server/password)"
echo "    next:        source ~/.bashrc && newmod.sh Game_A && mod Game_A"
echo "    after every pod restart: bash /workspace/scripts/post_restart.sh"
