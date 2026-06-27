//
//  GridCustomizationView.swift
//  Steps
//
//  The grid customization sheet: a live example month grid plus controls for
//  palette, custom ramp/goal colors, spread (response curve), and day shape.
//  Writes straight into the App Group via @AppStorage so the widget reads the
//  same values; reloads widget timelines on every change. App target only.
//

import SwiftUI
import WidgetKit

struct GridCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @AppStorage(SettingsStore.gridRampHexKey, store: SettingsStore.defaults)
    private var rampHex = GridStyle.defaultRampHex
    @AppStorage(SettingsStore.gridGoalHexKey, store: SettingsStore.defaults)
    private var goalHex = GridStyle.defaultGoalHex
    @AppStorage(SettingsStore.gridSpreadKey, store: SettingsStore.defaults)
    private var spread = GridStyle.defaultSpread
    @AppStorage(SettingsStore.gridShapeKey, store: SettingsStore.defaults)
    private var shapeRaw = DayShape.roundedSquare.rawValue

    /// The style currently described by the controls — drives the live preview.
    private var draft: GridStyle {
        GridStyle(rampHex: rampHex, goalHex: goalHex, spread: spread,
                  shape: DayShape(rawValue: shapeRaw) ?? .roundedSquare)
    }

    // ColorPickers work in Color; storage is hex, so bridge the two.
    private var rampBinding: Binding<Color> {
        Binding(get: { Color(hex: rampHex) }, set: { rampHex = $0.hexString })
    }
    private var goalBinding: Binding<Color> {
        Binding(get: { Color(hex: goalHex) }, set: { goalHex = $0.hexString })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { preview }
                    .listRowBackground(Color.clear)

                Section {
                    palettePicker
                } header: {
                    Text("Palette").font(.system(.caption, design: .monospaced))
                }

                Section {
                    ColorPicker("Ramp", selection: rampBinding, supportsOpacity: false)
                        .font(.system(.body, design: .monospaced))
                    ColorPicker("Goal", selection: goalBinding, supportsOpacity: false)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Custom colors").font(.system(.caption, design: .monospaced))
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Slider(value: $spread, in: GridStyle.spreadRange)
                        Text("Higher = mid days recede; goal days pop.")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Spread").font(.system(.caption, design: .monospaced))
                }

                Section {
                    Picker("Day shape", selection: $shapeRaw) {
                        ForEach(DayShape.allCases) { shape in
                            Text(shape.label).tag(shape.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Day shape").font(.system(.caption, design: .monospaced))
                }

                Section {
                    Button("Reset to default", role: .destructive) {
                        rampHex = GridStyle.defaultRampHex
                        goalHex = GridStyle.defaultGoalHex
                        spread = GridStyle.defaultSpread
                        shapeRaw = DayShape.roundedSquare.rawValue
                    }
                    .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        // The widget reads the same App Group keys; refresh it as the user tweaks.
        .onChange(of: draft) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: - Live example grid

    private var preview: some View {
        VStack(spacing: 10) {
            Text("Example month")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            StepsMonthView(dailySteps: GridStyle.sampleMonth, style: draft)
                .padding(14)
                .frame(width: 200, height: 200)
                .background(Color("AppTextMuted").opacity(0.12))   // flat neutral surface
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Palette presets

    private var palettePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(GridPalette.presets) { palette in
                    let selected = palette.rampHex == rampHex && palette.goalHex == goalHex
                    Button {
                        rampHex = palette.rampHex
                        goalHex = palette.goalHex
                    } label: {
                        VStack(spacing: 6) {
                            swatch(palette)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(selected ? Color.primary : .clear, lineWidth: 2)
                                }
                            Text(palette.name)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// A mini ramp + goal swatch for a palette, generated the same way as the grid.
    private func swatch(_ palette: GridPalette) -> some View {
        let style = GridStyle(rampHex: palette.rampHex, goalHex: palette.goalHex,
                              spread: spread, shape: .roundedSquare)
        return HStack(spacing: 2) {
            ForEach([2_000, 5_000, 8_000], id: \.self) { steps in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(style.color(forSteps: steps, goal: dailyStepGoal, scheme: scheme))
                    .frame(width: 13, height: 13)
            }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(style.goalColor)
                .frame(width: 13, height: 13)
        }
        .padding(4)
    }
}
