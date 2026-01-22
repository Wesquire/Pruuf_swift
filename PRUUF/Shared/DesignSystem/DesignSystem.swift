import SwiftUI
import UIKit

// MARK: - Design System
// Comprehensive design system for PRUUF iOS app
// Implements Section 4.4: UI/UX Design Specifications

// MARK: - Color Palette

/// App color palette using iOS system colors for automatic dark mode adaptation
enum AppColors {
    // MARK: Primary Colors

    /// Primary accent color - iOS Blue (#007AFF)
    static let primary = Color(UIColor.systemBlue)

    /// Success color - iOS Green (#34C759)
    static let success = Color(UIColor.systemGreen)

    /// Warning color - iOS Orange (#FF9500)
    static let warning = Color(UIColor.systemOrange)

    /// Error color - iOS Red (#FF3B30)
    static let error = Color(UIColor.systemRed)

    // MARK: Background Colors

    /// Screen background - iOS Gray 6 (#F2F2F7 light / #1C1C1E dark)
    static let background = Color(UIColor.systemGroupedBackground)

    /// Card background - White (#FFFFFF light / #2C2C2E dark)
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)

    /// Secondary background - for nested content
    static let secondaryBackground = Color(UIColor.tertiarySystemGroupedBackground)

    // MARK: Text Colors

    /// Primary text color - Black (#000000 light / White dark)
    static let textPrimary = Color(UIColor.label)

    /// Secondary text color - Gray (#8E8E93)
    static let textSecondary = Color(UIColor.secondaryLabel)

    /// Tertiary text color - lighter gray for hints
    static let textTertiary = Color(UIColor.tertiaryLabel)

    /// Placeholder text color
    static let textPlaceholder = Color(UIColor.placeholderText)

    // MARK: Semantic Colors

    /// Separator/divider color
    static let separator = Color(UIColor.separator)

    /// Tint color - matches primary
    static let tint = Color(UIColor.systemBlue)

    /// Fill color - for UI elements
    static let fill = Color(UIColor.systemFill)

    // MARK: Status Colors (with semantic meaning)

    /// Ping completed status
    static let pingCompleted = Color(UIColor.systemGreen)

    /// Ping pending status
    static let pingPending = Color(UIColor.systemYellow)

    /// Ping missed status
    static let pingMissed = Color(UIColor.systemRed)

    /// On break status
    static let onBreak = Color(UIColor.systemGray)

    // MARK: UIColor Accessors (for UIKit components)

    enum UIColors {
        static let primary = UIColor.systemBlue
        static let success = UIColor.systemGreen
        static let warning = UIColor.systemOrange
        static let error = UIColor.systemRed
        static let background = UIColor.systemGroupedBackground
        static let cardBackground = UIColor.secondarySystemGroupedBackground
        static let textPrimary = UIColor.label
        static let textSecondary = UIColor.secondaryLabel
    }
}

// MARK: - Typography

/// Typography styles using iOS system fonts (SF Pro)
enum AppTypography {

    // MARK: Headings (SF Pro Display)

    /// Large title - 34pt Bold
    static let largeTitle = Font.largeTitle.weight(.bold)

    /// Title 1 - 28pt Bold
    static let title1 = Font.title.weight(.bold)

    /// Title 2 - 22pt Bold
    static let title2 = Font.title2.weight(.bold)

    /// Title 3 - 20pt Semibold
    static let title3 = Font.title3.weight(.semibold)

    /// Headline - 17pt Semibold
    static let headline = Font.headline.weight(.semibold)

    // MARK: Body (SF Pro Text)

    /// Body - 17pt Regular
    static let body = Font.body

    /// Body Bold - 17pt Semibold
    static let bodyBold = Font.body.weight(.semibold)

    /// Callout - 16pt Regular
    static let callout = Font.callout

    /// Subheadline - 15pt Regular
    static let subheadline = Font.subheadline

    /// Subheadline Bold - 15pt Medium
    static let subheadlineBold = Font.subheadline.weight(.medium)

