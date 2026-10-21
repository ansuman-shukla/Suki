// Renders the README artwork as SVG cards in Suki's design system palette.
//
// Usage, from the repository root:
//   swift scripts/render-readme-art.swift
//
// Writes docs/assets/readme/<card>-light.svg and <card>-dark.svg. The README
// picks the variant with <picture> and prefers-color-scheme. Fonts are named,
// not embedded, so each viewer's system renders them (New York / SF on Macs).

import AppKit
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: "docs/assets/readme", isDirectory: true)

struct Theme {
    let name: String
    let surface: String
    let panel: String
    let border: String
    let text: String
    let text2: String
    let text3: String
    let accent: String
    let teal: String
    let orange: String
    let selection: String
    let selectionOpacity: Double
    let button: String
    let buttonText: String
    let secondaryButton: String
    let tileOpacity: Double
}

// Hex values mirror Sources/DesignSystem.swift (Palette + Theme).
let light = Theme(
    name: "light", surface: "#F5F4F0", panel: "#FCFCFB", border: "#E4E0D6", text: "#1A1A1A",
    text2: "#71716E", text3: "#9D9C98", accent: "#7232A6", teal: "#247872", orange: "#D9862B",
    selection: "#A26EC1", selectionOpacity: 0.12, button: "#1A1A1A", buttonText: "#FCFCFB",
    secondaryButton: "#EEEBE3", tileOpacity: 0.14
)
let dark = Theme(
    name: "dark", surface: "#202020", panel: "#2A2A29", border: "#343432", text: "#E9E8E1",
    text2: "#B3B2AD", text3: "#878683", accent: "#A26EC1", teal: "#68BDB0", orange: "#FFA946",
    selection: "#A26EC1", selectionOpacity: 0.16, button: "#FCFCFB", buttonText: "#1A1A1A",
    secondaryButton: "#343432", tileOpacity: 0.2
)

let iconDataURI: String = {
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "Resources/AppIcon-Source.png") as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let size = 128
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return "data:image/png;base64," + (data as Data).base64EncodedString()
}()

func svg(width: Int, height: Int, title rawTitle: String, _ body: String) -> String {
    let title = rawTitle.replacingOccurrences(of: "&", with: "&amp;")
    return """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)" role="img" aria-label="\(title)">
    <title>\(title)</title>
    <style>
    .serif{font-family:'New York','Iowan Old Style',ui-serif,Georgia,serif}
    .sans{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',Helvetica,Arial,sans-serif}
    .mono{font-family:ui-monospace,'SF Mono',Menlo,Consolas,monospace}
    </style>
    \(body)
    </svg>

    """
}

func card(_ t: Theme, x: Double, y: Double, width: Double, height: Double, radius: Double = 28) -> String {
    "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" rx=\"\(radius)\" fill=\"\(t.surface)\" stroke=\"\(t.border)\" stroke-width=\"2\"/>"
}

func sectionTitle(_ t: Theme, _ text: String) -> String {
    "<text x=\"4\" y=\"64\" class=\"serif\" font-size=\"60\" font-weight=\"600\" fill=\"\(t.text)\">\(text)</text>"
}

func keycap(_ t: Theme, x: Double, y: Double, size: Double) -> String {
    """
    <rect x="\(x)" y="\(y + 7)" width="\(size)" height="\(size)" rx="\(size * 0.2)" fill="#C9761F"/>
    <rect x="\(x)" y="\(y)" width="\(size)" height="\(size)" rx="\(size * 0.2)" fill="#FFA946"/>
    <text x="\(x + size / 2)" y="\(y + size * 0.62)" text-anchor="middle" class="sans" font-size="\(size * 0.38)" font-weight="600" fill="#1A1A1A">fn</text>
    """
}

