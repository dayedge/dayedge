import SwiftUI

/// The onboarding window's content: the step, and a fixed footer — Back on
/// the left, a quiet "2 of 5", the step's actions on the right (the
/// primary always in the same place). Return runs the primary action, Esc
/// goes back.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(model.step)
                .transition(.opacity)
            Rectangle().fill(OnboardingStyle.line).frame(height: 1)
            footer
        }
        .background(OnboardingStyle.background)
        .animation(.easeInOut(duration: 0.2), value: model.step)
        .sheet(isPresented: $model.isChoosingCity, onDismiss: model.cityChoiceClosed) {
            WeatherLocationSheet()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: OnboardingWelcomeStep()
        case .calendar: OnboardingPromptStep.calendar(model.state)
        case .reminders: OnboardingPromptStep.reminders(model.state)
        case .weather: OnboardingPromptStep.weather(model.state)
        case .ready: OnboardingReadyStep { model.open($0) }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.flow.canGoBack {
                Button(L10n.tr("onboardingview.back", "Back")) { model.back() }
                    .buttonStyle(OnboardingQuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if let secondary = model.secondaryTitle {
                Button(secondary) { Task { await model.secondary() } }
                    .buttonStyle(OnboardingQuietButtonStyle())
            }
            Button(model.primaryTitle) { Task { await model.primary() } }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .disabled(model.isWorking)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        // Centred on the window, whatever the buttons on either side.
        .overlay {
            Text(L10n.tr("onboarding.progress", "\(model.flow.position) of \(OnboardingFlow.count)"))
                .font(OnboardingStyle.small)
                .foregroundStyle(OnboardingStyle.quiet)
                .monospacedDigit()
                .accessibilityLabel(L10n.tr("onboardingview.step.of", "Step \(String(describing: model.flow.position)) of \(String(describing: OnboardingFlow.count))"))
        }
    }
}
