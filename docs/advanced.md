# Suki for power users

Everything you need to fine-tune Suki: providers and models, live transcription, shortcuts, Edit Mode, custom cleanup prompts, local models, privacy details, and FAQ. New to Suki? Start with the [README](../README.md).

## Providers and models

Suki uses two kinds of AI: a **transcription** model that turns your voice into text, and an **LLM** that cleans that text up. Setup asks you to pick one of each; a provider that does both needs only one key.

- **Choose your transcription provider:** Groq (`whisper-large-v3`), OpenAI (`gpt-transcribe` and older models), Gemini (`gemini-3.5-transcribe`), xAI (`grok-voice-transcribe-2.0`), Deepgram (`nova-3`), or any OpenAI-compatible endpoint. **Test model** checks a model ID with a second of generated silence.
- **Choose your LLM provider:** Cleanup, Edit Mode, and context use Groq, OpenAI, Anthropic, Google Gemini, xAI Grok, Cerebras, or any OpenAI-compatible endpoint, with that provider's current models suggested. **Test models** sends a one-line prompt to each selected model.

## Live transcription and live typing

- **Live transcription:** Stream audio over a WebSocket while you speak with OpenAI `gpt-live-transcribe`, Gemini `gemini-3.5-transcribe-live`, xAI, Deepgram, or an OpenAI-compatible realtime endpoint, so text is ready the moment you stop. If the live connection fails, Suki falls back to a regular upload.
- **Live typing (optional):** Have words typed into the focused app as you speak. OpenAI types word by word; Gemini, xAI, and Deepgram type each phrase when you pause. Live-typed text skips cleanup.

## Shortcuts

- **Custom shortcuts:** Customize both hold-to-talk and toggle dictation shortcuts. If your toggle shortcut extends your hold shortcut, you can start in hold mode and press the extra modifier keys to latch into tap mode without stopping the recording.

## Context and vocabulary

- **Context-aware cleanup:** Suki can read nearby app context so names, terms, and phrases are spelled correctly when you dictate into email, terminals, docs, and other apps.
- **Custom vocabulary:** Add names, jargon, and project-specific words that Suki should preserve during cleanup.

## Edit Mode

Edit Mode lets you highlight existing text and transform it with a spoken instruction, like "make this shorter" or "turn this into bullets." Enable it in settings, then use your normal dictation shortcut on selected text, or choose Manual mode to require an extra modifier key.

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

## Let your AI agent read your meetings

Suki ships a small, read-only [MCP](https://modelcontextprotocol.io) server, so coding agents and AI apps can look up the meetings you've recorded. It gives them three tools: `list_meetings`, `search_meetings`, and `read_meeting`. It can't change or delete anything, it never touches the network, and it only runs while your agent is using it.

Add it to your agent's MCP config:

```json
{
  "mcpServers": {
    "suki-meetings": {
      "command": "/Applications/Suki.app/Contents/MacOS/suki-mcp"
    }
  }
}
```

To read the meetings of a different Suki build, add `"args": ["--app", "Suki Dev"]`.

Whatever your agent reads, it sends to its own AI provider. Only connect agents you trust with your meeting transcripts.

## Privacy

- **No Suki server.** There's no account, no sign-up, and no tracking. Suki has no server to send your data to.
- **Your voice goes only where you send it.** Audio and text go straight to the AI provider you choose. Use local models, and nothing leaves your Mac at all.
- **Your stuff stays on your Mac.** Dictation history and meeting transcripts are saved locally, and your API keys are stored in the macOS Keychain.
- **You control context.** If you allow Screen Recording, Suki sends a screenshot of the app you're dictating into to your AI provider, so it can spell names right. Skip that permission and Suki works without it.
- **Agents only see meetings if you connect them.** The meetings MCP server is off until you add it to an agent's config, and it's read-only.

## FAQ

<details>
  <summary><b>How much does it cost?</b></summary>

  Suki is free. You pay your AI provider for what you use, which is usually a few cents for a lot of dictation. Some providers, like Groq, have a free tier, and local models cost nothing.
</details>

<details>
  <summary><b>Which provider should I pick?</b></summary>

  Start with Groq: it's fast, cheap, and one key covers everything. If you want to see words appear while you talk, try OpenAI or Gemini for live typing. You can switch any time in Settings.
</details>

<details>
  <summary><b>Why does macOS say it can't verify Suki?</b></summary>

  Suki isn't notarized by Apple, so macOS asks you to confirm the first launch. Click **Open Anyway** in **System Settings > Privacy & Security**. Suki checks the signature of every update before it installs it.
</details>

<details>
  <summary><b>Can I use it without the internet?</b></summary>

  Yes, if you run both transcription and cleanup on local models. See [Using a Local Model](#using-a-local-model).
</details>

<details>
  <summary><b>Does it work on Intel Macs?</b></summary>

  Yes. Suki runs on Apple Silicon and Intel Macs with macOS 13 or later.
</details>