func waveform(centerX: Double, centerY: Double, bars: Int, maxHeight: Double, color: String) -> String {
    let barWidth = 8.0, gap = 9.0
    let total = Double(bars) * barWidth + Double(bars - 1) * gap
    return (0..<bars).map { index in
        let x = centerX - total / 2 + Double(index) * (barWidth + gap) + barWidth / 2
        let distance = abs(Double(index) - Double(bars - 1) / 2) / (Double(bars) / 2)
        let peak = 1 - distance * distance * 0.55
        return """
        <g transform="translate(\(x) \(centerY))"><rect x="\(-barWidth / 2)" y="\(-maxHeight / 2)" width="\(barWidth)" height="\(maxHeight)" rx="\(barWidth / 2)" fill="\(color)"><animateTransform attributeName="transform" type="scale" values="1 0.25;1 \(peak);1 0.4;1 \(peak * 0.8);1 0.25" dur="1.3s" begin="\(Double(index) * -0.11)s" repeatCount="indefinite"/></rect></g>
        """
    }.joined(separator: "\n")
}

func hero(_ t: Theme) -> String {
    let typingDuration = "7s"
    let body = """
    <defs>
      <clipPath id="frame"><rect width="1600" height="700" rx="40"/></clipPath>
      <radialGradient id="glowA" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="\(t.accent)" stop-opacity="0.22"/><stop offset="1" stop-color="\(t.accent)" stop-opacity="0"/></radialGradient>
      <radialGradient id="glowB" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFA946" stop-opacity="0.2"/><stop offset="1" stop-color="#FFA946" stop-opacity="0"/></radialGradient>
      <filter id="shadow" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#000" flood-opacity="\(t.name == "dark" ? 0.45 : 0.1)"/></filter>
      <clipPath id="line1"><rect x="960" y="270" height="70" width="0"><animate attributeName="width" values="0;560;560" keyTimes="0;0.32;1" dur="\(typingDuration)" repeatCount="indefinite"/></rect></clipPath>
      <clipPath id="line2"><rect x="960" y="340" height="70" width="0"><animate attributeName="width" values="0;0;560;560" keyTimes="0;0.34;0.62;1" dur="\(typingDuration)" repeatCount="indefinite"/></rect></clipPath>
    </defs>
    <g clip-path="url(#frame)">
      <rect width="1600" height="700" fill="\(t.surface)"/>
      <circle cx="1350" cy="120" r="520" fill="url(#glowA)"/>
      <circle cx="160" cy="700" r="480" fill="url(#glowB)"/>
    </g>
    <rect x="1" y="1" width="1598" height="698" rx="40" fill="none" stroke="\(t.border)" stroke-width="2"/>

    <image x="96" y="84" width="76" height="76" xlink:href="\(iconDataURI)" href="\(iconDataURI)"/>
    <text x="190" y="137" class="serif" font-size="46" font-weight="600" fill="\(t.text)">Suki</text>

    <text x="92" y="320" class="serif" font-size="132" font-weight="600" fill="\(t.text)">Talk.</text>
    <text x="92" y="460" class="serif" font-size="132" font-weight="600" fill="\(t.text)">Suki <tspan font-style="italic" fill="\(t.accent)">types.</tspan></text>
    <text x="98" y="550" class="sans" font-size="34" fill="\(t.text2)">Dictation for every app on your Mac.</text>
    <text x="98" y="598" class="sans" font-size="34" fill="\(t.text2)">Free, private, and under 10MB.</text>

    <g filter="url(#shadow)"><rect x="900" y="110" width="600" height="320" rx="28" fill="\(t.panel)" stroke="\(t.border)" stroke-width="2"/></g>
    <circle cx="940" cy="150" r="8" fill="\(t.border)"/><circle cx="968" cy="150" r="8" fill="\(t.border)"/><circle cx="996" cy="150" r="8" fill="\(t.border)"/>
    <text x="960" y="222" class="sans" font-size="26" fill="\(t.text3)">To: Sam</text>
    <line x1="940" y1="248" x2="1460" y2="248" stroke="\(t.border)" stroke-width="2"/>
    <g>
      <animate attributeName="opacity" values="1;1;0" keyTimes="0;0.94;1" dur="\(typingDuration)" repeatCount="indefinite"/>
      <text x="960" y="318" class="sans" font-size="33" fill="\(t.text)" clip-path="url(#line1)">Hey Sam, the deck is ready.</text>
      <text x="960" y="388" class="sans" font-size="33" fill="\(t.text)" clip-path="url(#line2)">Want to go over it at 3?</text>
    </g>

    \(keycap(t, x: 948, y: 488, size: 92))
    <rect x="1068" y="492" width="340" height="88" rx="44" fill="#1A1A1A" stroke="\(t.name == "dark" ? "#464544" : "#1A1A1A")" stroke-width="2"/>
    \(waveform(centerX: 1238, centerY: 536, bars: 12, maxHeight: 44, color: "#FCFCFB"))
    """
    return svg(width: 1600, height: 700, title: "Talk. Suki types. Dictation for every app on your Mac.", body)
}

