# Changelog

All notable changes to Suki are documented here.

This project uses semantic versioning for public releases. Use `MAJOR.MINOR.PATCH`, where:

- `MAJOR` changes include breaking behavior or major compatibility changes.
- `MINOR` changes add user-visible features and improvements.
- `PATCH` changes fix bugs, polish existing behavior, or make small internal improvements.

## [Unreleased]

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

### Fixed
- Call transcripts no longer lose your voice when the call app (like the WhatsApp desktop app) takes over the microphone. Suki reconnects the mic and shows a warning if another app still blocks it.
- Call audio playing from your speakers is no longer transcribed a second time as your words.
- Call transcript lines now appear in the order people spoke, one line per turn, instead of in 10-second blocks.
