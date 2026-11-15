# Security

Please report security problems privately through GitHub's **Report a vulnerability** button
(Security tab) instead of opening a public issue.

What the installer does that you should know about:

- It downloads executables and model files from GitHub (Comfy-Org, OpenLayer, custom node
  repositories) and Hugging Face. Files with a published SHA256 are verified; custom node
  repositories are cloned at their default branch and run their own `install.py` if present.
- ComfyUI is started bound to `127.0.0.1` only.
- It never asks for, stores or transmits credentials. `HF_TOKEN` / `GITHUB_TOKEN`, if set, are
  only sent to their own services.
