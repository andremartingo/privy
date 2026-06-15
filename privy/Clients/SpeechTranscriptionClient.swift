import Dependencies
import FluidAudio
import Foundation
import Speech
import SwiftUI

struct SpeechTranscriptionClient {
    var makeTranscriber: @MainActor @Sendable (Binding<Memo>) -> SpokenWordTranscriber
}

extension SpeechTranscriptionClient {
    static var live: Self {
        Self(
            makeTranscriber: { memo in
                SpeechTranscriptionService.shared.makeTranscriber(memo: memo)
            }
        )
    }

    static var preview: Self {
        Self(
            makeTranscriber: { memo in
                SpokenWordTranscriber(memo: memo)
            }
        )
    }
}

extension SpeechTranscriptionClient: DependencyKey {
    static var liveValue: Self {
        #if DEBUG
            preview
        #else
            live
        #endif
    }
    static let previewValue = preview
}

extension DependencyValues {
    var speechTranscriptionClient: SpeechTranscriptionClient {
        get { self[SpeechTranscriptionClient.self] }
        set { self[SpeechTranscriptionClient.self] = newValue }
    }
}

@MainActor
private final class SpeechTranscriptionService {
    static let shared = SpeechTranscriptionService()

    private init() {}

    func makeTranscriber(memo: Binding<Memo>) -> SpokenWordTranscriber {
        SpokenWordTranscriber(memo: memo)
    }
}

@Observable
@MainActor
final class SpokenWordTranscriber {
    private enum ParakeetV3 {
        static let bundledModelDirectory = "parakeet-tdt-0.6b-v3"
        static let bundledModelSubdirectory = "ModelAssets"
        static let requiredBundleEntries = [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecisionv3.mlmodelc",
            "parakeet_vocab.json",
        ]
    }

