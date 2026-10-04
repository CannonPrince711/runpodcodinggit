#!/bin/bash
# RunPod modding workstation installer: code-server + Ollama/Qwen + Aider. No JupyterLab.
# Safe to re-run. Optional: GIT_NAME="Me" GIT_EMAIL="me@x.com" bash install.sh
set -e
[ -d /workspace ] || { echo "ERROR: /workspace not found. Attach a network volume first."; exit 1; }
echo "==> Creating directories"
mkdir -p /workspace/{mods/shared-libraries,tools,scripts,docs,downloads}
mkdir -p /workspace/ai/{aider,rules,prompts,context}
mkdir -p /workspace/models/{ollama,huggingface}
mkdir -p /workspace/dev-env/{npm-cache,nuget}
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
# Rewritten every run so new settings reach existing pods; ~/.bashrc just sources it
mkdir -p /workspace/dev-env
cat > /workspace/dev-env/env.sh << 'VARS'
export WORKSPACE=/workspace
export OLLAMA_MODELS=/workspace/models/ollama
export HF_HOME=/workspace/models/huggingface
export HUGGINGFACE_HUB_CACHE=/workspace/models/huggingface/hub
export OLLAMA_API_BASE=http://127.0.0.1:11434
export OLLAMA_KEEP_ALIVE=30m
export OLLAMA_MAX_LOADED_MODELS=1   # only one model in VRAM at a time
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_CONTEXT_LENGTH=32768   # default ctx for clients that can't set it (Qwen Code)
export PATH=/opt/qwen-code/bin:/opt/node/bin:$PATH
export OPENAI_BASE_URL=http://127.0.0.1:11434/v1   # Qwen Code -> local Ollama
export OPENAI_API_KEY=ollama
export OPENAI_MODEL=qwen2.5-coder:14b-instruct
export npm_config_cache=/workspace/dev-env/npm-cache
export NUGET_PACKAGES=/workspace/dev-env/nuget
export AIDER_MODEL_SETTINGS_FILE=/workspace/ai/aider/.aider.model.settings.yml
alias aider='/opt/aider-env/bin/aider --config /workspace/ai/aider/.aider.conf.yml'
alias mod='bash /workspace/scripts/mod.sh'
qmod() { local d="$1"; [ -d "$d" ] || d="/workspace/mods/$1"; [ -d "$d" ] || d=$(find /workspace/mods -maxdepth 6 -type d -iname "$1" -not -path "*/.git/*" | head -1); [ -n "$d" ] && cd "$d" && qwen; }   # Qwen Code in a mod folder (any depth)
alias newmod='bash /workspace/scripts/newmod.sh'
alias newmod.sh='bash /workspace/scripts/newmod.sh'
alias ws='cd /workspace'
alias dl='cd /workspace/downloads'
alias cslog='tail -f /workspace/code-server.log'
alias cs-save='tar -cf /workspace/code-server/extensions.tar -C /opt/cs/ext . && echo saved code-server extensions'
alias ollog='tail -f /workspace/ollama.log'
VARS
grep -q 'dev-env/env.sh' ~/.bashrc 2>/dev/null || echo '[ -f /workspace/dev-env/env.sh ] && . /workspace/dev-env/env.sh' >> ~/.bashrc
# Also export for the processes this script starts (.bashrc returns early in non-interactive shells)
export OLLAMA_MODELS=/workspace/models/ollama
export OLLAMA_KEEP_ALIVE=30m
export OLLAMA_MAX_LOADED_MODELS=1   # only one model in VRAM at a time
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_CONTEXT_LENGTH=32768   # default ctx for clients that can't set it (Qwen Code)
export PATH=/opt/qwen-code/bin:/opt/node/bin:$PATH
export OPENAI_BASE_URL=http://127.0.0.1:11434/v1   # Qwen Code -> local Ollama
export OPENAI_API_KEY=ollama
export OPENAI_MODEL=qwen2.5-coder:14b-instruct
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
pgrep -x ollama >/dev/null || OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_NUM_PARALLEL=1 OLLAMA_CONTEXT_LENGTH=32768 nohup setsid ollama serve > /workspace/ollama.log 2>&1 &

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

