<p align="center">
  <img src="Resources/AppIcon-Source.png" width="128" height="128" alt="Suki icon">
</p>

<h1 align="center">Suki</h1>

<p align="center">
  Fast, private dictation for your Mac. Speak, and your words land in any text field.
</p>

<p align="center">
  <a href="https://github.com/ansuman-shukla/Suki/releases/latest"><b>⬇ Download Suki</b></a><br>
  <sub>Works on all Macs (Apple Silicon + Intel)</sub>
</p>

---

## Overview

Suki is an open source menu-bar dictation app for macOS. It gives you fast AI transcription, live transcription while you speak, context-aware cleanup, and voice-driven text editing, using your own API keys and no subscription.

## Quick Start

1. Download `Suki.dmg` from the [latest release](https://github.com/ansuman-shukla/Suki/releases/latest), open it, and drag Suki to Applications.
2. Open Suki. macOS blocks the first launch because Suki is not notarized by Apple: go to **System Settings > Privacy & Security**, click **Open Anyway**, and confirm. You only do this once; later updates install from inside the app.
3. Get an API key from a supported provider, such as [Groq](https://groq.com/), [OpenAI](https://platform.openai.com/), or [Google AI Studio](https://aistudio.google.com/). Setup asks you to pick a transcription provider and an LLM provider; a provider that does both needs only one key.
4. Hold `Fn` to talk, or tap `Command-Fn` to start and stop dictation, and whatever you say is pasted into the current text field.

## Privacy

There is no Suki server, so Suki does not store or retain your data. The only information that leaves your computer are API calls to the transcription and LLM providers you configure.

## For Power Users

Providers and models, live transcription, Edit Mode, custom cleanup prompts, and local models are covered in [docs/advanced.md](docs/advanced.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up the project, build, test, and submit changes.

## License

Licensed under the MIT license.