    private let inputSequence: AsyncStream<AnalyzerInput>
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), any Error>?
    private var parakeetManager: AsrManager?
    private var parakeetLoadTask: Task<AsrManager, any Error>?

    static let green = Color(red: 0.36, green: 0.69, blue: 0.55).opacity(0.8)  // #5DAF8D

    // The format of the audio.
    var analyzerFormat: AVAudioFormat?

    let converter = BufferConverter()
    var downloadProgress: Progress?
    var modelPreparationProgress = 0.0

    let memo: Binding<Memo>

    var volatileTranscript: AttributedString = ""
    var finalizedTranscript: AttributedString = ""
    var onTranscriptChanged: ((AttributedString, AttributedString) -> Void)?

    static let locale = Locale(
        components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates))
    
    // Fallback locales to try when the preferred locale isn't available
    static let fallbackLocales = [
        Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedStates)),
        Locale(components: .init(languageCode: .english, script: nil, languageRegion: .unitedKingdom)),
        Locale(components: .init(languageCode: .english, script: nil, languageRegion: .canada)),
        Locale(components: .init(languageCode: .english, script: nil, languageRegion: .australia)),
        Locale(identifier: "en-US"),
        Locale(identifier: "en"),
        Locale.current
    ]

    init(memo: Binding<Memo>) {
        print(
            "[Transcriber DEBUG]: Initializing local Parakeet v3 transcriber with locale hint: \(SpokenWordTranscriber.locale.identifier)"
        )
        self.memo = memo
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = continuation
    }

    func transcribeAudioFile(_ url: URL) async throws {
        let manager = try await prepareParakeetManager()
        modelPreparationProgress = 100

        volatileTranscript = AttributedString("Transcribing locally...")
        volatileTranscript.foregroundColor = .purple.opacity(0.5)
        onTranscriptChanged?(finalizedTranscript, volatileTranscript)

        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(url, decoderState: &decoderState)
        let transcript = AttributedString(result.text)

        finalizedTranscript = transcript
        volatileTranscript = ""
        memo.text.wrappedValue = transcript
        onTranscriptChanged?(finalizedTranscript, volatileTranscript)

        print(
            "[Transcriber DEBUG]: Parakeet v3 transcription completed in \(result.processingTime)s, rtfx: \(result.rtfx)"
        )
    }

    private func prepareParakeetManager() async throws -> AsrManager {
        if let parakeetManager {
            return parakeetManager
        }

        if let parakeetLoadTask {
            let manager = try await parakeetLoadTask.value
            self.parakeetManager = manager
            return manager
        }

        modelPreparationProgress = 0
        let loadTask = Task<AsrManager, any Error> {
            let models = try await Self.loadParakeetV3Models()
            return AsrManager(config: Self.parakeetConfig, models: models)
        }
        parakeetLoadTask = loadTask

        do {
            let manager = try await loadTask.value
            parakeetManager = manager
            parakeetLoadTask = nil
            return manager
        } catch {
            parakeetLoadTask = nil
            throw error
        }
    }

    nonisolated private static var parakeetConfig: ASRConfig {
        ASRConfig(
            sampleRate: 16_000,
            parallelChunkConcurrency: 4,
            streamingEnabled: true,
            melChunkContext: false
        )
    }

    nonisolated private static func loadParakeetV3Models() async throws -> AsrModels {
        if let bundledModelURL = try bundledParakeetV3ModelURL() {
            print("[Transcriber DEBUG]: Loading bundled Parakeet v3 model from \(bundledModelURL.path)")
            return try await AsrModels.load(
                from: bundledModelURL,
                configuration: AsrModels.defaultConfiguration(),
                version: .v3,
                encoderPrecision: .int8
            )
        }

        print("[Transcriber DEBUG]: Bundled Parakeet v3 model not found; using FluidAudio cache")
        return try await AsrModels.downloadAndLoad(
            configuration: AsrModels.defaultConfiguration(),
            version: .v3,
            encoderPrecision: .int8
        )
    }

    nonisolated private static func bundledParakeetV3ModelURL() throws -> URL? {
        if let nestedURL = Bundle.main.url(
            forResource: ParakeetV3.bundledModelDirectory,
            withExtension: nil,
            subdirectory: ParakeetV3.bundledModelSubdirectory
        ),
            AsrModels.modelsExist(
                at: nestedURL,
                version: .v3,
                encoderPrecision: .int8
            )
        {
            return nestedURL
        }

        guard let resourceURL = Bundle.main.resourceURL,
            bundleRootContainsParakeetV3Model(resourceURL)
        else {
            return nil
        }

        let linkedURL = try prepareBundledParakeetV3Links(from: resourceURL)
        guard AsrModels.modelsExist(
            at: linkedURL,
            version: .v3,
            encoderPrecision: .int8
        ) else {
            return nil
        }

        return linkedURL
    }

    nonisolated private static func bundleRootContainsParakeetV3Model(_ rootURL: URL) -> Bool {
        ParakeetV3.requiredBundleEntries.allSatisfy { entry in
            FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(entry).path)
        }
    }

    nonisolated private static func prepareBundledParakeetV3Links(from rootURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let linksRootURL = appSupportURL.appendingPathComponent("BundledModelLinks", isDirectory: true)
        let linkedModelURL = linksRootURL.appendingPathComponent(
            ParakeetV3.bundledModelDirectory,
            isDirectory: true
        )

        if AsrModels.modelsExist(at: linkedModelURL, version: .v3, encoderPrecision: .int8) {
            return linkedModelURL
        }

        if fileManager.fileExists(atPath: linkedModelURL.path) {
            try fileManager.removeItem(at: linkedModelURL)
        }

        try fileManager.createDirectory(at: linkedModelURL, withIntermediateDirectories: true)

        for entry in ParakeetV3.requiredBundleEntries {
            let sourceURL = rootURL.appendingPathComponent(entry)
            let destinationURL = linkedModelURL.appendingPathComponent(entry)

            do {
                try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
            } catch {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
        }

        return linkedModelURL
    }

    func setUpTranscriber() async throws {
        print("[Transcriber DEBUG]: Starting transcriber setup...")

        transcriber = SpeechTranscriber(
            locale: SpokenWordTranscriber.locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange])

        guard let transcriber else {
            print("[Transcriber DEBUG]: ERROR - Failed to create SpeechTranscriber")
            throw TranscriptionError.failedToSetupRecognitionStream
        }
        print("[Transcriber DEBUG]: SpeechTranscriber created successfully")

        analyzer = SpeechAnalyzer(modules: [transcriber])
        print("[Transcriber DEBUG]: SpeechAnalyzer created with transcriber module")

        do {
            print("[Transcriber DEBUG]: Ensuring model is available...")
            try await ensureModel(transcriber: transcriber, locale: SpokenWordTranscriber.locale)
            print("[Transcriber DEBUG]: Model check completed successfully")
        } catch let error as TranscriptionError {
            print("[Transcriber DEBUG]: Model setup failed with error: \(error.descriptionString)")
            throw error
        }

        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [
            transcriber
        ])
        print("[Transcriber DEBUG]: Best audio format: \(String(describing: analyzerFormat))")

        guard analyzerFormat != nil else {
            print("[Transcriber DEBUG]: ERROR - No compatible audio format found")
            throw TranscriptionError.invalidAudioDataType
        }

        recognizerTask = Task {
            print("[Transcriber DEBUG]: Starting recognition task...")
            do {
                print("[Transcriber DEBUG]: About to start listening for transcription results...")
                var resultCount = 0
                for try await case let result in transcriber.results {
                    resultCount += 1
                    let text = result.text
                    if result.isFinal {
                        finalizedTranscript += text
                        volatileTranscript = ""
                        updateMemoWithNewText(withFinal: text)
                        onTranscriptChanged?(finalizedTranscript, volatileTranscript)
                    } else {
                        volatileTranscript = text
                        volatileTranscript.foregroundColor = .purple.opacity(0.5)
                        onTranscriptChanged?(finalizedTranscript, volatileTranscript)
                    }
                }
                print(
                    "[Transcriber DEBUG]: Recognition task completed normally after \(resultCount) results"
                )
            } catch {
                print(
                    "[Transcriber DEBUG]: ERROR - Speech recognition failed: \(error.localizedDescription)"
                )
            }
        }

        do {
            try await analyzer?.start(inputSequence: inputSequence)
            print("[Transcriber DEBUG]: SpeechAnalyzer started successfully")
        } catch {
            print(
                "[Transcriber DEBUG]: ERROR - Failed to start SpeechAnalyzer: \(error.localizedDescription)"
            )
            throw error
        }
    }

    func updateMemoWithNewText(withFinal str: AttributedString) {
        print("[Transcriber DEBUG]: Updating memo with finalized text: '\(str)'")
        memo.text.wrappedValue.append(str)
        print(
            "[Transcriber DEBUG]: Memo updated, current memo text length: \(memo.text.wrappedValue.characters.count)"
        )
    }

    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer) async throws {
        guard let analyzerFormat else {
            print("[Transcriber DEBUG]: ERROR - No analyzer format available")
            throw TranscriptionError.invalidAudioDataType
        }

        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)

        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }

    public func finishTranscribing() async throws {
        print("[Transcriber DEBUG]: Finishing transcription...")
        inputBuilder.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        print("[Transcriber DEBUG]: Transcription finished and cleaned up")
    }

    /// Reset the transcriber for a new recording session
    /// This clears existing transcripts when restarting recording
    public func reset() {
        print("[Transcriber DEBUG]: Resetting transcriber - clearing transcripts")
        volatileTranscript = ""
        finalizedTranscript = ""
        modelPreparationProgress = 0
        onTranscriptChanged?(finalizedTranscript, volatileTranscript)
    }
}

