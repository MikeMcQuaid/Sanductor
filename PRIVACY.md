# Sanductor privacy policy

Last updated: 21 November 2026.

Sanductor is developed by Mike McQuaid. This policy covers the Mac app and its iPhone companion. Sanductor has no developer-operated account service or relay, advertising or tracking analytics. Your repositories and terminal sessions are not automatically sent to the developer.

## Your Mac and iPhone

The Mac app works with repositories, worktrees, prompts, agent conversations, terminal output and GitHub metadata. Settings, session records, backups and optional diagnostic logs are stored on your Mac. Transcript retention normally removes files after 30 days without changes, while preserving ongoing work and open files. An inactive transcript is also kept while its linked Git worktree exists. Saved session names and resume identifiers are stored separately in app metadata: they have no automatic expiry and remain until that metadata is removed, even after a transcript expires. Repository files and other settings have their own lifetime and are not removed by transcript retention.

The iPhone connects directly to the Mac address you configure using encrypted SSH. It sends your commands and receives repository names, session information, pull request status and terminal output. The Mac and anyone authorised to administer it can access that information. No Sanductor relay receives this traffic.

Connection addresses, ports, username, session choice and display preferences are stored on the phone. Its generated SSH private key and saved host keys are stored in the device's Keychain. The private key does not leave the phone; you share its public key to authorise access on your Mac. GitHub avatars are cached locally on both platforms.

## GitHub and coding agents

Both apps request public repository-owner avatars from GitHub. These requests disclose the requested owner name and normal connection information, such as your IP address, to GitHub. Avatar requests do not include your GitHub credentials. Opening a pull request uses GitHub's app or website, with its own sign-in and privacy practices.

The Mac uses your configured GitHub tools and account to fetch project information and carry out actions such as publishing changes or requesting a review. The iPhone receives status from the Mac; Sanductor does not copy the Mac's GitHub credentials to the phone.

Settings → Secrets stores named values in your Mac login Keychain. Using `$NAME` or `${NAME}` in a Sanductor prompt sends that value to the agent running as the sandbox user and to its provider. Session prompt files, transcripts and their backups can contain the value. Sanductor stores saved prompts, custom review briefs and Work settings in a separate private file on your Mac. Prompt text is saved verbatim, including any literal credentials you enter. When iCloud is available, Sanductor automatically backs up these settings to your private iCloud database and restores them on your other Macs. Saved references contain only the name.

Coding agents and review services you use can send prompts, source code, terminal output and other accessible project information to their providers. Sanductor can also request account usage information from the configured agent providers. These services run under your chosen accounts and terms. A sandbox limits access to local files; it does not prevent an agent from uploading files it can read.

See the [GitHub privacy statement][github], [OpenAI privacy policy][openai] and [Anthropic privacy policy][anthropic], together with the terms and data controls for your particular account or API service. Other tools you run have their own privacy practices.

## TestFlight and contact

Apple automatically collects TestFlight crash logs and usage information and shares them with the developer. Feedback you submit can include screenshots, comments, device details and contact information. Public-link participation does not itself reveal your name or email address to the developer. See [TestFlight and privacy][apple].

I use beta diagnostics and information you send me to investigate problems, reply to you and improve Sanductor. I do not sell this information or use it for advertising. TestFlight information shared with me is not passed to third parties. I retain support correspondence and diagnostics only as long as needed for those purposes or legal obligations. Apple's retention and your other providers' retention are governed by their respective policies.

## Your choices

Disconnect the phone to stop its SSH connection. Revoke its access by removing the authorised public key from your Mac and rebuilding the sandvault configuration, as described in the [iPhone setup guide][setup]. Use **Forget saved host keys** in iPhone Settings to clear host trust. That action does not delete the phone's private key or revoke access.

Deleting the iPhone app removes its app data; offloading retains it. Keychain entries can survive app deletion. Removing the Mac app does not delete repositories, agent accounts, session records or backups. Remove those separately when no longer needed. Your system backup and sync settings may retain further copies. Revoke provider credentials with the provider if you want to stop their use completely.

Contact [Mike McQuaid](mailto:mike@mikemcquaid.com) with privacy questions or requests to access, correct or delete information you have sent me. Depending on your location, you may also have rights to object to or restrict processing and complain to your data protection authority. I cannot delete data held solely on your devices or by other providers. Avoid posting private code, credentials or terminal output in public issues. Changes to this policy will appear here with an updated date.

[github]: https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement
[openai]: https://openai.com/policies/privacy-policy/
[anthropic]: https://www.anthropic.com/legal/privacy
[apple]: https://www.apple.com/legal/privacy/data/en/test-flight/
[setup]: https://github.com/MikeMcQuaid/Sanductor#-iphone-companion-app
