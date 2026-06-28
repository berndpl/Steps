//
//  StepsWatchWidget.swift
//  StepsWatchWidget
//
//  The watchOS complications bundle. Reuses the shared accessory widgets
//  (Steps Ring, Tiny Steps) — the same code that drives the iOS lock-screen
//  widgets — exposed here as watch-face complications.
//

import WidgetKit
import SwiftUI

@main
struct StepsWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        StepsRingWidget()
        TinyStepsWidget()
    }
}
