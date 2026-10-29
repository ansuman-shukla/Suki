# Changelog

All notable changes to Suki are documented here.

This project uses semantic versioning for public releases. Use `MAJOR.MINOR.PATCH`, where:

- `MAJOR` changes include breaking behavior or major compatibility changes.
- `MINOR` changes add user-visible features and improvements.
- `PATCH` changes fix bugs, polish existing behavior, or make small internal improvements.

## [Unreleased]

## [0.3.0] - 2026-10-29

### Added
- Meetings now stop recording on their own when the call ends, after 10 minutes of silence, when your Mac goes to sleep, or after 4 hours. An auto-stopped meeting is saved, but not copied to your clipboard, and a notice tells you why it stopped.
- A **Repair** button for stuck permissions. If System Settings shows Accessibility or Screen Recording as on but Suki still can't use it, Repair resets Suki's permission and asks again. You'll find it in the permission alerts, the menu bar, Settings, and Setup.

### Improved
- On laptop speakers, meeting transcripts no longer turn the other person's voice into short fake "You" lines. While they're talking, your own lines may show up a few seconds later in the live view.
- Shortcuts start working as soon as you grant Accessibility, with no relaunch needed.

### Fixed
- Long meeting transcripts no longer stutter while scrolling.

## [0.2.0] - 2026-10-28

### Added
- Let your AI agent read your meetings. Suki now includes a small, read-only MCP server, so coding agents and AI apps can list, search, and read the meetings you've recorded. It stays off until you add it to an agent's config, never touches the network, and can't change or delete anything. Setup steps are in `docs/advanced.md`.

## [0.1.1] - 2026-10-21

A small release with no changes to the app itself.

### Improved
- A new, easier README with a short visual tour, a four-step setup guide, a Suki vs Wispr Flow comparison, and a demo video.
- Advanced setup (providers, local models, custom prompts, timeouts), privacy details, and an FAQ now live in a separate guide, `docs/advanced.md`.

## [0.1.0] - 2026-10-21

First public release of Suki, a menu-bar dictation app for macOS that uses your own transcription and LLM API keys.

### Added
- Dictation anywhere: hold `Fn` to talk, or tap `Command-Fn` to start and stop, and your words are pasted into the focused text field. Both shortcuts can be customized.
- Choose your transcription provider (Groq, OpenAI, Gemini, xAI, Deepgram, or any OpenAI-compatible endpoint) and, separately, your LLM provider for cleanup and Edit Mode.
- Live transcription while you speak, with optional live typing into the focused app.
- Context-aware cleanup, custom vocabulary, snippets, and Edit Mode for rewriting selected text with a spoken instruction.
- A hub window with a home page showing dictation stats and day-grouped history, plus Dictionary and Snippets pages.
- Meeting notes: record a call with your mic and the Mac's audio, get a "You" / "Them" transcript, copy it, and keep past meetings as notes you can rename.
- Suki notices when a call app starts using the microphone and offers to take notes (can be turned off in Settings).
- New app icon, original dictation sounds, and light and dark themes.
- A signed universal DMG for Apple Silicon and Intel Macs. Suki is not notarized by Apple, so the first launch needs a one-time **Open Anyway** in System Settings > Privacy & Security; updates after that install from inside the app.

### Improved
- In-app updates are installed only when they are signed by the same certificate as your installed copy of Suki, so a tampered or foreign download is refused.

### Fixed
- Call transcripts no longer lose your voice when the call app (like the WhatsApp desktop app) takes over the microphone. Suki reconnects the mic and shows a warning if another app still blocks it.
- Call audio playing from your speakers is no longer transcribed a second time as your words.
- Call transcript lines now appear in the order people spoke, one line per turn, instead of in 10-second blocks.