    // MARK: Captions (SF Pro Text Light)

    /// Footnote - 13pt Regular
    static let footnote = Font.footnote

    /// Caption 1 - 12pt Regular
    static let caption1 = Font.caption

    /// Caption 2 - 11pt Regular
    static let caption2 = Font.caption2

    // MARK: Code/Monospace (SF Mono)

    /// Monospace for codes - 32pt Medium (for 6-digit codes)
    static let codeDisplay = Font.system(size: 32, weight: .medium, design: .monospaced)

    /// Monospace for codes - 40pt Medium (large display)
    static let codeLarge = Font.system(size: 40, weight: .medium, design: .monospaced)

    /// Monospace for inline code - 15pt Regular
    static let codeInline = Font.system(size: 15, weight: .regular, design: .monospaced)

    // MARK: Custom Sizes

    /// Hero title for onboarding - 28pt Bold
    static let heroTitle = Font.system(size: 28, weight: .bold, design: .default)

    /// Button text - 17pt Semibold
    static let button = Font.system(size: 17, weight: .semibold, design: .default)

    /// Small button text - 15pt Medium
    static let buttonSmall = Font.system(size: 15, weight: .medium, design: .default)

    /// Tab label - 10pt Medium
    static let tabLabel = Font.system(size: 10, weight: .medium, design: .default)
}

// MARK: - Spacing

/// Spacing constants for consistent layout
enum AppSpacing {
    /// Extra small spacing - 4pt
    static let xs: CGFloat = 4

    /// Small spacing - 8pt
    static let sm: CGFloat = 8

    /// Medium spacing / Element spacing - 12pt
    static let md: CGFloat = 12

    /// Large spacing / Screen & Card padding - 16pt
    static let lg: CGFloat = 16

    /// Extra large spacing - 20pt
    static let xl: CGFloat = 20

    /// Section spacing - 24pt
    static let section: CGFloat = 24

    /// Large section spacing - 32pt
    static let sectionLarge: CGFloat = 32

    // MARK: Semantic Spacing

    /// Screen horizontal padding - 16pt
    static let screenPadding: CGFloat = 16

    /// Card internal padding - 16pt
    static let cardPadding: CGFloat = 16

    /// Element spacing (between items) - 12pt
    static let elementSpacing: CGFloat = 12

    /// Section spacing (between groups) - 24pt
    static let sectionSpacing: CGFloat = 24

    /// Minimum touch target - 44pt
    static let minTouchTarget: CGFloat = 44
}

// MARK: - Corner Radius

/// Corner radius constants
enum AppCornerRadius {
    /// Small radius - 4pt
    static let small: CGFloat = 4

    /// Medium radius - 8pt
    static let medium: CGFloat = 8

    /// Large radius - 12pt
    static let large: CGFloat = 12

    /// Extra large radius - 16pt
    static let extraLarge: CGFloat = 16

    /// Card radius - 16pt
    static let card: CGFloat = 16

    /// Button radius - 12pt
    static let button: CGFloat = 12

    /// Pill/Capsule - full rounding
    static let pill: CGFloat = .infinity
}

// MARK: - Shadows

/// Shadow styles for elevation
enum AppShadow {
    /// Light shadow for subtle elevation
    static func light() -> some View {
        Color.black.opacity(0.05)
    }

    /// Medium shadow for cards
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowY: CGFloat = 2
    static let cardShadowOpacity: Double = 0.1

    /// Heavy shadow for modals
    static let modalShadowRadius: CGFloat = 16
    static let modalShadowY: CGFloat = 4
    static let modalShadowOpacity: Double = 0.15
}

// MARK: - Animation

/// Animation configurations
enum AppAnimation {
    /// Standard spring animation for most interactions
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    /// Quick spring for buttons
    static let buttonSpring = Animation.spring(response: 0.25, dampingFraction: 0.7)

    /// Ease in out for transitions
    static let easeInOut = Animation.easeInOut(duration: 0.25)