struct Feature {
    let title: String
    let lines: [String]
    let glyph: (String) -> String
}

let features: [Feature] = [
    Feature(title: "Tiny", lines: ["Under 10MB. About 20x", "smaller than Wispr Flow."]) { color in
        "<rect x=\"14\" y=\"14\" width=\"52\" height=\"52\" rx=\"12\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"4\" stroke-dasharray=\"7 7\"/><rect x=\"29\" y=\"29\" width=\"22\" height=\"22\" rx=\"6\" fill=\"\(color)\"/>"
    },
    Feature(title: "Free", lines: ["No subscription and", "no word limits."]) { color in
        "<path d=\"M40 40c-6-8-10-11-15-11-6 0-11 5-11 11s5 11 11 11c5 0 9-3 15-11s10-11 15-11c6 0 11 5 11 11s-5 11-11 11c-5 0-9-3-15-11z\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"5\" stroke-linejoin=\"round\"/>"
    },
    Feature(title: "Private", lines: ["No account, no Suki server.", "History stays on your Mac."]) { color in
        "<rect x=\"22\" y=\"36\" width=\"36\" height=\"28\" rx=\"7\" fill=\"\(color)\"/><path d=\"M29 36v-7a11 11 0 0 1 22 0v7\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"5\" stroke-linecap=\"round\"/>"
    },
    Feature(title: "Any AI", lines: ["OpenAI, Groq, Gemini,", "Claude, and more."]) { color in
        "<path d=\"M40 14c2 15 9 22 24 26-15 4-22 11-24 26-2-15-9-22-24-26 15-4 22-11 24-26z\" fill=\"\(color)\"/>"
    },
    Feature(title: "Local models", lines: ["Run models on your own", "Mac. Nothing leaves it."]) { color in
        "<rect x=\"20\" y=\"22\" width=\"40\" height=\"28\" rx=\"5\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"5\"/><path d=\"M12 60h56\" stroke=\"\(color)\" stroke-width=\"5\" stroke-linecap=\"round\"/>"
    },
    Feature(title: "Knows your words", lines: ["Custom dictionary and", "snippets for your jargon."]) { color in
        "<text x=\"40\" y=\"53\" text-anchor=\"middle\" class=\"serif\" font-size=\"38\" font-weight=\"600\" fill=\"\(color)\">Aa</text>"
    },
]

func featureGrid(_ t: Theme) -> String {
    let columns = 3, cardWidth = 512.0, cardHeight = 320.0, gap = 32.0, top = 104.0
    let accents = [t.orange, t.accent, t.teal]
    let cards = features.enumerated().map { index, feature -> String in
        let x = Double(index % columns) * (cardWidth + gap)
        let y = top + Double(index / columns) * (cardHeight + gap)
        let color = accents[index % accents.count]
        let lines = feature.lines.enumerated().map { lineIndex, line in
            "<text x=\"\(x + 40)\" y=\"\(y + 244 + Double(lineIndex) * 38)\" class=\"sans\" font-size=\"27\" fill=\"\(t.text2)\">\(line)</text>"
        }.joined(separator: "\n")
        return """
        \(card(t, x: x + 1, y: y, width: cardWidth - 2, height: cardHeight))
        <g transform="translate(\(x + 40) \(y + 40))"><rect width="80" height="80" rx="20" fill="\(color)" fill-opacity="\(t.tileOpacity)"/>\(feature.glyph(color))</g>
        <text x="\(x + 40)" y="\(y + 192)" class="serif" font-size="44" font-weight="600" fill="\(t.text)">\(feature.title)</text>
        \(lines)
        """
    }.joined(separator: "\n")
    let height = Int(top + 2 * cardHeight + gap + 2)
    return svg(width: 1600, height: height, title: "Why Suki: tiny, free, private, any AI, local models, and knows your words.",
               sectionTitle(t, "Why Suki") + "\n" + cards)
}

