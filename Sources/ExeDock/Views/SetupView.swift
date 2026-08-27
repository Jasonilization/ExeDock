import SwiftUI

/// Shown while `SetupCoordinator` checks for / prepares the Sikarugir engine at launch.
struct SetupView: View {
    @ObservedObject var setup: SetupCoordinator

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: iconName)
                .font(.system(size: 52))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.title2)
                .bold()
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if showsSpinner {
                Group {
                    if let fraction = progressFraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView(value: nil as Double?)
                    }
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
                .padding(.top, 4)
            }
            if showsRetryButton {
                Button("Check Again") {
                    setup.runSetup()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch setup.stage {
        case .checking: return "Checking for the Sikarugir engine…"
        case .extractingEngine: return "Preparing the Sikarugir engine…"
        case .initializingBottle: return "Setting up your bottle…"
        case .waitingForSikarugirCreator: return "Waiting for Sikarugir Creator…"
        case .missingSikarugirCreator: return "Sikarugir Creator isn't installed"
        case .failed: return "Setup ran into a problem"
        case .ready: return "Ready"
        }
    }

    private var subtitle: String {
        switch setup.stage {
        case .checking:
            return "Looking for a Wine engine Sikarugir Creator has already downloaded."
        case .extractingEngine:
            return "Copying the engine into ExeDock's own bottle - this only happens once."
        case .initializingBottle:
            return "Creating ExeDock's own Wine prefix."
        case .waitingForSikarugirCreator:
            return "ExeDock opened Sikarugir Creator so it can download a Wine engine. Let it finish downloading - ExeDock will pick it up automatically, no need to relaunch."
        case .missingSikarugirCreator:
            return "ExeDock runs on the Sikarugir engine and won't guess at a download for it. Install Sikarugir Creator, let it download an engine once, then check again here."
        case .failed(let message):
            return message
        case .ready:
            return ""
        }
    }

    private var iconName: String {
        switch setup.stage {
        case .missingSikarugirCreator: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        case .waitingForSikarugirCreator: return "arrow.triangle.2.circlepath"
        default: return "gearshape.2"
        }
    }

    private var iconColor: Color {
        switch setup.stage {
        case .missingSikarugirCreator, .failed: return .orange
        default: return .secondary
        }
    }

    private var progressFraction: Double? {
        switch setup.stage {
        case .checking: return 0.15
        case .extractingEngine: return 0.45
        case .initializingBottle: return 0.8
        case .waitingForSikarugirCreator: return nil
        case .missingSikarugirCreator, .failed, .ready: return nil
        }
    }

    private var showsSpinner: Bool {
        switch setup.stage {
        case .checking, .extractingEngine, .initializingBottle, .waitingForSikarugirCreator: return true
        case .missingSikarugirCreator, .failed, .ready: return false
        }
    }

    private var showsRetryButton: Bool {
        switch setup.stage {
        case .missingSikarugirCreator, .failed: return true
        default: return false
        }
    }
}
