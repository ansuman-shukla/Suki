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

## Suki vs Wispr Flow

|                         | Suki                                    | Wispr Flow                                   |
| ----------------------- | --------------------------------------- | -------------------------------------------- |
| Price                   | Free, no word limits                    | Free up to 2,000 words a week, then $15/month |
| Size on disk            | About 25MB                              | About 500MB                                  |
| Choose your AI model    | Yes, 7+ providers or any compatible one | No                                           |
| Local models            | Yes                                     | No, transcription always runs in the cloud   |
| Where your voice goes   | Only to the provider you pick           | Wispr's servers                              |
| Open source             | Yes (MIT)                               | No                                           |
| Dictionary and snippets | Yes                                     | Yes                                          |
| Meeting transcripts     | Yes, split into you and them            | Yes, with AI notes and speaker detection     |
| Platforms               | Mac                                     | Mac, Windows, iPhone, Android                |

<sub>Wispr Flow details come from its pricing and privacy pages and the size of version 1.6, checked October 2026. Suki is free, but your AI provider may charge for usage.</sub>

## Get Started in 3 Steps

1. **Install it.** Download `Suki.dmg` from the [latest release](https://github.com/ansuman-shukla/Suki/releases/latest), open it, and drag Suki to Applications.
   The first time you open it, macOS blocks it because Suki isn't notarized by Apple. Go to **System Settings > Privacy & Security**, click **Open Anyway**, and confirm. You only do this once; updates install from inside the app.
2. **Add an AI key.** Setup walks you through it. The easiest start is a key from [Groq](https://console.groq.com/keys), because one Groq key handles both transcription and cleanup. [OpenAI](https://platform.openai.com/) and [Google AI Studio](https://aistudio.google.com/) work too.
3. **Hold `Fn` and talk.** Let go, and your words appear wherever your cursor is. Want to go hands-free? Tap `Command-Fn` to start, and tap it again to stop.

Suki asks for **Microphone** access to hear you and **Accessibility** access to type for you. **Screen Recording** is optional and helps Suki spell names it can see on screen.

## What You Can Do

- **Dictate anywhere.** Email, Slack, Notion, your code editor, or the terminal. Suki removes the "ums" and fixes punctuation for you.
- **Edit with your voice.** Highlight some text and say "make this shorter" or "turn this into bullets." Turn on Edit Mode in Settings.
- **Snippets.** Say a short phrase and Suki types the full text, like your email signature or a meeting link.
- **Dictionary.** Teach Suki names, product terms, and jargon once, and it keeps spelling them the way you do.
- **Meeting transcripts.** When a call starts in Zoom, Google Meet, Teams, Slack, and others, Suki offers to take notes and gives you a transcript of what you said and what they said. Needs macOS 14.2 or later.
- **Live typing.** Watch your words appear as you speak, with providers that support it.
- **Your own shortcuts.** Change the hold-to-talk and hands-free shortcuts to whatever keys you like.

## Privacy

- **No Suki server.** There's no account, no sign-up, and no tracking. Suki has no server to send your data to.
- **Your voice goes only where you send it.** Audio and text go straight to the AI provider you choose. Use local models, and nothing leaves your Mac at all.
- **Your stuff stays on your Mac.** Dictation history and meeting transcripts are saved locally, and your API keys are stored in the macOS Keychain.
- **You control context.** If you allow Screen Recording, Suki sends a screenshot of the app you're dictating into to your AI provider, so it can spell names right. Skip that permission and Suki works without it.

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

  Yes, if you run both transcription and cleanup on local models. See [Using a Local Model](docs/advanced.md#using-a-local-model).
</details>

<details>
  <summary><b>Does it work on Intel Macs?</b></summary>

  Yes. Suki runs on Apple Silicon and Intel Macs with macOS 13 or later.
</details>

## For Power Users

Providers and models, live transcription, Edit Mode, custom cleanup prompts, and local models are covered in [docs/advanced.md](docs/advanced.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up the project, build, test, and submit changes.

## License

Licensed under the MIT license.
