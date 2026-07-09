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
import UIKit

struct GridCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @AppStorage(SettingsStore.gridRampHexKey, store: SettingsStore.defaults)
    private var rampHex = GridStyle.defaultRampHex
    @AppStorage(SettingsStore.gridGoalHexKey, store: SettingsStore.defaults)
    private var goalHex = GridStyle.defaultGoalHex
    @AppStorage(SettingsStore.gridTodayHexKey, store: SettingsStore.defaults)
    private var todayHex = GridStyle.defaultTodayHex
    @AppStorage(SettingsStore.gridCurveKey, store: SettingsStore.defaults)
    private var curveRaw = CurveShape.easeIn.rawValue
    @AppStorage(SettingsStore.gridSpreadKey, store: SettingsStore.defaults)
    private var spread = GridStyle.defaultSpread
    @AppStorage(SettingsStore.gridShapeKey, store: SettingsStore.defaults)
    private var shapeRaw = DayShape.roundedSquare.rawValue
    @AppStorage(SettingsStore.gridMarkerKey, store: SettingsStore.defaults)
    private var markerRaw = BestDayMarker.dot.rawValue

    private var curve: CurveShape { CurveShape(rawValue: curveRaw) ?? .easeIn }

    /// Transient "copied" confirmation shown after tapping the preview.
    @State private var didCopy = false

    /// The style currently described by the controls — drives the live preview.
    private var draft: GridStyle {
        GridStyle(rampHex: rampHex, goalHex: goalHex, todayHex: todayHex,
                  curve: curve, spread: spread,
                  shape: DayShape(rawValue: shapeRaw) ?? .roundedSquare,
                  marker: BestDayMarker(rawValue: markerRaw) ?? .dot)
    }

    // ColorPickers work in Color; storage is hex, so bridge the two.
    private var rampBinding: Binding<Color> {
        Binding(get: { Color(hex: rampHex) }, set: { rampHex = $0.hexString })
    }
    private var goalBinding: Binding<Color> {
        Binding(get: { Color(hex: goalHex) }, set: { goalHex = $0.hexString })
    }
    private var todayBinding: Binding<Color> {
        Binding(get: { Color(hex: todayHex) }, set: { todayHex = $0.hexString })
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
                    ColorPicker("Today", selection: todayBinding, supportsOpacity: false)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Custom colors").font(.system(.caption, design: .monospaced))
                } footer: {
                    Text("Today is the ring around the current day — separate from the goal color.")
                        .font(.system(.caption2, design: .monospaced))
                }

                Section {
                    curvePicker
                    VStack(alignment: .leading, spacing: 6) {
                        Slider(value: $spread, in: GridStyle.spreadRange) {
                            Text("Strength")
                        } minimumValueLabel: {
                            Text("subtle").font(.system(.caption2, design: .monospaced))
                        } maximumValueLabel: {
                            Text("strong").font(.system(.caption2, design: .monospaced))
                        }
                    }
                } header: {
                    Text("Curve").font(.system(.caption, design: .monospaced))
                } footer: {
                    Text("How a day's steps map to fill intensity.")
                        .font(.system(.caption2, design: .monospaced))
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
                    Picker("Best-day marker", selection: $markerRaw) {
                        ForEach(BestDayMarker.allCases) { marker in
                            Label(marker.label, systemImage: marker.symbol)
                                .tag(marker.rawValue)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Month's best day").font(.system(.caption, design: .monospaced))
                } footer: {
                    Text("Marks the highest-steps day of the month.")
                        .font(.system(.caption2, design: .monospaced))
                }

                Section {
                    Button("Reset to default", role: .destructive) {
                        rampHex = GridStyle.defaultRampHex
                        goalHex = GridStyle.defaultGoalHex
                        todayHex = GridStyle.defaultTodayHex
                        curveRaw = CurveShape.easeIn.rawValue
                        spread = GridStyle.defaultSpread
                        shapeRaw = DayShape.roundedSquare.rawValue
                        markerRaw = BestDayMarker.dot.rawValue
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
        .onChange(of: draft) { _, _ in
            WidgetCenter.shared.reloadAllTimelines()
            WatchSync.shared.push()   // mirror the new theme to the watch
        }
    }

    // MARK: - Live example grid

    private var preview: some View {
        VStack(spacing: 10) {
            Text(didCopy ? "Copied — paste in chat" : "Example month · tap to copy")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(didCopy ? draft.goalColor(for: scheme) : .secondary)
                .animation(.easeInOut(duration: 0.2), value: didCopy)
            StepsMonthView(dailySteps: GridStyle.sampleMonth, style: draft)
                .padding(14)
                .frame(width: 200, height: 200)
                .background(Color("AppTextMuted").opacity(0.12))   // flat neutral surface
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture { copyPayload() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    /// Copy the current color/shape settings to the clipboard as a shareable
    /// payload, so the exact look can be pasted into a chat as a reference.
    private func copyPayload() {
        UIPasteboard.general.string = draft.sharePayload
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { didCopy = false }
        }
    }

    // MARK: - Curve type

    /// Horizontal picker of curve shapes, each shown as a small sparkline of the
    /// response at the current strength so the effect is visible before choosing.
    private var curvePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CurveShape.allCases) { shape in
                    let selected = shape == curve
                    Button { curveRaw = shape.rawValue } label: {
                        VStack(spacing: 6) {
                            CurveSparkline(shape: shape, strength: spread)
                                .frame(width: 44, height: 30)
                                .padding(4)
                                .background(Color("AppTextMuted").opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(selected ? Color.primary : .clear, lineWidth: 2)
                                }
                            Text(shape.label)
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
                              curve: curve, spread: spread, shape: .roundedSquare, marker: .none)
        return HStack(spacing: 2) {
            ForEach([2_000, 5_000, 8_000], id: \.self) { steps in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(style.color(forSteps: steps, goal: dailyStepGoal, scheme: scheme))
                    .frame(width: 13, height: 13)
            }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(style.goalColor(for: scheme))
                .frame(width: 13, height: 13)
        }
        .padding(4)
    }
}

/// A tiny line plot of a `CurveShape` (input 0→1 across, intensity 0→1 up) used
/// as the visual in the curve-type picker.
private struct CurveSparkline: View {
    let shape: CurveShape
    let strength: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                let steps = 24
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let y = shape.apply(t, strength: strength)
                    let point = CGPoint(x: w * t, y: h * (1 - y))
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
            }
            .stroke(Color.primary,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

#Preview {
    GridCustomizationView()
}
