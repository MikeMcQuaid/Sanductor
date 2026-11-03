# 🪪 Sanductor

Sanductor (formerly AgentIDE) is a free, native macOS app for running parallel coding agents and maintaining GitHub projects.
[`sandvault`][sv] runs agents as a separate non-admin macOS user with a clean environment, keeping your home, GitHub credentials and inherited secrets out of reach without agent permission prompts.
Once set up, go from a GitHub issue or security advisory to a merged pull request with clicks alone.

## 💡 Motivation

I lead [Homebrew] and [treat coding agents as untrusted](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/), keeping my credentials and signing keys out of their reach.
My [coding workflow](https://mikemcquaid.com/vibe-coding-developer-productivity-tools/) fits in one app, from prompt to merged pull request.
No Sanductor account, subscription or hosted relay exists or is planned.

![The worktree sidebar, an agent's terminal and its review beside it](docs/screenshot.png)

## ✨ Features

- Runs [Codex CLI] or [Claude Code] in parallel [worktrees](https://git-scm.com/docs/git-worktree) as a sandboxed non-admin macOS user, without containers or virtual machines.
- Reviews changes with fresh agent sessions, [CodeRabbit](https://www.coderabbit.ai) or [Copilot](https://docs.github.com/copilot/code-review), including findings outside the diff.
- Copies reviews and failed CI logs for pasting into agents, with opt-in autofix and local conflict recovery that resume after relaunch.
- Keeps signing and pushing under your control, with rebasing, stacked PRs, labels, merge queues, automerge and cleanup.
- Keeps agents running and reachable over SSH after quitting, with private backups and 30-day retention that preserves ongoing work.
- Starts from prompts, issues, branches, existing PRs or unpublished security advisories.
- Schedules repository prompts daily, weekly or monthly while open.
- Tracks agents, PRs and blockers by repository or status, with bulk worktree actions and notifications.
- Edits code with syntax highlighting, fuzzy file search and shell tabs.
- Starts tasks and checks blockers through Shortcuts and Siri, with an [iPhone companion](#-iphone-companion-app) and agent shortcut keys.

## 📋 Requirements

- An Apple silicon Mac running macOS Tahoe (26) or later.
- [Homebrew], [Git](https://git-scm.com), [`gh`][gh], [`herdr`][herdr] and [`ripgrep`](https://github.com/BurntSushi/ripgrep).
- [`sandvault`][sv] 1.29 or later.
- A [Codex CLI] or [Claude Code] account.

## 📦 Installation

```bash
brew install --cask sanductor
```

Update with [`brew upgrade`][Homebrew] (recommended), or unzip a signed [release](https://github.com/MikeMcQuaid/Sanductor/releases) into /Applications.

### 🎬 Getting started

Follow Sanductor’s checks; run setup commands in your normal terminal.
Run [`brew install`][Homebrew] [`sandvault`][sv], then [`sv build`][sv] and authorise setup.
This creates the non-admin account `sandvault-<you>` and shared workspace `/Users/Shared/sv-<you>`; `<you>` is your macOS username.
Run [`gh auth login`][gh] as yourself, then [`sv codex`][sv] or [`sv claude`][sv] to sign in; quit the agent and click "Recheck".
[`sv`][sv] uses the sandbox account, with its own agent login.
After setup, a short tour names both accounts and explains the panes.

Add a repository in the sidebar and start an agent in its own worktree.
Choose repository paths inside the workspace in Settings → Advanced.
Symlinks can point here but cannot grant access outside the workspace.
The centre terminal uses `sandvault-<you>`; Shell uses your account.
Bootstrap shared dependencies in Shell from the main checkout.
Agents cannot [`/opt/homebrew/bin/brew install`][Homebrew]; bootstrap shared dependencies as yourself.
Agents survive quitting via [`herdr`][herdr]; Shell tabs close.
Agents can change shared files and upload readable code; [review their work](https://mikemcquaid.com/why-open-source-maintainers-thrive-in-the-llm-era/) before trusting it.
Follow setup's keychain guidance; never reset your main user's keychain.
For permission popups see [`sandvault` recovery](https://github.com/webcoyote/sandvault#fix-the-security-popup).

Upgrading from the former app preserves settings and conversations; keep old session files, update custom app paths and repeat iPhone setup.

## ⚙️ Configuration

Settings (Cmd-,):

- **General**: Choose session defaults, signing and the browser.
- **Work**: Hide selected organisations on Mac and iPhone outside working hours while schedules continue.
- **Schedules**: Manage jobs, preview masked tokens or start jobs now.
- **Sessions**: Inspect and stop agents and browser pages.
- **Review**: Choose reviewers, models, effort and review or fix prompts.
- **Notifications**: Set alerts, private sounds and a Dock badge.
- **Fonts**: Customise fonts and sizes.
- **Editor**: Choose the external editor opened with Cmd-click.
- **Advanced**: Set paths, refresh intervals, idle sleep and logging.

Use `sanductor .` for a worktree or `sanductor /some/file` for a file.
In Shell, set Sanductor as your editor in your shell configuration:

```bash
if [ -n "${SANDUCTOR}" ]; then
  export EDITOR="$(command -v sanductor) --wait"
  export VISUAL="${EDITOR}"
fi
```

## 📱 iPhone companion app

For iOS 26+, run `script/bootstrap` and `script/install` in a source checkout and build `Sanductor-iOS` in Xcode with your signing team.

1. Copy the public key from iPhone Settings to your Mac's clipboard, then install it for the `sandvault-<you>` user:

   ```bash
   mkdir -p ~/.config/codeofhonor/sandvault/authorized_keys.d
   pbpaste >~/.config/codeofhonor/sandvault/authorized_keys.d/sanductor-phone
   sv build
   ```

   Delete that file and run [`sv build`][sv] to revoke the key.

2. Put this in `/etc/ssh/sshd_config.d/000-sanductor.conf` with your username and workspace path; enable Remote Login for `sandvault-<you>`:

   ```text
   Match User sandvault-<you>
       SetEnv SHARED_WORKSPACE=/Users/Shared/sv-<you>
   ```

3. Enter your Mac's address and username; `sandvault-` is added.
   Use port `22` locally or via VPN; for public access, forward another external router port to Mac port `22` with key-only authentication.
   Select `sanductor` (installed app) or `sanductor-dev` (development).
   Choose **Connect** and verify the host key against `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on your Mac.
   A changed key must be explicitly replaced in Settings.

## 🛠️ Development

Xcode 27.2 or later is needed to build from source.
Use `script/build`, `script/test`, `script/style --fix` and `script/analyze` for [development](ARCHITECTURE.md#dependencies-and-toolchain).
Quit the app and run `script/tutorial` to replay the opening tour without resetting settings.
See the [release process](ARCHITECTURE.md#releases) for publishing.

## 📄 Licence and contact

[AGPL-3.0](LICENSE); personal software without support or compatibility guarantees.
[Contact Mike McQuaid](mailto:mike@mikemcquaid.com).
Vendored [Octicons](https://github.com/primer/octicons) use the [MIT License](https://github.com/primer/octicons/blob/main/LICENSE).

[Codex CLI]: https://github.com/openai/codex
[Claude Code]: https://code.claude.com/docs
[Homebrew]: https://brew.sh
[sv]: https://github.com/webcoyote/sandvault
[gh]: https://cli.github.com
[herdr]: https://herdr.dev
