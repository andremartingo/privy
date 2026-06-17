import SwiftUI
import FluidAudio

@Observable
class AppSettings {
    var colorScheme: ColorScheme?
    var useSampleAudioForNewMemos: Bool = false
    var modelId: String = TranscriptionOptions.default.modelId
    var languageCode: String = TranscriptionOptions.default.languageCode ?? "en"
    var detectLanguage: Bool = false
    var translateToEnglish: Bool = false
    var initialPrompt: String = ""
    var timestampsEnabled: Bool = true
    var cleanupEnabled: Bool = false
    var skipSilentParts: Bool = false
    var reduceRepetitions: Bool = false
    var strongerRepetitionReduction: Bool = false
    var autoDeleteRecordingsAfterDays: Int = 0
    var wordReplacements: String = ""
    
    // Diarization settings
    var diarizationEnabled: Bool = true
    var clusteringThreshold: Float = 0.7
    var minSegmentDuration: TimeInterval = 0.5
    var maxSpeakers: Int? = nil
    var enableRealTimeProcessing: Bool = false

    init() {
        // Load saved settings
        if let savedScheme = UserDefaults.standard.object(forKey: "colorScheme") as? Int {
            switch savedScheme {
            case 0:
                self.colorScheme = .light
            case 1:
                self.colorScheme = .dark
            default:
                self.colorScheme = nil
            }
        } else {
            self.colorScheme = nil
        }
        
        // Load diarization settings
        loadTranscriptionSettings()
        loadDiarizationSettings()
        useSampleAudioForNewMemos =
            UserDefaults.standard.object(forKey: "useSampleAudioForNewMemos") as? Bool ?? false
    }

    func setColorScheme(_ scheme: ColorScheme?) {
        self.colorScheme = scheme

        // Save to UserDefaults
        if let scheme = scheme {
            UserDefaults.standard.set(scheme == .light ? 0 : 1, forKey: "colorScheme")
        } else {
            UserDefaults.standard.removeObject(forKey: "colorScheme")
        }
    }

    var themeDisplayName: String {
        switch colorScheme {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case nil:
            return "System"
        case .some(_):
            return "System"
        }
    }

    func setUseSampleAudioForNewMemos(_ enabled: Bool) {
        self.useSampleAudioForNewMemos = enabled
        UserDefaults.standard.set(enabled, forKey: "useSampleAudioForNewMemos")
    }

    // MARK: - Transcription Settings

    private func loadTranscriptionSettings() {
        modelId = UserDefaults.standard.string(forKey: "modelId") ?? TranscriptionOptions.default.modelId
        languageCode = UserDefaults.standard.string(forKey: "languageCode")
            ?? TranscriptionOptions.default.languageCode
            ?? "en"
        detectLanguage = UserDefaults.standard.object(forKey: "detectLanguage") as? Bool ?? false
        translateToEnglish = UserDefaults.standard.object(forKey: "translateToEnglish") as? Bool ?? false
        initialPrompt = UserDefaults.standard.string(forKey: "initialPrompt") ?? ""
        timestampsEnabled = UserDefaults.standard.object(forKey: "timestampsEnabled") as? Bool ?? true
        cleanupEnabled = UserDefaults.standard.object(forKey: "cleanupEnabled") as? Bool ?? false
        skipSilentParts = UserDefaults.standard.object(forKey: "skipSilentParts") as? Bool ?? false
        reduceRepetitions = UserDefaults.standard.object(forKey: "reduceRepetitions") as? Bool ?? false
        strongerRepetitionReduction = UserDefaults.standard.object(forKey: "strongerRepetitionReduction") as? Bool ?? false
        autoDeleteRecordingsAfterDays =
            UserDefaults.standard.object(forKey: "autoDeleteRecordingsAfterDays") as? Int ?? 0
        wordReplacements = UserDefaults.standard.string(forKey: "wordReplacements") ?? ""
    }

    func setModelId(_ modelId: String) {
        self.modelId = modelId
        UserDefaults.standard.set(modelId, forKey: "modelId")
    }

    func setLanguageCode(_ languageCode: String) {
        self.languageCode = languageCode
        UserDefaults.standard.set(languageCode, forKey: "languageCode")
    }