extension SpokenWordTranscriber {
    public func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        print("[Transcriber DEBUG]: Checking model availability for locale: \(locale.identifier)")

        // First try to download/install any needed assets
        print("[Transcriber DEBUG]: Checking for required downloads...")
        try await downloadIfNeeded(for: transcriber)
        
        // Check supported locales
        let supportedLocales = await SpeechTranscriber.supportedLocales
        print("[Transcriber DEBUG]: Found \(supportedLocales.count) supported locales")
        
        // If no locales are supported, try fallback approach
        if supportedLocales.isEmpty {
            print("[Transcriber DEBUG]: WARNING - No supported locales found. Trying fallback locales...")
            
            // Try each fallback locale
            for fallbackLocale in SpokenWordTranscriber.fallbackLocales {
                print("[Transcriber DEBUG]: Trying fallback locale: \(fallbackLocale.identifier)")
                do {
                    try await reserveLocale(locale: fallbackLocale)
                    print("[Transcriber DEBUG]: Successfully allocated fallback locale: \(fallbackLocale.identifier)")
                    return
                } catch {
                    print("[Transcriber DEBUG]: Fallback locale \(fallbackLocale.identifier) failed: \(error)")
                    continue
                }
            }
            
            print("[Transcriber DEBUG]: All fallback locales failed")
            throw TranscriptionError.localeNotSupported
        }
        
