import MacStartCore
import SwiftUI

/// What the overlay's views can ask the controller to do.
struct OverlayActions {
    let launch: @MainActor (InstalledApp) -> Void
    let dismiss: @MainActor () -> Void
    let showPage: @MainActor (Int) -> Void
}

/// The overlay's content: the paged grid and the page dots, or the loading and empty states.
struct OverlayView: View {
    let store: LayoutStore
    @Bindable var state: OverlayState
    let icons: IconProvider
    let actions: OverlayActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let metrics = GridMetrics(
                overlaySize: geometry.size,
                columns: store.preferences.gridColumns,
                rows: store.preferences.gridRows
            )
            ZStack {
                Color.black.opacity(0.2)
                    .contentShape(Rectangle())
                    .onTapGesture { actions.dismiss() }
                content(metrics: metrics)
            }
        }
        .ignoresSafeArea()
        .scaleEffect(state.isPresented || reduceMotion ? 1 : 1.06)
        .animation(
            reduceMotion ? nil : .easeOut(duration: OverlayController.animationDuration),
            value: state.isPresented
        )
        .onChange(of: store.layout.pages.count) { _, pageCount in
            state.clampPage(toPageCount: pageCount)
        }
    }

    @ViewBuilder
    private func content(metrics: GridMetrics) -> some View {
        if !store.hasLoaded {
            ProgressView()
                .controlSize(.large)
        } else if store.layout.placedAppIDs.isEmpty {
            Text("No apps found")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.85))
                .allowsHitTesting(false)
        } else {
            PagedGridView(
                pages: store.layout.pages,
                currentPage: $state.currentPage,
                metrics: metrics,
                store: store,
                icons: icons,
                actions: actions
            )
            if store.layout.pages.count > 1 {
                VStack {
                    Spacer()
                    PageIndicator(
                        pageCount: store.layout.pages.count,
                        currentPage: state.currentPage ?? 0,
                        select: { actions.showPage($0) }
                    )
                    .padding(.bottom, metrics.bottomInset * 0.35)
                }
            }
        }
    }
}
