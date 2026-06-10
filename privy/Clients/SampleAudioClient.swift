import Dependencies
import Foundation

struct SampleAudioClient {
    var sampleURL: @Sendable () -> URL?

    static var live: Self {
        Self(
            sampleURL: {
                Bundle.main.url(forResource: "sample", withExtension: "mp3")
            }
        )
    }

    static var preview: Self {
        Self(sampleURL: { nil })
    }
}

extension SampleAudioClient: DependencyKey {
    static let liveValue = live
    static let previewValue = preview
}

extension DependencyValues {
    var sampleAudioClient: SampleAudioClient {
        get { self[SampleAudioClient.self] }
        set { self[SampleAudioClient.self] = newValue }
    }
}