func steps(_ t: Theme) -> String {
    let cardWidth = 382.0, cardHeight = 380.0, gap = 24.0, top = 104.0
    let cursor = "<path d=\"M0 0v34l9-8 7 15 7-3-7-14h12z\" fill=\"\(t.text)\" stroke=\"\(t.surface)\" stroke-width=\"3\" stroke-linejoin=\"round\"/>"
    let visuals: [(Double, Double) -> String] = [
        { cx, cy in
            """
            <image x="\(cx - 140)" y="\(cy - 38)" width="76" height="76" xlink:href="\(iconDataURI)" href="\(iconDataURI)"/>
            <path d="M\(cx - 44) \(cy)h66m-14-14 14 14-14 14" fill="none" stroke="\(t.text3)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
            <path d="M\(cx + 42) \(cy - 30)h28l10 10h40a8 8 0 0 1 8 8v42a8 8 0 0 1-8 8h-78a8 8 0 0 1-8-8v-52a8 8 0 0 1 8-8z" fill="\(t.secondaryButton)" stroke="\(t.text3)" stroke-width="3"/>
            """
        },
        { cx, cy in
            """
            <rect x="\(cx - 120)" y="\(cy - 32)" width="240" height="64" rx="14" fill="\(t.secondaryButton)" stroke="\(t.border)" stroke-width="2"/>
            <text x="\(cx)" y="\(cy + 10)" text-anchor="middle" class="sans" font-size="27" font-weight="600" fill="\(t.text)">Open Anyway</text>
            <g transform="translate(\(cx + 88) \(cy + 12))">\(cursor)</g>
            """
        },
        { cx, cy in
            """
            <rect x="\(cx - 140)" y="\(cy - 32)" width="280" height="64" rx="14" fill="\(t.panel)" stroke="\(t.border)" stroke-width="2"/>
            <text x="\(cx - 116)" y="\(cy + 9)" class="mono" font-size="26" fill="\(t.text2)">gsk_••••••••</text>
            <rect x="\(cx + 100)" y="\(cy - 18)" width="3" height="36" rx="1.5" fill="\(t.accent)"><animate attributeName="opacity" values="1;1;0;0" keyTimes="0;0.5;0.5;1" dur="1.1s" repeatCount="indefinite"/></rect>
            """
        },
        { cx, cy in
            """
            \(keycap(t, x: cx - 124, y: cy - 46, size: 88))
            <rect x="\(cx - 16)" y="\(cy - 38)" width="148" height="72" rx="36" fill="#1A1A1A"/>
            \(waveform(centerX: cx + 58, centerY: cy - 2, bars: 6, maxHeight: 36, color: "#FCFCFB"))
            """
        },
    ]
    let labels = [["Download and drag", "to Applications"], ["Open Anyway in", "Privacy &amp; Security"],
                  ["Paste a free", "Groq key"], ["Hold fn", "and talk"]]
    let cards = (0..<4).map { index -> String in
        let x = Double(index) * (cardWidth + gap)
        let text = labels[index].enumerated().map { lineIndex, line in
            "<text x=\"\(x + 36)\" y=\"\(top + 290 + Double(lineIndex) * 38)\" class=\"sans\" font-size=\"28\" font-weight=\"\(lineIndex == 0 ? 600 : 400)\" fill=\"\(lineIndex == 0 ? t.text : t.text2)\">\(line)</text>"
        }.joined(separator: "\n")
        return """
        \(card(t, x: x + 1, y: top, width: cardWidth - 2, height: cardHeight))
        <text x="\(x + 36)" y="\(top + 78)" class="serif" font-size="48" font-weight="600" fill="\(t.text3)">\(index + 1)</text>
        \(visuals[index](x + cardWidth / 2, top + 170))
        \(text)
        """
    }.joined(separator: "\n")
    return svg(width: 1600, height: Int(top + cardHeight + 2),
               title: "Get started: download and drag to Applications, click Open Anyway in Privacy & Security, paste a free Groq key, hold fn and talk.",
               sectionTitle(t, "Get started in a minute") + "\n" + cards)
}