# Qwen Code (terminal agent, like Aider) on Node 22, both under /opt, saved to /workspace like the rest
if [ ! -x /opt/qwen-code/bin/qwen ]; then
  restore qwen-code || true
  if [ ! -x /opt/qwen-code/bin/qwen ]; then
    echo "    installing qwen code..."
    mkdir -p /opt/node
    curl -fsSL https://nodejs.org/dist/v22.11.0/node-v22.11.0-linux-x64.tar.gz | tar -xz -C /opt/node --strip-components=1
    PATH=/opt/node/bin:$PATH npm install -g -q --no-fund --no-audit --cache /tmp/npm-cache \
      --prefix /opt/qwen-code @qwen-code/qwen-code \
      && save qwen-code /opt/node /opt/qwen-code || echo "    WARN: qwen code install failed"
  fi
fi

# Continue (Qwen chat + autocomplete inside code-server) reads ~/.continue, which a restart wipes
mkdir -p ~/.continue && cp /workspace/ai/continue/config.yaml ~/.continue/config.yaml 2>/dev/null || true
mkdir -p /workspace/code-server/data/User
# Speed: code-server's editor state and extensions run from the container disk (/opt/cs),
# not the slow network volume. Your settings/keybindings/tasks stay on /workspace (symlinked),
# and extensions are kept on /workspace as extensions.tar (save new ones with: cs-save).
CS=/opt/cs
mkdir -p $CS/data/User $CS/ext
for f in settings.json keybindings.json tasks.json; do
  [ -f /workspace/code-server/data/User/$f ] && ln -sfn /workspace/code-server/data/User/$f $CS/data/User/$f || true
done
if [ -z "$(ls -A $CS/ext)" ]; then
  if [ -f /workspace/code-server/extensions.tar ]; then
    tar -xf /workspace/code-server/extensions.tar -C $CS/ext
  elif [ -n "$(ls -A /workspace/code-server/extensions 2>/dev/null)" ]; then
    cp -r /workspace/code-server/extensions/. $CS/ext/ && tar -cf /workspace/code-server/extensions.tar -C $CS/ext .
  fi
fi
# Keep the password in a file on the volume instead of hardcoding it here
[ -f /workspace/code-server/password ] || { openssl rand -base64 18 > /workspace/code-server/password 2>/dev/null; }
pgrep -f "code-server.*--bind-addr" >/dev/null || \
  PASSWORD="$(cat /workspace/code-server/password)" nohup setsid code-server \
     --bind-addr 0.0.0.0:8080 --auth password \
     --user-data-dir $CS/data \
     --extensions-dir $CS/ext \
     /workspace/mods > /workspace/code-server.log 2>&1 &

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

cat > /workspace/scripts/find-project.sh << '__RPEOF_FP__'
#!/bin/bash
# Print the project folder that contains $1 (any depth under /workspace/mods).
# Prefers the nearest folder with .git or CONVENTIONS.md, then one with a build file.
start=$(cd "${1:-$PWD}" 2>/dev/null && pwd) || exit 1
for pass in repo build; do
  d=$start
  while [ "$d" != "/" ] && [ "$d" != "/workspace/mods" ] && [ "$d" != "/workspace" ]; do
    if [ $pass = repo ]; then
      { [ -e "$d/.git" ] || [ -f "$d/CONVENTIONS.md" ]; } && { echo "$d"; exit 0; }
    else
      ls "$d" 2>/dev/null | grep -qiE '^(build\.gradle(\.kts)?|settings\.gradle(\.kts)?|gradlew|pom\.xml|.*\.sln|.*\.csproj|cmakelists\.txt|package\.json)$' \
        && { echo "$d"; exit 0; }
    fi
    d=$(dirname "$d")
  done
done
exit 1
__RPEOF_FP__

cat > /workspace/scripts/aider-here.sh << '__RPEOF_AH__'
#!/bin/bash
# Open Aider for the project this terminal (or file) is in; otherwise ask which one.
DIR=$(bash /workspace/scripts/find-project.sh "$PWD")
if [ -z "$DIR" ]; then
  echo "Projects in /workspace/mods:"
  find /workspace/mods -maxdepth 5 \( -name .git -o -name CONVENTIONS.md -o -name build.gradle -o -name '*.sln' \) \
    -not -path '*/Decompiled/*' -printf '%h\n' 2>/dev/null | sort -u | sed 's#^/workspace/mods/#  #'
  read -r -p "Open Aider for which one (name or path)? " DIR
fi
[ -n "$DIR" ] && exec bash /workspace/scripts/mod.sh "$DIR"
__RPEOF_AH__

cat > /workspace/scripts/mod.sh << '__RPEOF2__'
#!/bin/bash
# Usage: mod <GameName | folder name | path>   (reattaches if already running)
ARG="$1"
[ -z "$ARG" ] && { echo "usage: mod <GameName | folder | path>"; exit 1; }
if [ -d "$ARG" ]; then
  DIR=$(cd "$ARG" && pwd)
