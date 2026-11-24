# 🪪 Sanductor

Sanductor (formerly AgentIDE) is a free, native macOS app for running parallel coding agents and maintaining GitHub projects.
[`sandvault`][sv] runs agents as a non-admin macOS user without permission prompts or access to your home, credentials or environment.
Agents can read public repositories but have no GitHub credentials.
Go from a GitHub issue or advisory to a merged PR with clicks alone.

## 💡 Motivation

I lead [Homebrew] and [treat coding agents as untrusted](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/).
I [write and review my own PRs](https://mikemcquaid.com/vibe-coding-developer-productivity-tools/) in Sanductor.
I review other people's PRs in GitHub.
No Sanductor account, subscription or hosted relay exists or is planned.

![The sidebar, an agent's terminal and its review](docs/screenshot.png)

## ✨ Features

- Runs [Codex CLI] or [Claude Code] in parallel [worktrees](https://git-scm.com/docs/git-worktree) as a sandboxed non-admin macOS user, without containers or virtual machines.
- Reviews changes with fresh agent sessions, [CodeRabbit](https://www.coderabbit.ai) or [Copilot](https://docs.github.com/copilot/code-review), including findings outside the diff.
- Copies feedback with its stack, bulk-resolves reviews and reruns CI.
- Opt-in autofix feeds reviews, CI failures and merge conflicts back to agents, resumes after relaunch and never signs or pushes.
- Signs and pushes from any published stack layer, with rebasing, labels, merge queues, automerge and branch and temporary file cleanup.
- Keeps agents running and reachable over SSH after quitting, with private backups and 30-day retention that preserves ongoing work.
- Saves prompts, attaches files and schedules recurring tasks per repo.
- Groups work by repository or latest event, with unpushed commits, CI, reviews, dated blockers, bulk actions and alerts.
- Edits code with syntax highlighting, fuzzy file search and shell tabs.
- Starts tasks and checks blockers through Shortcuts and Siri, with an [iPhone companion](#-iphone-companion-app) and agent shortcut keys.

## 📋 Requirements

- An Apple silicon Mac running macOS Tahoe (26) or later.
- [Homebrew], [Git](https://git-scm.com), [`gh`][gh], [`herdr`][herdr] and [`ripgrep`](https://github.com/BurntSushi/ripgrep).
- [`sandvault`][sv] 1.29 or later.
- A [Codex CLI] or [Claude Code] account.

## 📦 Installation

```bash
brew install sanductor
```

Or unzip a [signed release](https://github.com/MikeMcQuaid/Sanductor/releases) into /Applications.

### 🎬 Getting started

Follow Sanductor’s checks; run setup commands in your normal terminal.
The centre terminal uses `sandvault-<you>`; Shell uses your account.
Run [`brew install`][Homebrew] [`sandvault`][sv], then [`sv build`][sv] and authorise setup.
This creates the non-admin account `sandvault-<you>` and shared workspace `/Users/Shared/sv-<you>`; `<you>` is your macOS username.
Run [`gh auth login`][gh] as yourself, then [`sv codex`][sv] or [`sv claude`][sv] to sign in; quit the agent and click "Recheck".
[`sv`][sv] uses the sandbox account, with its own agent login.

Add a repository in the sidebar, then start from a prompt, issue, open discussion, branch, existing PR or unpublished security advisory.
Choose repository paths inside the workspace in Settings → Advanced.
Symlinks can point here but cannot grant access outside the workspace.
Install shared dependencies yourself in Shell from the main checkout; agents cannot run `brew install`.
Agents survive quitting via [`herdr`][herdr]; Shell tabs close.
Agents can change shared files and upload readable code; [review their work](https://mikemcquaid.com/why-open-source-maintainers-thrive-in-the-llm-era/) before trusting it.
Keep your main keychain; see [`sandvault` recovery](https://github.com/webcoyote/sandvault#fix-the-security-popup) for permission prompts.

Upgrading from the former app preserves settings and conversations; keep old session files, update custom app paths and repeat iPhone setup.

## ⚙️ Configuration

Quit the app and link `~/.sanductor/settings.plist` to your dotfiles.

- **General**: Set defaults and review restored host settings.
- **Work**: Set work hours, holidays and a 15-minute snooze.
- **Prompts**: Back up prompts, schedules and Work settings in iCloud.
- **Secrets**: Save a named Keychain value and use `$NAME` in prompts.
- **Sessions**: Inspect and stop agents and browser pages.
- **Review**: Pick reviewers, models, effort and review or fix prompts.
- **Notifications**: Set Mac and iPhone alerts, sounds and a Dock badge.
- **Fonts**: Customise fonts and sizes.
- **Editor**: Choose the external editor for files and worktrees.
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

Use [TestFlight](https://apps.apple.com/app/testflight/id899247664) on iOS 26+ to [join the beta](https://testflight.apple.com/join/zA5bSe4d).
Or clone this repo, put `DEVELOPMENT_TEAM = <your paid team ID>` in `Signing.xcconfig` at its root, run `script/bootstrap` and `script/install`, then build `Sanductor-iOS` in Xcode.
Read and reply in Reader, with up to three recent turns on iPhone.
Shows public and private PR status with conflict badges and prefers GitHub Mobile, falling back to GitHub.com; private PRs require sign-in.

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

3. Set Home and optional Away addresses; Automatic tries both.
   Enter your Mac username; `sandvault-` is added.
   Use port `22` locally or a router port forwarded to key-only SSH.
   Select `sanductor` (installed app) or `sanductor-dev` (development).
   Choose **Connect** and verify the host key against `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on your Mac.
   A changed key must be explicitly replaced in Settings.
4. For alerts while away, use one iCloud account on both, turn on Send to iPhone in the Mac's Settings → Notifications, then reconnect.

## 🛠️ Development

Xcode 27.2 or later is needed to build from source.
Use `script/build`, `script/test`, `script/style --fix` and `script/analyze` for [development](ARCHITECTURE.md#dependencies-and-toolchain).
Quit the app and run `script/tutorial` to replay the opening tour without resetting settings.

## 📄 Licence and contact

[AGPL-3.0](LICENSE); no support or compatibility guarantees.
[Privacy policy](PRIVACY.md).
[Contact Mike McQuaid](mailto:mike@mikemcquaid.com).
Vendored [Octicons](https://github.com/primer/octicons) use the [MIT License](https://github.com/primer/octicons/blob/main/LICENSE).

[Codex CLI]: https://github.com/openai/codex
[Claude Code]: https://code.claude.com/docs
[Homebrew]: https://brew.sh
[sv]: https://github.com/webcoyote/sandvault
[gh]: https://cli.github.com
[herdr]: https://herdr.dev