func comparison(_ t: Theme) -> String {
    let top = 104.0, rowHeight = 88.0, headerHeight = 120.0
    let rows: [(String, String, String)] = [
        ("Unlimited use", "Free", "$15/month"), ("Size on disk", "25MB", "500MB"),
        ("Pick your AI model", "yes", "no"), ("Local models", "yes", "no"), ("Open source", "yes", "no"),
    ]
    let sukiX = 1000.0, wisprX = 1360.0
    let height = top + headerHeight + Double(rows.count) * rowHeight + 40
    func value(_ value: String, x: Double, y: Double, strong: Bool) -> String {
        switch value {
        case "yes":
            return "<g transform=\"translate(\(x) \(y - 10))\"><circle r=\"24\" fill=\"\(t.teal)\" fill-opacity=\"\(t.tileOpacity + 0.04)\"/><path d=\"M-10 0l6 7 13-15\" fill=\"none\" stroke=\"\(t.teal)\" stroke-width=\"5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></g>"
        case "no":
            return "<path transform=\"translate(\(x) \(y - 10))\" d=\"M-8-8 8 8M8-8-8 8\" stroke=\"\(t.text3)\" stroke-width=\"4\" stroke-linecap=\"round\"/>"
        default:
            return "<text x=\"\(x)\" y=\"\(y)\" text-anchor=\"middle\" class=\"sans\" font-size=\"31\" font-weight=\"\(strong ? 600 : 400)\" fill=\"\(strong ? t.text : t.text2)\">\(value)</text>"
        }
    }
    let rowMarkup = rows.enumerated().map { index, row -> String in
        let baseline = top + headerHeight + Double(index) * rowHeight + 56
        let divider = index == 0 ? "" : "<line x1=\"56\" y1=\"\(baseline - 56)\" x2=\"1544\" y2=\"\(baseline - 56)\" stroke=\"\(t.border)\" stroke-width=\"2\"/>"
        return """
        \(divider)
        <text x="64" y="\(baseline)" class="sans" font-size="31" fill="\(t.text)">\(row.0)</text>
        \(value(row.1, x: sukiX, y: baseline, strong: true))
        \(value(row.2, x: wisprX, y: baseline, strong: false))
        """
    }.joined(separator: "\n")
    let body = """
    \(sectionTitle(t, "Suki vs Wispr Flow"))
    \(card(t, x: 1, y: top, width: 1598, height: height - top - 2, radius: 32))
    <rect x="\(sukiX - 150)" y="\(top + 20)" width="300" height="\(height - top - 42)" rx="24" fill="\(t.selection)" fill-opacity="\(t.selectionOpacity)"/>
    <image x="\(sukiX - 92)" y="\(top + 34)" width="56" height="56" xlink:href="\(iconDataURI)" href="\(iconDataURI)"/>
    <text x="\(sukiX - 26)" y="\(top + 76)" class="serif" font-size="42" font-weight="600" fill="\(t.text)">Suki</text>
    <text x="\(wisprX)" y="\(top + 76)" text-anchor="middle" class="serif" font-size="42" font-weight="600" fill="\(t.text3)">Wispr Flow</text>
    \(rowMarkup)
    """
    return svg(width: 1600, height: Int(height),
               title: "Suki vs Wispr Flow: unlimited use free vs $15/month, 25MB vs 500MB, pick your AI model, local models, open source.",
               body)
}

func demoTitle(_ t: Theme) -> String {
    svg(width: 1600, height: 84, title: "See Suki in action", sectionTitle(t, "See Suki in action"))
}

func downloadButton(_ t: Theme) -> String {
    let body = """
    <rect width="600" height="120" rx="60" fill="\(t.button)"/>
    <path d="M118 38v34m-14-14 14 14 14-14M102 84h32" fill="none" stroke="\(t.buttonText)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
    <text x="160" y="74" class="sans" font-size="40" font-weight="600" fill="\(t.buttonText)">Download for Mac</text>
    """
    return svg(width: 600, height: 120, title: "Download Suki for Mac", body)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let cards: [(String, (Theme) -> String)] = [
    ("hero", hero), ("features", featureGrid), ("steps", steps), ("compare", comparison), ("download", downloadButton), ("demo", demoTitle),
]
for (name, render) in cards {
    for theme in [light, dark] {
        let url = outputDirectory.appendingPathComponent("\(name)-\(theme.name).svg")
        try render(theme).write(to: url, atomically: true, encoding: .utf8)
        print("Wrote \(url.path)")
    }
}