elif [ -d "/workspace/mods/$ARG" ]; then
  DIR="/workspace/mods/$ARG"
else
  # Find a folder with that name anywhere under /workspace/mods (e.g. shared-libraries/minecraft/Villageoverhaul)
  DIR=$(find /workspace/mods -maxdepth 6 -type d -iname "$ARG" -not -path '*/.git/*' -not -path '*/Decompiled/*' 2>/dev/null | head -1)
fi
{ [ -z "$DIR" ] || [ ! -d "$DIR" ]; } && { echo "no such mod: $ARG (run: newmod.sh $ARG)"; exit 1; }

NAME=$(basename "$DIR")
SESSION="mod-${NAME//[^A-Za-z0-9_-]/_}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  exec tmux attach -t "$SESSION"
fi

READ=""
[ -f "$DIR/CONVENTIONS.md" ] && READ="--read ./CONVENTIONS.md"
tmux new-session -s "$SESSION" -c "$DIR" \
  "/opt/aider-env/bin/aider \
   --config /workspace/ai/aider/.aider.conf.yml \
   $READ \
   --watch-files"
__RPEOF2__

cat > /workspace/ai/aider/.aider.model.settings.yml << '__RPEOF3__'
- name: ollama/qwen2.5-coder:14b-instruct
  edit_format: diff
  use_repo_map: true
  examples_as_sys_msg: true
  extra_params:
    num_ctx: 32768


__RPEOF3__

cat > /workspace/ai/aider/.aider.conf.yml << '__RPEOF4__'
model: ollama/qwen2.5-coder:14b-instruct
weak-model: ollama/qwen2.5-coder:14b-instruct   # same model for commit messages, so nothing else loads
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

mkdir -p /workspace/ai/continue
cat > /workspace/ai/continue/config.yaml << '__RPEOF_C__'
name: Local Qwen
version: 1.0.0
schema: v1
models:
  - name: Qwen2.5-Coder 14B
    provider: ollama
    model: qwen2.5-coder:14b-instruct
    apiBase: http://127.0.0.1:11434
    roles: [chat, edit, apply, autocomplete]
    defaultCompletionOptions:
      contextLength: 32768
rules:
  - Follow the modding rules in /workspace/ai/rules/MODDING_RULES.md
__RPEOF_C__
mkdir -p ~/.continue && cp /workspace/ai/continue/config.yaml ~/.continue/config.yaml

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

[ -s /workspace/code-server/data/User/settings.json ] || cat > /workspace/code-server/data/User/settings.json << '__RPEOF_S__'
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

# Aider inside code-server: a task + Ctrl+Alt+A shortcut (only written if you don't have your own)
[ -s /workspace/code-server/data/User/tasks.json ] || cat > /workspace/code-server/data/User/tasks.json << '__RPEOF_T__'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Aider: open for this mod",
      "type": "shell",
      "command": "bash /workspace/scripts/aider-here.sh",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "dedicated",
        "focus": true,
        "clear": true
      },
      "options": {
        "cwd": "${fileDirname}"
      }
    }
  ]
}
__RPEOF_T__
[ -s /workspace/code-server/data/User/keybindings.json ] || cat > /workspace/code-server/data/User/keybindings.json << '__RPEOF_K__'
[
  {
    "key": "ctrl+alt+a",
    "command": "workbench.action.tasks.runTask",
    "args": "Aider: open for this mod"
  }
]
__RPEOF_K__

# Speed: stop code-server watching/indexing models, caches and decompiled code on the network volume.
# Merged into settings.json even if you already have one (skipped if it contains comments).
# Update the Aider task in an existing tasks.json
python3 - << '__RPEOF_TM__' || true
import json
p = "/workspace/code-server/data/User/tasks.json"
want = json.loads(r'''{"label": "Aider: open for this mod", "type": "shell", "command": "bash /workspace/scripts/aider-here.sh", "problemMatcher": [], "presentation": {"reveal": "always", "panel": "dedicated", "focus": true, "clear": true}, "options": {"cwd": "${fileDirname}"}}''')
try:
    t = json.load(open(p))
except Exception:
    raise SystemExit(0)
t["tasks"] = [x for x in t.get("tasks", []) if x.get("label") != want["label"]] + [want]
json.dump(t, open(p, "w"), indent=2)
__RPEOF_TM__
# Browser-safe Continue shortcuts (browsers grab Ctrl+L / Ctrl+I). Merged into keybindings.json.
python3 - << '__RPEOF_KB__' || echo "    NOTE: keybindings.json has comments; add Alt+L / Alt+I for Continue by hand"
import json
p = "/workspace/code-server/data/User/keybindings.json"
try:
    kb = json.load(open(p))