        // Check if preferred locale is supported
        var localeToUse = locale
        if await supported(locale: locale) {
            print("[Transcriber DEBUG]: Preferred locale is supported: \(locale.identifier)")
        } else {
            print("[Transcriber DEBUG]: Preferred locale not supported, trying fallbacks...")
            
            // Try to find a supported fallback locale
            var foundSupportedLocale = false
            for fallbackLocale in SpokenWordTranscriber.fallbackLocales {
                if await supported(locale: fallbackLocale) {
                    print("[Transcriber DEBUG]: Found supported fallback locale: \(fallbackLocale.identifier)")
                    localeToUse = fallbackLocale
                    foundSupportedLocale = true
                    break
                }
            }
            
            guard foundSupportedLocale else {
                print("[Transcriber DEBUG]: ERROR - No supported locale found among fallbacks")
                throw TranscriptionError.localeNotSupported
            }
        }

        if await installed(locale: localeToUse) {
            print("[Transcriber DEBUG]: Model already installed for locale: \(localeToUse.identifier)")
        } else {
            print("[Transcriber DEBUG]: Model not installed for locale: \(localeToUse.identifier)")
        }

        // Always ensure locale is allocated after installation/download
        try await reserveLocale(locale: localeToUse)
    }

    func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        
        // Check different locale identifier formats
        let localeId = locale.identifier
        let localeBCP47 = locale.identifier(.bcp47)
        
        // Check with different formatting approaches
        let isSupported = supported.contains { supportedLocale in
            supportedLocale.identifier == localeId ||
            supportedLocale.identifier(.bcp47) == localeBCP47 ||
            supportedLocale.identifier == "en-US" ||
            supportedLocale.identifier(.bcp47) == "en-US"
        }
        
        print(
            "[Transcriber DEBUG]: Supported locales check - locale: \(localeId), bcp47: \(localeBCP47), supported: \(isSupported)"
        )
        print(
            "[Transcriber DEBUG]: All supported locales: \(supported.map { "\($0.identifier) (\($0.identifier(.bcp47)))" })"
        )
        
        // If no locales are supported at all, this indicates a system issue
        if supported.isEmpty {
            print("[Transcriber DEBUG]: WARNING - No supported locales found, this may indicate a system configuration issue")
        }
        
        return isSupported
    }

    func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        let isInstalled = installed.map { $0.identifier(.bcp47) }.contains(
            locale.identifier(.bcp47))
        print(
            "[Transcriber DEBUG]: Installed locales check - locale: \(locale.identifier), installed: \(isInstalled)"
        )
        print(
            "[Transcriber DEBUG]: All installed locales: \(installed.map { $0.identifier(.bcp47) })"
        )
        return isInstalled
    }

    func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        print("[Transcriber DEBUG]: Checking if download is needed...")
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module])
        {
            print("[Transcriber DEBUG]: Download required, starting asset installation...")
            self.downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
            print("[Transcriber DEBUG]: Asset download and installation completed")
        } else {
            print("[Transcriber DEBUG]: No download needed")
        }
    }

    func reserveLocale(locale: Locale) async throws {
        print("[Transcriber DEBUG]: Checking if locale is already allocated: \(locale.identifier)")
        let allocated = await AssetInventory.reservedLocales
        print(
            "[Transcriber DEBUG]: Currently allocated locales: \(allocated.map { $0.identifier })")

        if allocated.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            print("[Transcriber DEBUG]: Locale already allocated: \(locale.identifier)")
            return
        }

        print("[Transcriber DEBUG]: Allocating locale: \(locale.identifier)")
        try await AssetInventory.reserve(locale: locale)
        print("[Transcriber DEBUG]: Locale allocated successfully: \(locale.identifier)")
    }

    func release() async {
        print("[Transcriber DEBUG]: Deallocating locales...")
        let allocated = await AssetInventory.reservedLocales
        print("[Transcriber DEBUG]: Allocated locales: \(allocated.map { $0.identifier })")
        for locale in allocated {
            await AssetInventory.release(reservedLocale: locale)
        }
        print("[Transcriber DEBUG]: Deallocation completed")
    }
}
