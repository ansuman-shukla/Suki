<p align="center">
  <img src="Resources/AppIcon-Source.png" width="128" height="128" alt="Suki icon">
</p>

<h1 align="center">Suki</h1>

<h3 align="center">Talk, and Suki types it. In any app on your Mac.</h3>

<p align="center">
  A free, open source alternative to Wispr Flow.<br>
  Under 10MB, works with the AI model you choose, and there's no Suki server.
</p>

<p align="center">
  <a href="https://github.com/ansuman-shukla/Suki/releases/latest"><b>⬇ Download Suki for Mac</b></a><br>
  <sub>Free · Apple Silicon and Intel · macOS 13 or later</sub>
</p>

<!-- Demo video: paste the github.com/user-attachments/assets/... link on its own line here. -->

---

## Why Suki

<table>
  <tr>
    <td width="50%" valign="top">
      <b>Tiny and native</b><br>
      Under 10MB to download and about 25MB installed. Wispr Flow takes about 500MB. Suki is a native Mac app, so it stays light on your system.
    </td>
    <td width="50%" valign="top">
      <b>Your AI, your choice</b><br>
      Use Groq, OpenAI, Gemini, Anthropic, xAI, Deepgram, Cerebras, or any OpenAI-compatible service. Switch whenever you like.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <b>Private by design</b><br>
      No Suki account and no Suki server. Your voice goes straight to the provider you pick, and your history stays on your Mac.
    </td>
    <td valign="top">
      <b>Runs on local models</b><br>
      Run cleanup with Ollama or LM Studio and transcription with a local Whisper server, and your words never leave your computer.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <b>Spells your words right</b><br>
      Add names and jargon to your dictionary, so Suki spells them the way you do. It can also read the app you're typing in to catch names on screen.
    </td>
    <td valign="top">
      <b>Free, no word limits</b><br>
      No subscription and no weekly cap. You pay your AI provider directly for what you use, and some providers, like Groq, have a free tier.
    </td>
  </tr>
</table>

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