except FileNotFoundError:
    kb = []
want = [
    {"key": "alt+l", "command": "continue.focusContinueInput"},
    {"key": "alt+a", "command": "workbench.action.tasks.runTask", "args": "Aider: open for this mod"},
    {"key": "alt+i", "command": "continue.focusEdit", "when": "editorTextFocus"},
    {"key": "alt+i", "command": "continue.quickEdit", "when": "editorTextFocus"},
]
have = {(k.get("key"), k.get("command")) for k in kb}
kb += [w for w in want if (w["key"], w["command"]) not in have]
json.dump(kb, open(p, "w"), indent=2)
__RPEOF_KB__

python3 - << '__RPEOF_PY__' || echo "    NOTE: settings.json has comments; add the speed settings from the guide by hand"
import json
p = "/workspace/code-server/data/User/settings.json"
s = json.load(open(p))
heavy = {"/workspace/models/**": True, "/workspace/dev-env/**": True, "/workspace/code-server/**": True,
         "/workspace/downloads/**": True, "**/Decompiled/**": True, "**/bin/**": True, "**/obj/**": True,
         "**/.git/objects/**": True, "**/.aider.tags.cache.v*/**": True}
s.setdefault("files.watcherExclude", {}).update(heavy)
s.setdefault("search.exclude", {}).update({k: v for k, v in heavy.items() if "Decompiled" not in k})
s["search.followSymlinks"] = False
s["git.autoRepositoryDetection"] = "openEditors"
s["extensions.autoUpdate"] = False
# "Aider" entry in the terminal panel's + dropdown
s.setdefault("terminal.integrated.profiles.linux", {})["Aider"] = {"path": "bash", "args": ["/workspace/scripts/aider-here.sh"], "icon": "hubot"}
s["gitlens.codeLens.enabled"] = False
json.dump(s, open(p, "w"), indent=2)
__RPEOF_PY__

# No chmod: the network volume refuses it, so scripts are always run with bash

echo "==> Installing packages and starting services (post_restart.sh)"
bash /workspace/scripts/post_restart.sh

export OLLAMA_MODELS=/workspace/models/ollama
echo "==> Waiting for Ollama"
for i in $(seq 1 60); do curl -sf http://127.0.0.1:11434 >/dev/null && break; sleep 2; done
curl -sf http://127.0.0.1:11434 >/dev/null || { echo "ERROR: Ollama did not start; see /workspace/ollama.log"; exit 1; }

echo "==> Pulling Qwen models (first run downloads ~9 GB)"
ollama pull qwen2.5-coder:14b-instruct

echo "==> Checking Ollama sees the GPU"
ollama run qwen2.5-coder:14b-instruct "say ok" >/dev/null 2>&1 || true
if ollama ps | grep -q "GPU"; then
  ollama ps | sed -n 2p | sed 's/^/    /'
else
  echo "    WARN: model is not on the GPU. Check: nvidia-smi, and grep -i 'inference compute' /workspace/ollama.log"
fi

echo "==> Installing code-server extensions"
# Lean set: GitLens and Prettier were dropped because they slow down page load
for ext in muhammad-sammy.csharp llvm-vs-code-extensions.vscode-clangd sumneko.lua ms-python.python \
           ms-vscode.hexeditor Continue.continue; do
  code-server --extensions-dir /opt/cs/ext --install-extension "$ext" >/dev/null 2>&1 \
    && echo "    $ext" || echo "    WARN: could not install $ext"
done
tar -cf /workspace/code-server/extensions.tar -C /opt/cs/ext . && echo "    saved extensions to /workspace/code-server/extensions.tar"

echo
echo "==> Done."
echo "    code-server: RunPod Connect -> HTTP Services -> port 8080"
echo "    password:    $(cat /workspace/code-server/password)"
echo "    Aider in the editor: open a file in a mod, press Ctrl+Alt+A or Alt+A, or Terminal + dropdown -> Aider; comment \"... AI!\" and save to trigger it"
echo "    Qwen Code agent: qmod Game_A   (or: cd /workspace/mods/Game_A && qwen)"
echo "    Qwen in the editor: click the Continue icon in the left sidebar (chat: Alt+L, edit selection: Alt+I)"
echo "    next:        source ~/.bashrc && newmod.sh Game_A && mod Game_A"
echo "    after every pod restart: bash /workspace/scripts/post_restart.sh"
