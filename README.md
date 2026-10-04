# RunPod Game Modding Workstation

code-server + Aider + Qwen2.5-Coder (via Ollama) on a RunPod RTX A5000. No JupyterLab.

## Install

In the pod's terminal (network volume mounted at `/workspace`):

```bash
curl -fsSL https://raw.githubusercontent.com/CannonPrince711/runpodcodinggit/main/install.sh | bash
```

Optional settings, set before running:

```bash
export GIT_NAME="Your Name" GIT_EMAIL="you@example.com"   # git identity for Aider commits
```

If the repo is private, paste the line from `install-oneliner.txt` instead.

After every pod restart:

```bash
bash /workspace/scripts/post_restart.sh
```

## Windows 11 (Shadow PC or any PC with an NVIDIA GPU)

Same tools without RunPod: VS Code (desktop) + Continue, Aider, Qwen Code, and Ollama running Qwen2.5-Coder 14B at a 32k context. Open a normal PowerShell window (not admin), click Yes on any Windows prompts, and run:

```powershell
irm https://raw.githubusercontent.com/CannonPrince711/runpodcodinggit/main/install.ps1 | iex
```

Optional, run first in the same window:

```powershell
$env:GIT_NAME="Your Name"; $env:GIT_EMAIL="you@example.com"
```

Mods go in `C:\mods`; configs and helper scripts in `C:\modtools`. Then open a new PowerShell window and use `newmod Game_A`, `mod Game_A` (Aider), `qmod Game_A` (Qwen Code) and `code C:\mods`. Nothing needs running after a reboot. Section 17 of the guide has the details.

## Files

- `install.sh` — full setup, safe to re-run
- `install.ps1` — Windows 11 setup, safe to re-run
- `install-oneliner.txt` — the same installer as one pasteable line (no download needed)
- `runpod-modding-setup.md` — the full guide
