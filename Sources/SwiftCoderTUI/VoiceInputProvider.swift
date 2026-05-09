import Foundation

// MARK: - VoiceInputProvider

/// An injectable provider that delivers a speech-to-text transcription.
///
/// The host application implements this protocol using whatever speech-recognition
/// stack it prefers (e.g. Apple's `Speech` framework on macOS).  `swift-coder-tui`
/// itself does not import `Speech`, keeping the library free of platform-specific
/// audio entitlements.
///
/// Usage:
/// ```swift
/// struct MySpeechProvider: VoiceInputProvider {
///     func transcribe() async throws -> String {
///         return try await VoiceInput.transcribe()
///     }
/// }
///
/// let config = AppConfig(
///     ...
///     voiceInputProvider: MySpeechProvider()
/// )
/// ```
///
/// When no provider is configured, `Ctrl+V` in the `Renderer` is silently ignored.
public protocol VoiceInputProvider: Sendable {
    /// Start recording and return the final transcription when the user stops speaking.
    ///
    /// - Throws: Any error from the underlying speech recognition stack.
    ///   The `Renderer` will surface the `localizedDescription` to the user.
    func transcribe() async throws -> String
}