    /// Slow ease for loading states
    static let slowEase = Animation.easeInOut(duration: 0.5)

    /// Button press scale factor - 0.95
    static let buttonPressScale: CGFloat = 0.95

    /// Card transition animation
    static let cardTransition = AnyTransition.move(edge: .bottom).combined(with: .opacity)

    /// Fade transition
    static let fade = AnyTransition.opacity

    /// Slide up transition
    static let slideUp = AnyTransition.move(edge: .bottom)

    /// Slide down transition
    static let slideDown = AnyTransition.move(edge: .top)
}

// MARK: - View Modifiers

/// Button press animation modifier
struct ButtonPressModifier: ViewModifier {
    @State private var isPressed = false
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? AppAnimation.buttonPressScale : 1.0)
            .animation(AppAnimation.buttonSpring, value: isPressed)
            .onTapGesture {
                isPressed = true
                Haptics.impact(style: .light)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                    action()
                }
            }
    }
}

/// Card style modifier
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.cardPadding)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCornerRadius.card)
            .shadow(
                color: Color.black.opacity(AppShadow.cardShadowOpacity),
                radius: AppShadow.cardShadowRadius,
                x: 0,
                y: AppShadow.cardShadowY
            )
    }
}

/// Primary button style
struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background(isDisabled ? AppColors.textSecondary : AppColors.primary)
            .cornerRadius(AppCornerRadius.button)
            .scaleEffect(configuration.isPressed ? AppAnimation.buttonPressScale : 1.0)
            .animation(AppAnimation.buttonSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue {
                    Haptics.impact(style: .light)
                }
            }
    }
}

/// Secondary button style (outline)
struct SecondaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundColor(isDisabled ? AppColors.textSecondary : AppColors.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.button)
                    .stroke(isDisabled ? AppColors.textSecondary : AppColors.primary, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? AppAnimation.buttonPressScale : 1.0)
            .animation(AppAnimation.buttonSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue {
                    Haptics.impact(style: .light)
                }
            }
    }
}

/// Destructive button style
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background(AppColors.error)
            .cornerRadius(AppCornerRadius.button)
            .scaleEffect(configuration.isPressed ? AppAnimation.buttonPressScale : 1.0)
            .animation(AppAnimation.buttonSpring, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { newValue in
                if newValue {
                    Haptics.impact(style: .medium)
                }
            }
    }
}

/// Minimum touch target modifier
struct MinTouchTargetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minWidth: AppSpacing.minTouchTarget, minHeight: AppSpacing.minTouchTarget)
    }
}

/// Loading overlay modifier
struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    let message: String?

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)

            if isLoading {
                ZStack {
                    // Blur background
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    // Loading indicator
                    VStack(spacing: AppSpacing.md) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)

                        if let message = message {
                            Text(message)
                                .font(AppTypography.subheadline)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(AppSpacing.section)
                    .background(
                        Color(UIColor.systemGray5)
                            .opacity(0.9)
                            .blur(radius: 1)
                    )
                    .cornerRadius(AppCornerRadius.large)
                }
                .transition(.opacity)
            }
        }
        .animation(AppAnimation.easeInOut, value: isLoading)
    }
}

/// Success checkmark animation view
struct SuccessCheckmarkView: View {
    @State private var showCheckmark = false
    @State private var scale: CGFloat = 0.5

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColors.success)
                .frame(width: 80, height: 80)
                .scaleEffect(scale)

            Image(systemName: "checkmark")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
                .opacity(showCheckmark ? 1 : 0)
                .scaleEffect(showCheckmark ? 1 : 0.5)
        }
        .onAppear {
            withAnimation(AppAnimation.spring) {
                scale = 1.0
            }
            withAnimation(AppAnimation.spring.delay(0.1)) {
                showCheckmark = true
            }
            Haptics.success()
        }
    }
}

// MARK: - Accessibility