    func setDetectLanguage(_ enabled: Bool) {
        detectLanguage = enabled
        UserDefaults.standard.set(enabled, forKey: "detectLanguage")
    }

    func setTranslateToEnglish(_ enabled: Bool) {
        translateToEnglish = enabled
        UserDefaults.standard.set(enabled, forKey: "translateToEnglish")
    }

    func setInitialPrompt(_ prompt: String) {
        initialPrompt = prompt
        UserDefaults.standard.set(prompt, forKey: "initialPrompt")
    }

    func setTimestampsEnabled(_ enabled: Bool) {
        timestampsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "timestampsEnabled")
    }

    func setCleanupEnabled(_ enabled: Bool) {
        cleanupEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "cleanupEnabled")
    }

    func setSkipSilentParts(_ enabled: Bool) {
        skipSilentParts = enabled
        UserDefaults.standard.set(enabled, forKey: "skipSilentParts")
    }

    func setReduceRepetitions(_ enabled: Bool) {
        reduceRepetitions = enabled
        UserDefaults.standard.set(enabled, forKey: "reduceRepetitions")
    }

    func setStrongerRepetitionReduction(_ enabled: Bool) {
        strongerRepetitionReduction = enabled
        UserDefaults.standard.set(enabled, forKey: "strongerRepetitionReduction")
    }

    func setAutoDeleteRecordingsAfterDays(_ days: Int) {
        autoDeleteRecordingsAfterDays = days
        UserDefaults.standard.set(days, forKey: "autoDeleteRecordingsAfterDays")
    }

    func setWordReplacements(_ replacements: String) {
        wordReplacements = replacements
        UserDefaults.standard.set(replacements, forKey: "wordReplacements")
    }

    var transcriptionOptions: TranscriptionOptions {
        TranscriptionOptions(
            modelId: modelId,
            languageCode: languageCode.isEmpty ? nil : languageCode,
            detectLanguage: detectLanguage,
            translateToEnglish: translateToEnglish,
            prompt: initialPrompt,
            timestampsEnabled: timestampsEnabled,
            cleanupEnabled: cleanupEnabled
        )
    }
    
    // MARK: - Diarization Settings
    
    private func loadDiarizationSettings() {
        diarizationEnabled = UserDefaults.standard.object(forKey: "diarizationEnabled") as? Bool ?? true
        clusteringThreshold = UserDefaults.standard.object(forKey: "clusteringThreshold") as? Float ?? 0.7
        minSegmentDuration = UserDefaults.standard.object(forKey: "minSegmentDuration") as? TimeInterval ?? 0.5
        maxSpeakers = UserDefaults.standard.object(forKey: "maxSpeakers") as? Int
        enableRealTimeProcessing = UserDefaults.standard.object(forKey: "enableRealTimeProcessing") as? Bool ?? false
    }
    
    func setDiarizationEnabled(_ enabled: Bool) {
        self.diarizationEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "diarizationEnabled")
    }
    
    func setClusteringThreshold(_ threshold: Float) {
        self.clusteringThreshold = threshold
        UserDefaults.standard.set(threshold, forKey: "clusteringThreshold")
    }
    
    func setMinSegmentDuration(_ duration: TimeInterval) {
        self.minSegmentDuration = duration
        UserDefaults.standard.set(duration, forKey: "minSegmentDuration")
    }
    
    func setMaxSpeakers(_ speakers: Int?) {
        self.maxSpeakers = speakers
        if let speakers = speakers {
            UserDefaults.standard.set(speakers, forKey: "maxSpeakers")
        } else {
            UserDefaults.standard.removeObject(forKey: "maxSpeakers")
        }
    }
    
    func setEnableRealTimeProcessing(_ enabled: Bool) {
        self.enableRealTimeProcessing = enabled
        UserDefaults.standard.set(enabled, forKey: "enableRealTimeProcessing")
    }
    
    /// Returns the current diarization configuration for FluidAudio
    func diarizationConfig() -> DiarizerConfig {
        return DiarizerConfig(
            clusteringThreshold: clusteringThreshold,
            minSpeechDuration: Float(minSegmentDuration),
            minSilenceGap: 0.5, // Default value from FluidAudio
            numClusters: maxSpeakers ?? -1, // -1 for auto-detect
            minActiveFramesCount: 10.0, // Default value from FluidAudio
            debugMode: false
        )
    }
}
