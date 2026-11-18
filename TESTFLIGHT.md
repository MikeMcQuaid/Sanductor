# Sanductor public beta submission

Draft copy for **App Store Connect > Sanductor > TestFlight**, under **Additional > Test Information**. Copy each field without its heading. Review the beta terms before adopting them. These TestFlight terms do not replace the repository's source licence or a custom App Store EULA. Keep reviewer contact details current in App Store Connect.

## Beta App Description

Keep your coding agents within reach from your iPhone. Sanductor connects to Sanductor on your own Mac, so you can check repositories and pull request status, start tasks and continue agent sessions in a live terminal. Your agents keep running on the Mac when you disconnect.

The companion uses a direct, encrypted SSH connection with a key created on your phone. There is no Sanductor account, subscription or hosted relay. Requires iOS 26 or later and an Apple silicon Mac running macOS 26 or later with Sanductor and sandvault configured. Coding agents use your own Codex or Claude Code account. Remote access requires a network route to your Mac.

This beta focuses on connection setup, session control and reliable reconnection. Please send feedback through TestFlight, excluding private code, credentials and terminal content you do not want to share.

## What to Test

Please test first-time SSH pairing, host-key verification, repository and session lists, starting an agent task, terminal input, pull request links and reconnecting after the phone sleeps or changes networks. Include your iPhone model, iOS version and reproduction steps in feedback.

The public release workflow supplies its own version-specific What to Test text automatically; this is a suggested manual alternative.

## Beta App Review Notes

Sanductor is a remote companion for a Mac development workspace. It is not a standalone coding service. Review requires an Apple silicon Mac running macOS 26 or later and an iPhone running iOS 26 or later on a network that allows the phone to reach the Mac over SSH. Use your own review Mac; there is no developer-hosted demo server or Sanductor login.

1. Install Homebrew if needed, then run `brew install sanductor sandvault` in the Mac's normal user account. Open Sanductor from /Applications. Follow its setup checks, including `sv build`, `gh auth login` and `sv codex` or `sv claude` for the selected coding agent. These use your GitHub and agent-provider accounts, not an account with Sanductor.
2. Add a disposable repository in the Mac app and start an agent session. Use a test project without private code. Complete installation and workspace setup using the linked README below.
3. On iPhone, open Settings and use **Share public key** to transfer the displayed SSH public key to the Mac. Copy that key to its clipboard. On the Mac, run:

   ```sh
   mkdir -p ~/.config/codeofhonor/sandvault/authorized_keys.d
   pbpaste >~/.config/codeofhonor/sandvault/authorized_keys.d/sanductor-phone
   sv build
   ```

4. Enable **System Settings > General > Sharing > Remote Login** for `sandvault-<you>`, replacing `<you>` with your Mac username. Create `/etc/ssh/sshd_config.d/000-sanductor.conf` with administrator privileges:

   ```text
   Match User sandvault-<you>
       SetEnv SHARED_WORKSPACE=/Users/Shared/sv-<you>
   ```

5. On iPhone, set Home to the Mac's local address, port 22 and Mac username to your normal username; the app adds `sandvault-`. Select the `sanductor` session and tap **Connect**. Compare the displayed host fingerprint with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the Mac before accepting it. Away is optional; no router forwarding is needed on the same local network.
6. Open the repository and session, send a short task and observe terminal output. Disconnect and reconnect to confirm the session continues. Opening a private PR may separately require GitHub sign-in.

The phone authenticates to the reviewer's Mac with its SSH key, not a shared username and password supplied by the developer. Agent commands execute on that Mac. Contact mike@mikemcquaid.com if review setup needs assistance.

Setup: https://github.com/MikeMcQuaid/Sanductor#-iphone-companion-app

## Beta Licence Agreement

Sanductor is provided by Mike McQuaid under the GNU Affero General Public License, version 3. The licence text and corresponding source are available at https://github.com/MikeMcQuaid/Sanductor. Third-party components retain their respective licences. These beta notes impose no additional restrictions on rights granted by those licences.

This is pre-release software. Features may change, connections may fail and commands can modify files on the Mac you connect to. Keep backups and review agent changes before relying on them. TestFlight builds expire and continued availability or compatibility is not promised. Warranty and liability are governed by the applicable software licence and any rights that cannot be excluded under applicable law.

Apple's TestFlight terms govern its distribution service. GitHub, agent providers and other services you choose have their own terms and may charge for usage. Sanductor's data handling is described at https://github.com/MikeMcQuaid/Sanductor/blob/main/PRIVACY.md.

Feedback is voluntary. Do not include secrets or confidential project material. There is no confidentiality requirement for this public beta. Contact: Mike McQuaid, mike@mikemcquaid.com.

## Other fields and preparation

- **Feedback email:** `mike@mikemcquaid.com`.
- **Review contact:** Mike McQuaid and that email; enter your reachable telephone number privately in App Store Connect.
- **Privacy Policy URL:** publish `PRIVACY.md` on `main`, then use `https://github.com/MikeMcQuaid/Sanductor/blob/main/PRIVACY.md`. Confirm it opens without signing in. Also add an accessible privacy link in the app; a repository file alone does not provide that.
- **Marketing/support URL:** `https://github.com/MikeMcQuaid/Sanductor`.
- **Reviewer access:** these notes deliberately use the reviewer's Mac and provider accounts. They do not promise an existing demo account. Apple requires full review access; if it cannot use this setup, arrange access through App Review before resubmitting. A short pairing and session-control video would help explain the companion requirement.
- **Encryption:** follow the implementation-specific guidance in [Architecture](ARCHITECTURE.md#iphone-testflight). Existing builds use Apple's crypto implementation on iOS; do not change answers merely because the connection protocol is SSH.
- **Age rating and privacy answers:** answer for the shipped app and its integrations, including arbitrary terminal content and configured AI services. No advertising or tracking does not by itself establish that every App Privacy answer is “Data Not Collected”.

For an eventual App Store listing, choose **Developer Tools** as the primary category and optionally **Productivity** as the secondary. Suggested subtitle: **Your coding agents, on iPhone**. Capture real iPhone screenshots showing the repository/session list, an agent terminal and PR status. Use disposable projects and remove private hostnames, account details and code. A connection-settings image can explain setup, but should not be the lead image.

App Store screenshots and categories are not prerequisites for the first external TestFlight beta. The enhanced invitation can show those from the latest approved App Store version; uploading screenshots to an unapproved draft does not make them appear in the invitation. See [Apple's test-information guide][test-info].

Create the configured external group (**Public Beta** by default, or the name in `TESTFLIGHT_PUBLIC_GROUP`), submit an eligible official release build and wait for beta approval. Then enable its public link, choose **Open to Anyone** and set the limit to **10,000**. The existing workflow assigns future official releases to that group; private internal-only builds remain separate. Full operational steps are in [Architecture](ARCHITECTURE.md#iphone-testflight).

[test-info]: https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/
