import SwiftUI

/// Scrollable settings page with a serif title, e.g. "General".
struct SettingsPane<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(title)
                    .font(SukiFont.display(30, .medium))
                    .foregroundStyle(Theme.textPrimary)
                content
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(SukiToggleStyle())
        .foregroundStyle(Theme.textPrimary)
    }
}

/// Rounded card of rows separated by thin dividers, with an optional all-caps label above it.
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .sectionLabelStyle()
                    .padding(.horizontal, 4)
            }
            // Every row draws a divider on its top edge; shifting the stack up by 1pt lets the
            // card's clip shape hide the first one.
            VStack(spacing: 0) { content }
                .padding(.top, -1)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
        }
    }
}

/// Label on the left (title plus the current value or a short hint), control on the right.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let accessory: Accessory

    init(_ title: String, detail: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 16) {
            SettingsRowLabel(title: title, detail: detail)
            Spacer(minLength: 16)
            accessory
        }
        .settingsRowLayout()
    }
}

struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowLabel(title: title, detail: detail)
        }
        .toggleStyle(SukiToggleStyle())
        .settingsRowLayout()
    }
}

/// Free-form row for editors that don't fit the label/control layout.
struct SettingsBlock<Content: View>: View {
    var title: String?
    var detail: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                SettingsRowLabel(title: title, detail: detail)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsRowLayout()
    }
}

struct SettingsRowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SukiFont.ui(14, .medium))
                .foregroundStyle(Theme.textPrimary)
            if let detail {
                Text(detail)
                    .settingsCaptionStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    func settingsCaptionStyle() -> some View {
        font(SukiFont.ui(12.5)).foregroundStyle(Theme.textSecondary)
    }

    fileprivate func settingsRowLayout() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
    }
}

/// Small black pill switch with a sliding knob.
struct SukiToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SukiToggle(configuration: configuration)
    }
}

private struct SukiToggle: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 12)
                Capsule()
                    .fill(configuration.isOn ? Theme.toggleOn : Theme.toggleOff)
                    .frame(width: 34, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Theme.primaryButtonText)
                            .padding(2.5)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.suki, value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// Segmented control in the app palette: the selected segment uses the same black fill as `SukiToggle`.
/// Replaces `.pickerStyle(.segmented)`, which always draws in the system accent blue.
struct SukiSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, selection: Binding<Value>, options: [Value], label: @escaping (Value) -> String) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(SukiFont.ui(12, .medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Theme.primaryButtonText : Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(isSelected ? Theme.toggleOn : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Theme.secondaryButton))
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.suki, value: selection)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
        }
    }
}

/// Subtle gray button, or the black primary button when `prominent`.
struct SettingsButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        SettingsButton(configuration: configuration, prominent: prominent)
    }
}

extension ButtonStyle where Self == SettingsButtonStyle {
    static var settings: SettingsButtonStyle { SettingsButtonStyle() }
    static var settingsProminent: SettingsButtonStyle { SettingsButtonStyle(prominent: true) }
}

private struct SettingsButton: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(SukiFont.ui(13, .medium))
            .foregroundStyle(prominent ? Theme.primaryButtonText : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(prominent ? Theme.primaryButton : Theme.secondaryButton)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Theme.textPrimary.opacity(isHovered && isEnabled ? 0.05 : 0))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.suki, value: isHovered)
    }
}

/// Gray "Change" button that opens a menu, e.g. an inline `Picker` of options.
struct SettingsMenuButton<Content: View>: View {
    var title = "Change"
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Text(title)
                .font(SukiFont.ui(13, .medium))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Theme.secondaryButton)
        )
    }
}

struct SettingsSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .sectionLabelStyle()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            content
        }
    }
}

struct SettingsCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isHovered ? Theme.rowHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close Settings")
        .onHover { isHovered = $0 }
        .animation(.suki, value: isHovered)
    }
}