/// Accessibility configuration
enum AppAccessibility {
    /// Minimum color contrast ratio (WCAG AA)
    static let minContrastRatio: Double = 4.5

    /// Check if user prefers reduced motion
    @MainActor
    static var prefersReducedMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Get animation based on reduce motion preference
    @MainActor
    static func animation(_ animation: Animation) -> Animation? {
        prefersReducedMotion ? nil : animation
    }
}

/// VoiceOver accessible button modifier
struct AccessibleButtonModifier: ViewModifier {
    let label: String
    let hint: String?

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }
}

/// Dynamic Type support modifier
struct DynamicTypeModifier: ViewModifier {
    @Environment(\.sizeCategory) var sizeCategory

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply card styling
    func cardStyle() -> some View {
        modifier(CardModifier())
    }

    /// Apply button press animation
    func buttonPress(action: @escaping () -> Void) -> some View {
        modifier(ButtonPressModifier(action: action))
    }

    /// Ensure minimum touch target size
    func minTouchTarget() -> some View {
        modifier(MinTouchTargetModifier())
    }

    /// Apply loading overlay
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, message: message))
    }

    /// Apply VoiceOver accessibility
    func accessibleButton(label: String, hint: String? = nil) -> some View {
        modifier(AccessibleButtonModifier(label: label, hint: hint))
    }

    /// Apply dynamic type support
    func supportsDynamicType() -> some View {
        modifier(DynamicTypeModifier())
    }

    /// Apply conditional reduce motion animation
    @ViewBuilder
    func reduceMotionAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self
        } else {
            self.animation(animation, value: value)
        }
    }

    /// Apply screen padding
    func screenPadding() -> some View {
        self.padding(.horizontal, AppSpacing.screenPadding)
    }

    /// Apply section spacing
    func sectionSpacing() -> some View {
        self.padding(.vertical, AppSpacing.sectionSpacing)
    }
}

// MARK: - Preview Provider

#if DEBUG
struct DesignSystemPreview: View {
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.section) {
                // Colors
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Colors")
                        .font(AppTypography.title2)

                    HStack(spacing: AppSpacing.sm) {
                        colorSwatch(AppColors.primary, name: "Primary")
                        colorSwatch(AppColors.success, name: "Success")
                        colorSwatch(AppColors.warning, name: "Warning")
                        colorSwatch(AppColors.error, name: "Error")
                    }
                }

                // Typography
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Typography")
                        .font(AppTypography.title2)

                    Text("Large Title").font(AppTypography.largeTitle)
                    Text("Title 1").font(AppTypography.title1)
                    Text("Body Text").font(AppTypography.body)
                    Text("123456").font(AppTypography.codeDisplay)
                    Text("Caption Text").font(AppTypography.caption1)
                }

                // Buttons
                VStack(spacing: AppSpacing.md) {
                    Text("Buttons")
                        .font(AppTypography.title2)

                    Button("Primary Button") {}
                        .buttonStyle(PrimaryButtonStyle())

                    Button("Secondary Button") {}
                        .buttonStyle(SecondaryButtonStyle())

                    Button("Destructive Button") {}
                        .buttonStyle(DestructiveButtonStyle())
                }

                // Card
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Cards")
                        .font(AppTypography.title2)

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Card Title")
                            .font(AppTypography.headline)
                        Text("This is a card with the standard styling applied.")
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .cardStyle()
                }

                // Success Animation
                VStack(spacing: AppSpacing.md) {
                    Text("Success Animation")
                        .font(AppTypography.title2)

                    SuccessCheckmarkView()
                }
            }
            .screenPadding()
        }
        .background(AppColors.background)
    }

    private func colorSwatch(_ color: Color, name: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(color)
                .frame(width: 60, height: 60)
            Text(name)
                .font(AppTypography.caption2)
        }
    }
}

struct DesignSystemPreview_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DesignSystemPreview()
                .preferredColorScheme(.light)
            DesignSystemPreview()
                .preferredColorScheme(.dark)
        }
    }
}
#endif
