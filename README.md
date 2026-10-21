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

## Features

- **Choose your transcription provider:** Groq (`whisper-large-v3`), OpenAI (`gpt-transcribe` and older models), Gemini (`gemini-3.5-transcribe`), xAI (`grok-voice-transcribe-2.0`), Deepgram (`nova-3`), or any OpenAI-compatible endpoint. **Test model** checks a model ID with a second of generated silence.
- **Choose your LLM provider:** Cleanup, Edit Mode, and context use Groq, OpenAI, Anthropic, Google Gemini, xAI Grok, Cerebras, or any OpenAI-compatible endpoint, with that provider's current models suggested. **Test models** sends a one-line prompt to each selected model.
- **Live transcription:** Stream audio over a WebSocket while you speak with OpenAI `gpt-live-transcribe`, Gemini `gemini-3.5-transcribe-live`, xAI, Deepgram, or an OpenAI-compatible realtime endpoint, so text is ready the moment you stop. If the live connection fails, Suki falls back to a regular upload.
- **Live typing (optional):** Have words typed into the focused app as you speak. OpenAI types word by word; Gemini, xAI, and Deepgram type each phrase when you pause. Live-typed text skips cleanup.
- **Custom shortcuts:** Customize both hold-to-talk and toggle dictation shortcuts. If your toggle shortcut extends your hold shortcut, you can start in hold mode and press the extra modifier keys to latch into tap mode without stopping the recording.
- **Context-aware cleanup:** Suki can read nearby app context so names, terms, and phrases are spelled correctly when you dictate into email, terminals, docs, and other apps.
- **Custom vocabulary:** Add names, jargon, and project-specific words that Suki should preserve during cleanup.

## Edit Mode

Edit Mode lets you highlight existing text and transform it with a spoken instruction, like "make this shorter" or "turn this into bullets." Enable it in settings, then use your normal dictation shortcut on selected text, or choose Manual mode to require an extra modifier key.

## Privacy

There is no Suki server, so Suki does not store or retain your data. The only information that leaves your computer are API calls to the transcription and LLM providers you configure.

## Custom Cleanup

If you'd rather keep cleanup more literal and less context-aware, you can paste this simpler prompt into the custom system prompt setting:

<details>
  <summary>Simple post-processing prompt</summary>

  <pre><code>You are a dictation post-processor. You receive raw speech-to-text output and return clean text ready to be typed into an application.

Your job:
- Remove filler words (um, uh, you know, like) unless they carry meaning.
- Fix spelling, grammar, and punctuation errors.
- When the transcript already contains a word that is a close misspelling of a name or term from the context or custom vocabulary, correct the spelling. Never insert names or terms from context that the speaker did not say.
- Preserve the speaker's intent, tone, and meaning exactly.

Output rules:
- Return ONLY the cleaned transcript text, nothing else. So NEVER output words like "Here is the cleaned transcript text:"
- If the transcription is empty, return exactly: EMPTY
- Do not add words, names, or content that are not in the transcription. The context is only for correcting spelling of words already spoken.
- Do not change the meaning of what was said.

Example:
RAW_TRANSCRIPTION: "hey um so i just wanted to like follow up on the meating from yesterday i think we should definately move the dedline to next friday becuz the desine team still needs more time to finish the mock ups and um yeah let me know if that works for you ok thanks"

Then your response would be ONLY the cleaned up text, so here your response is ONLY:
"Hey, I just wanted to follow up on the meeting from yesterday. I think we should definitely move the deadline to next Friday because the design team still needs more time to finish the mockups. Let me know if that works for you. Thanks."</code></pre>
</details>

## Using a Local Model

Suki can use OpenAI-compatible local or self-hosted providers. In Settings > LLM, choose **Custom (OpenAI-compatible)** and enter the base URL and model IDs of your local server, such as Ollama, LM Studio, or another OpenAI-compatible server. For local transcription, choose **Custom** in Settings > Transcription and enter that endpoint; the key is optional.

Local models are often slower than hosted providers, especially on cold start, long recordings, or busy hardware.

<details>
  <summary>Configure longer timeouts for local models</summary>

  Suki keeps the default network timeout at 20 seconds, but you can extend it with macOS defaults:

```bash
defaults write com.ansumanshukla.suki transcription_timeout_seconds -float 120
defaults write com.ansumanshukla.suki post_processing_timeout_seconds -float 120
defaults write com.ansumanshukla.suki context_request_timeout_seconds -float 120
```

The timeout keys are:

- `transcription_timeout_seconds`: audio transcription requests
- `post_processing_timeout_seconds`: transcript cleanup and edit mode requests
- `context_request_timeout_seconds`: nearby app context requests

Only positive values are used. Remove a custom timeout to return to the 20-second default:

```bash
defaults delete com.ansumanshukla.suki transcription_timeout_seconds
defaults delete com.ansumanshukla.suki post_processing_timeout_seconds
defaults delete com.ansumanshukla.suki context_request_timeout_seconds
```

</details>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up the project, build, test, and submit changes.

## License

Licensed under the MIT license.
