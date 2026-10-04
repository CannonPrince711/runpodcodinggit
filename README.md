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

## Files

- `install.sh` — full setup, safe to re-run
- `install-oneliner.txt` — the same installer as one pasteable line (no download needed)
- `runpod-modding-setup.md` — the full guide
