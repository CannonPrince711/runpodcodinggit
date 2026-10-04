# Windows 11 modding workstation installer: VS Code + Ollama/Qwen + Aider + Qwen Code. No JupyterLab.
# Windows version of install.sh, made for a Shadow PC Power (RTX A4500 20 GB) but fine on any
# Windows 11 PC with an NVIDIA GPU. Safe to re-run.
#
# Run in a normal (not admin) PowerShell window and click Yes on any Windows prompts:
#   irm https://raw.githubusercontent.com/CannonPrince711/runpodcodinggit/main/install.ps1 | iex
# Optional, set first:
#   $env:GIT_NAME="Your Name"; $env:GIT_EMAIL="you@example.com"   # git identity for Aider commits
#   $env:MODS_DIR="D:\mods"; $env:MODTOOLS_DIR="D:\modtools"       # defaults: C:\mods, C:\modtools

& {
$ErrorActionPreference = 'Continue'   # native tools write to stderr; failures are checked by exit code
$ProgressPreference = 'SilentlyContinue'

$Mods  = if ($env:MODS_DIR) { $env:MODS_DIR.TrimEnd('\') } else { 'C:\mods' }
$Tools = if ($env:MODTOOLS_DIR) { $env:MODTOOLS_DIR.TrimEnd('\') } else { 'C:\modtools' }
$ToolsFwd = $Tools -replace '\\', '/'
$Model = 'qwen2.5-coder:14b-instruct'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Note($msg) { Write-Host "    $msg" }
function Write-Utf8($path, $text) {   # UTF-8 without BOM (YAML and some tools choke on a BOM)
  $dir = Split-Path $path -Parent
  if ($dir -and !(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}
function Fill($text) { $text.Replace('__TOOLSFWD__', $ToolsFwd).Replace('__TOOLS__', $Tools).Replace('__MODS__', $Mods) }
function Update-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Add-UserPath($dir) {
  $p = [Environment]::GetEnvironmentVariable('Path', 'User'); if (!$p) { $p = '' }
  if (($p -split ';') -notcontains $dir) { [Environment]::SetEnvironmentVariable('Path', (($p.TrimEnd(';') + ';' + $dir).TrimStart(';')), 'User') }
  if (($env:Path -split ';') -notcontains $dir) { $env:Path += ";$dir" }
}
function Install-Pkg($id, $name) {
  winget list --id $id -e --accept-source-agreements *> $null
  if ($LASTEXITCODE -eq 0) { Write-Note "${name}: already installed"; return }
  Write-Note "${name}: installing..."
  winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
  if ($LASTEXITCODE -ne 0) { Write-Warning "winget could not install $name ($id), exit code $LASTEXITCODE" }
}
function Find-Exe($names, $fallbacks) {
  foreach ($n in $names) { $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { return $c.Source } }
  foreach ($f in $fallbacks) { if ($f -and (Test-Path -LiteralPath $f)) { return $f } }
  return $null
}
function Read-Json($path) {   # tolerates whole-line // comments (VS Code adds one to keybindings.json)
  if (!(Test-Path -LiteralPath $path)) { return $null }
  $t = [IO.File]::ReadAllText($path)
  $t = ($t -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
  if (!$t.Trim()) { return $null }
  return (ConvertFrom-Json -InputObject $t)
}
function Set-Prop($obj, $name, $value) {
  if ($obj.PSObject.Properties[$name]) { $obj.$name = $value } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
function Merge-Prop($obj, $name, $hash) {
  $cur = $obj.$name
  if ($null -eq $cur) { $cur = New-Object PSObject; Set-Prop $obj $name $cur }
  foreach ($k in $hash.Keys) { Set-Prop $cur $k $hash[$k] }
}

try {
# --- 0. Checks ---
Write-Step 'Checking this PC'
if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "winget not found. Install or update 'App Installer' from the Microsoft Store, then run this again."
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) { Write-Warning 'This window is running as administrator. A normal window is better (VS Code and Ollama install per user).' }
$smi = Find-Exe @('nvidia-smi') @("$env:SystemRoot\System32\nvidia-smi.exe")
if ($smi) { $gpu = & $smi --query-gpu=name,memory.total --format=csv,noheader 2>$null; Write-Note "GPU: $gpu" }
else { Write-Warning 'nvidia-smi not found: is the NVIDIA driver installed? Qwen will be very slow on CPU.' }

# PowerShell blocks profile scripts by default on Windows 11 Home; the mod/newmod/qmod commands need them
$pol = Get-ExecutionPolicy -Scope CurrentUser
if ($pol -in 'Undefined', 'Restricted', 'AllSigned') {
  try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop; Write-Note 'PowerShell script policy (current user): RemoteSigned' }
  catch { Write-Warning "Could not set the PowerShell script policy: $($_.Exception.Message)" }
}

# --- 1. Folders ---
Write-Step "Creating folders ($Mods, $Tools)"
foreach ($d in @("$Mods\shared-libraries", "$Tools\scripts", "$Tools\docs", "$Tools\downloads",
                 "$Tools\ai\aider", "$Tools\ai\rules", "$Tools\ai\prompts", "$Tools\ai\context", "$Tools\ai\continue")) {
  New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# --- 2. Environment variables (user level; Ollama reads them when it starts) ---
Write-Step 'Setting environment variables'
$vars = [ordered]@{
  OLLAMA_API_BASE           = 'http://127.0.0.1:11434'
  OLLAMA_KEEP_ALIVE         = '30m'
  OLLAMA_MAX_LOADED_MODELS  = '1'       # only one model in VRAM at a time
  OLLAMA_NUM_PARALLEL       = '1'
  OLLAMA_CONTEXT_LENGTH     = '32768'   # default ctx for clients that can't set it (Qwen Code)
  OPENAI_BASE_URL           = 'http://127.0.0.1:11434/v1'   # Qwen Code -> local Ollama
  OPENAI_API_KEY            = 'ollama'
  OPENAI_MODEL              = $Model
  AIDER_MODEL_SETTINGS_FILE = "$Tools\ai\aider\.aider.model.settings.yml"
  MODS_DIR                  = $Mods
  MODTOOLS_DIR              = $Tools
}
foreach ($k in $vars.Keys) {
  [Environment]::SetEnvironmentVariable($k, $vars[$k], 'User')
  Set-Item -Path "env:$k" -Value $vars[$k]
}

# --- 3. Programs (winget) ---
Write-Step 'Installing programs with winget (first run downloads ~1.5 GB)'
Install-Pkg 'Git.Git'                   'Git'
Install-Pkg 'BurntSushi.ripgrep.MSVC'   'ripgrep'
Install-Pkg 'Microsoft.DotNet.SDK.8'    '.NET SDK 8'
Install-Pkg 'OpenJS.NodeJS.LTS'         'Node.js LTS'
Install-Pkg 'astral-sh.uv'              'uv (Python manager for Aider)'
Install-Pkg 'Microsoft.VisualStudioCode' 'VS Code'
Install-Pkg 'Ollama.Ollama'             'Ollama'
Update-Path

$git = Find-Exe @('git') @("$env:ProgramFiles\Git\cmd\git.exe")
if (!$git) { throw 'Git is not installed; see the winget messages above.' }

# --- 4. Git ---
Write-Step 'Configuring git'
$curName = & $git config --global user.name
if ($env:GIT_NAME -or !$curName) { & $git config --global user.name $(if ($env:GIT_NAME) { $env:GIT_NAME } else { 'YourName' }) }
$curMail = & $git config --global user.email
if ($env:GIT_EMAIL -or !$curMail) { & $git config --global user.email $(if ($env:GIT_EMAIL) { $env:GIT_EMAIL } else { 'you@example.com' }) }
& $git config --global init.defaultBranch main
& $git config --global core.longpaths true   # decompiled games have deep paths
Write-Note ("identity: " + (& $git config --global user.name) + " <" + (& $git config --global user.email) + ">")

# --- 5. Aider (own Python 3.12, managed by uv) ---
Write-Step 'Installing Aider'
$uv = Find-Exe @('uv') @("$env:USERPROFILE\.local\bin\uv.exe", "$env:LOCALAPPDATA\Microsoft\WinGet\Links\uv.exe")
if (!$uv) {
  Write-Note 'uv not found via winget; using the official uv installer'
  Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
  Update-Path
  $uv = Find-Exe @('uv') @("$env:USERPROFILE\.local\bin\uv.exe")
}
if (!$uv) { throw 'uv could not be installed, so Aider cannot be installed.' }
$uvBin = (& $uv tool dir --bin).Trim()
Add-UserPath $uvBin
if (Test-Path -LiteralPath "$uvBin\aider.exe") { Write-Note 'aider: already installed (update with: uv tool upgrade aider-chat)' }
else {
  & $uv tool install --force --python 3.12 --with pip aider-chat@latest
  if ($LASTEXITCODE -ne 0) { Write-Warning 'Aider install failed; see the messages above.' }
}

# --- 6. Qwen Code (terminal agent, like Aider) ---
Write-Step 'Installing Qwen Code'
$npm = Find-Exe @('npm.cmd') @("$env:ProgramFiles\nodejs\npm.cmd")
Add-UserPath "$env:APPDATA\npm"
if (Test-Path -LiteralPath "$env:APPDATA\npm\qwen.cmd") { Write-Note 'qwen: already installed' }
elseif ($npm) {
  & $npm install -g --no-fund --no-audit '@qwen-code/qwen-code'
  if ($LASTEXITCODE -ne 0) { Write-Warning 'Qwen Code install failed; see the messages above.' }
}
else { Write-Warning 'npm not found, so Qwen Code was skipped. Re-run this installer after Node.js installs.' }

# --- 7. Configs, rules and helper scripts ---
Write-Step "Writing configs and helper scripts to $Tools"

Write-Utf8 "$Tools\ai\aider\.aider.model.settings.yml" (Fill @'
- name: ollama_chat/qwen2.5-coder:14b-instruct
  edit_format: diff
  use_repo_map: true
  examples_as_sys_msg: true
  extra_params:
    num_ctx: 32768
'@)

Write-Utf8 "$Tools\ai\aider\.aider.conf.yml" (Fill @'
model: ollama_chat/qwen2.5-coder:14b-instruct
weak-model: ollama_chat/qwen2.5-coder:14b-instruct
model-settings-file: __TOOLSFWD__/ai/aider/.aider.model.settings.yml

read:
  - __TOOLSFWD__/ai/rules/MODDING_RULES.md

auto-commits: true
attribute-author: false
gitignore: true
dark-mode: true
stream: true
cache-prompts: true
'@)

Write-Utf8 "$Tools\ai\rules\MODDING_RULES.md" @'
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
6. Wrap patch bodies in try/catch and log via the plugin logger: an unhandled exception in a patch can hard-crash the game.
7. All tunables go in a BepInEx ConfigEntry, not hardcoded constants.
8. Keep namespaces unique per mod. Never reuse a game's own namespace.
9. One feature per change. Do not refactor unrelated code.

## Output
- Complete compilable files, not fragments.
- Include required `using` directives.
- Note any new assembly references needed in the .csproj.
- State target framework if it matters (netstandard2.1 / net472 / net6.0).
'@

$continueCfg = Fill @'
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
  - Follow the modding rules in __TOOLSFWD__/ai/rules/MODDING_RULES.md
'@
Write-Utf8 "$Tools\ai\continue\config.yaml" $continueCfg
# Continue reads ~/.continue/config.yaml; replace it only if it is ours (or missing)
$cc = "$env:USERPROFILE\.continue\config.yaml"
if (!(Test-Path -LiteralPath $cc) -or ([IO.File]::ReadAllText($cc) -match '^name: Local Qwen')) { Write-Utf8 $cc $continueCfg }
else { Write-Note "kept your own $cc (ours is in $Tools\ai\continue\config.yaml)" }

# Find a mod folder by path, by name directly in the mods folder, or by name at any depth below it
Write-Utf8 "$Tools\scripts\resolve-mod.ps1" (Fill @'
param([string]$Name)
$Mods = '__MODS__'
if (!$Name) { return }
if (Test-Path -LiteralPath $Name -PathType Container) { return (Resolve-Path -LiteralPath $Name).Path }
$p = Join-Path $Mods $Name
if (Test-Path -LiteralPath $p -PathType Container) { return $p }
# Breadth-first, 6 levels, skipping folders that are never projects
$level = @(Get-Item -LiteralPath $Mods -ErrorAction SilentlyContinue)
for ($depth = 0; $depth -lt 6 -and $level.Count -gt 0; $depth++) {
  $next = @()
  foreach ($d in $level) {
    foreach ($c in @(Get-ChildItem -LiteralPath $d.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
      if ($c.Name -in '.git', 'Decompiled', 'bin', 'obj', 'node_modules', '.gradle', 'build') { continue }
      if ($c.Name -eq $Name) { return $c.FullName }
      $next += $c
    }
  }
  $level = $next
}
'@)

# Print the project folder containing a path: nearest folder with .git or CONVENTIONS.md, then one with a build file
Write-Utf8 "$Tools\scripts\find-project.ps1" (Fill @'
param([string]$Start = (Get-Location).Path)
$Mods = '__MODS__'.TrimEnd('\')
$s = (Resolve-Path -LiteralPath $Start -ErrorAction SilentlyContinue).Path
if (!$s) { return }
if (Test-Path -LiteralPath $s -PathType Leaf) { $s = Split-Path $s -Parent }
$build = '^(build\.gradle(\.kts)?|settings\.gradle(\.kts)?|gradlew|pom\.xml|.*\.sln|.*\.csproj|cmakelists\.txt|package\.json)$'
foreach ($pass in 'repo', 'build') {
  $d = $s
  while ($d -and $d.TrimEnd('\') -ne $Mods) {
    if ($pass -eq 'repo') {
      if ((Test-Path -LiteralPath (Join-Path $d '.git')) -or (Test-Path -LiteralPath (Join-Path $d 'CONVENTIONS.md'))) { return $d }
    } elseif (Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $build } | Select-Object -First 1) {
      return $d
    }
    $d = Split-Path $d -Parent
  }
}
'@)

# mod <GameName | folder name | path>: Aider in that mod's folder
Write-Utf8 "$Tools\scripts\mod.ps1" (Fill @'
param([string]$Name)
$Tools = '__TOOLS__'
if (!$Name) { Write-Host 'usage: mod <GameName | folder | path>'; return }
$dir = & "$Tools\scripts\resolve-mod.ps1" $Name
if (!$dir) { Write-Host "no such mod: $Name (run: newmod $Name)"; return }
$aider = Get-Command aider -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$aider) { Write-Host 'aider not found; run install.ps1 again'; return }
if (!(Test-Path -LiteralPath (Join-Path $dir '.git'))) { git -C $dir init -q }   # Aider needs a git repo
$a = @('--config', "$Tools\ai\aider\.aider.conf.yml")
if (Test-Path -LiteralPath (Join-Path $dir 'CONVENTIONS.md')) { $a += @('--read', 'CONVENTIONS.md') }
$a += '--watch-files'
Push-Location -LiteralPath $dir
try { & $aider.Source @a } finally { Pop-Location }
'@)

# newmod <GameName>: scaffold a mod workspace with git
Write-Utf8 "$Tools\scripts\newmod.ps1" (Fill @'
param([string]$Name)
$Mods = '__MODS__'
if (!$Name) { Write-Host 'usage: newmod <GameName>'; return }
$dir = Join-Path $Mods $Name
foreach ($sub in 'src', 'Decompiled', 'docs', 'refs') { New-Item -ItemType Directory -Force -Path (Join-Path $dir $sub) | Out-Null }
$enc = New-Object System.Text.UTF8Encoding $false
$ignore = @('bin/', 'obj/', '*.user', '*.suo', '*.dll', '*.pdb', '*.mdb', 'Decompiled/', 'refs/',
            '.aider.tags.cache.v*/', '.aider.chat.history.md', '.aider.input.history', '')
if (!(Test-Path -LiteralPath "$dir\.gitignore")) { [IO.File]::WriteAllText("$dir\.gitignore", ($ignore -join "`n"), $enc) }
$conv = @("# $Name - Mod Notes", '', '- Engine / version:', '- Mod loader:', '- Target framework:', '- Key assemblies:',
          '- Decompiled source: ./Decompiled  (read-only reference)', '- Source: ./src', '')
if (!(Test-Path -LiteralPath "$dir\CONVENTIONS.md")) { [IO.File]::WriteAllText("$dir\CONVENTIONS.md", ($conv -join "`n"), $enc) }
if (!(Test-Path -LiteralPath "$dir\.git")) { git -C $dir init -q }
git -C $dir add -A
git -C $dir commit -qm "init: $Name mod workspace" 2>$null
Write-Host "Created $dir"
'@)

# Aider for the project the current folder (or open file) is in; otherwise ask which one
Write-Utf8 "$Tools\scripts\aider-here.ps1" (Fill @'
$Tools = '__TOOLS__'; $Mods = '__MODS__'
$dir = & "$Tools\scripts\find-project.ps1" (Get-Location).Path
if (!$dir) {
  Write-Host "Projects in ${Mods}:"
  Get-ChildItem -LiteralPath $Mods -Recurse -Depth 5 -Force -ErrorAction SilentlyContinue |
    Where-Object { ($_.Name -in '.git', 'CONVENTIONS.md', 'build.gradle' -or $_.Name -like '*.sln') -and $_.FullName -notmatch '\\Decompiled\\' } |
    ForEach-Object { Split-Path $_.FullName -Parent } | Sort-Object -Unique |
    ForEach-Object { '  ' + $_.Substring($Mods.Length).TrimStart('\') }
  $dir = Read-Host 'Open Aider for which one (name or path)?'
}
if ($dir) { & "$Tools\scripts\mod.ps1" $dir }
'@)

# Commands for every PowerShell window (loaded from your PowerShell profile)
Write-Utf8 "$Tools\scripts\profile.ps1" (Fill @'
# Modding commands, written by install.ps1 (re-running it overwrites this file)
$ModsDir = '__MODS__'; $ModTools = '__TOOLS__'
function mods { Set-Location -LiteralPath $ModsDir }
function mod { & "$ModTools\scripts\mod.ps1" @args }
function newmod { & "$ModTools\scripts\newmod.ps1" @args }
function aider-here { & "$ModTools\scripts\aider-here.ps1" }
function qmod {   # Qwen Code in a mod folder (any depth)
  param([string]$Name)
  $d = & "$ModTools\scripts\resolve-mod.ps1" $Name
  if ($d) { Set-Location -LiteralPath $d; qwen } else { Write-Host "no such mod: $Name" }
}
function aider {   # plain `aider` also uses the Qwen config
  $exe = Get-Command aider -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (!$exe) { Write-Host 'aider not found; run install.ps1 again'; return }
  & $exe.Source --config "$ModTools\ai\aider\.aider.conf.yml" @args
}
function ollog { Get-Content "$env:LOCALAPPDATA\Ollama\server.log" -Tail 50 -Wait }
'@)

$docs = [Environment]::GetFolderPath('MyDocuments')   # follows OneDrive redirection
$hook = "if (Test-Path '$Tools\scripts\profile.ps1') { . '$Tools\scripts\profile.ps1' }"
foreach ($prof in @("$docs\WindowsPowerShell\Microsoft.PowerShell_profile.ps1", "$docs\PowerShell\Microsoft.PowerShell_profile.ps1")) {
  if ((Test-Path -LiteralPath $prof) -and ((Get-Content -LiteralPath $prof -Raw) -like "*$Tools\scripts\profile.ps1*")) { continue }
  New-Item -ItemType Directory -Force -Path (Split-Path $prof -Parent) | Out-Null
  Add-Content -LiteralPath $prof -Value "`r`n# Modding commands (mod, newmod, qmod, mods)`r`n$hook"
}
Write-Note 'commands added to your PowerShell profile: mod, newmod, qmod, mods, aider-here, ollog'

# --- 8. Ollama + Qwen ---
Write-Step 'Restarting Ollama with the new settings'
$ollama = Find-Exe @('ollama') @("$env:LOCALAPPDATA\Programs\Ollama\ollama.exe")
if (!$ollama) { throw 'Ollama is not installed; see the winget messages above.' }
Get-Process -Name 'ollama app', 'ollama' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$tray = Join-Path (Split-Path $ollama -Parent) 'ollama app.exe'
if (Test-Path -LiteralPath $tray) { Start-Process -FilePath $tray }   # tray app; also starts with Windows
else { Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden }
$up = $false
for ($i = 0; $i -lt 60 -and !$up; $i++) {
  try { Invoke-WebRequest -Uri 'http://127.0.0.1:11434' -UseBasicParsing -TimeoutSec 2 | Out-Null; $up = $true } catch { Start-Sleep -Seconds 2 }
}
if (!$up) { throw "Ollama did not start; see $env:LOCALAPPDATA\Ollama\server.log" }

Write-Step 'Pulling Qwen2.5-Coder 14B (first run downloads ~9 GB)'
& $ollama pull $Model
if ($LASTEXITCODE -ne 0) { Write-Warning 'Model download failed; run: ollama pull qwen2.5-coder:14b-instruct' }

Write-Step 'Checking Ollama uses the GPU'
& $ollama run $Model 'say ok' *> $null
$ps = (& $ollama ps) -join "`n"
if ($ps -match 'GPU') { Write-Note (($ps -split "`n")[1]) }
else { Write-Warning "Model is not on the GPU. Check nvidia-smi and $env:LOCALAPPDATA\Ollama\server.log" }

# --- 9. VS Code ---
Write-Step 'Installing VS Code extensions'
$code = Find-Exe @('code.cmd') @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd")
if ($code) {
  foreach ($ext in 'ms-dotnettools.csharp', 'ms-vscode.cpptools', 'sumneko.lua', 'ms-python.python',
                   'ms-vscode.hexeditor', 'Continue.continue') {
    & $code --install-extension $ext *> $null
    if ($LASTEXITCODE -eq 0) { Write-Note $ext } else { Write-Warning "could not install $ext" }
  }
} else { Write-Warning 'VS Code not found; extensions skipped.' }

Write-Step 'Writing VS Code settings, Aider task and shortcut'
$user = "$env:APPDATA\Code\User"
# Windows PowerShell 5.1 can write arrays as {"value":[...],"Count":n}; dropping this type data prevents it
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData System.Array -ErrorAction SilentlyContinue }
$aiderArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$Tools\scripts\aider-here.ps1")
try {
  $s = Read-Json "$user\settings.json"
  if ($null -eq $s) { $s = New-Object PSObject }
  if (!$s.PSObject.Properties['files.autoSave']) { Set-Prop $s 'files.autoSave' 'afterDelay' }
  if (!$s.PSObject.Properties['git.enableSmartCommit']) { Set-Prop $s 'git.enableSmartCommit' $true }
  $heavy = [ordered]@{ '**/Decompiled/**' = $true; '**/bin/**' = $true; '**/obj/**' = $true; '**/.git/objects/**' = $true
                       '**/.aider.tags.cache.v*/**' = $true; '**/.gradle/**' = $true; '**/build/**' = $true
                       '**/run/**' = $true; '**/node_modules/**' = $true }
  Merge-Prop $s 'files.watcherExclude' $heavy
  $searchEx = [ordered]@{}; foreach ($k in $heavy.Keys) { if ($k -notlike '*Decompiled*') { $searchEx[$k] = $true } }
  Merge-Prop $s 'search.exclude' $searchEx
  Merge-Prop $s 'files.exclude' ([ordered]@{ '**/.aider.tags.cache.v*' = $true })
  # "Aider" entry in the terminal panel's + dropdown
  Merge-Prop $s 'terminal.integrated.profiles.windows' ([ordered]@{ Aider = [ordered]@{ path = 'powershell.exe'; args = $aiderArgs; icon = 'hubot' } })
  Write-Utf8 "$user\settings.json" (ConvertTo-Json -InputObject $s -Depth 20)
} catch { Write-Warning "settings.json could not be read (comments?), so it was left alone: $($_.Exception.Message)" }

$label = 'Aider: open for this mod'
try {
  $t = Read-Json "$user\tasks.json"
  if ($null -eq $t) { $t = New-Object PSObject -Property @{ version = '2.0.0'; tasks = @() } }
  $task = [ordered]@{ label = $label; type = 'process'; command = 'powershell.exe'; args = $aiderArgs; problemMatcher = @()
                      presentation = [ordered]@{ reveal = 'always'; panel = 'dedicated'; focus = $true; clear = $true }
                      options = [ordered]@{ cwd = '${fileDirname}' } }
  Set-Prop $t 'tasks' (@(@($t.tasks) | Where-Object { $_ -and $_.label -ne $label }) + @($task))
  Write-Utf8 "$user\tasks.json" (ConvertTo-Json -InputObject $t -Depth 20)
} catch { Write-Warning "tasks.json could not be read, so it was left alone: $($_.Exception.Message)" }

try {
  $kb = @(Read-Json "$user\keybindings.json" | Where-Object { $_ })
  if (!($kb | Where-Object { $_.key -eq 'ctrl+alt+a' -and $_.command -eq 'workbench.action.tasks.runTask' })) {
    $kb += [pscustomobject][ordered]@{ key = 'ctrl+alt+a'; command = 'workbench.action.tasks.runTask'; args = $label }
  }
  Write-Utf8 "$user\keybindings.json" (ConvertTo-Json -InputObject @($kb) -Depth 10)
} catch { Write-Warning "keybindings.json could not be read, so it was left alone: $($_.Exception.Message)" }

Write-Host ''
Write-Step 'Done.'
Write-Note 'Open a NEW PowerShell window first (this one has old settings), then:'
Write-Note '  newmod Game_A        create C:\mods\Game_A with git'
Write-Note '  mod Game_A           Aider in that mod (any folder depth works: mod Villageoverhaul)'
Write-Note '  qmod Game_A          Qwen Code agent in that mod'
Write-Note "  code $Mods           VS Code on your mods folder"
Write-Note 'In VS Code: Continue icon in the left bar for Qwen chat (Ctrl+L, edit selection: Ctrl+I);'
Write-Note '  Ctrl+Alt+A or Terminal + dropdown -> Aider opens Aider for the open file''s mod;'
Write-Note '  comment "... AI!" in a file and save to trigger it.'
Write-Note 'Ollama starts with Windows (tray icon). Nothing to run after a reboot.'
} catch {
  Write-Host ''
  Write-Host "Install stopped: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'Fix that and run the same command again; finished steps are skipped.'
}
}
