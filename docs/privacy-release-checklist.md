# Privacy And Release Checklist

Date: 2026-06-17

Privy's product claim is local-first transcription. Before release, verify these
items against the actual shipped build.

## Default Data Flow

- Audio recording writes to the app container.
- Imported media is copied into the app container before transcription.
- Transcription runs locally by default.
- Summaries and cleanup run locally when Foundation Models are available.
- Exports and shares are user initiated.

## Network Audit

- Run transcription with networking disabled.
- Confirm no audio, transcript text, summaries, speaker labels, or export files
  leave the device during default recording, import, transcription, cleanup, or
  summary flows.
- Inspect Swift package dependencies for network behavior.
- Verify crash logs and diagnostics do not include audio or transcript content.
- Re-run the audit after adding model downloads, analytics, crash reporting,
  sync, purchases, or support upload flows.

## App Store Privacy

- Add a privacy policy that matches the shipped behavior.
- Set the App Store privacy nutrition label to no data collection only if the
  network audit confirms it.
- Document any optional feature that can send user content outside the device.

## Hardware And Model Compatibility

- Test the default Parakeet model on the minimum supported iPhone and Mac.
- Add runtime warnings before enabling models that exceed available memory,
  storage, Neural Engine/GPU capability, or OS support.
- Keep downloaded-model state separate from general settings before adding
  multiple large models.

## Platform Work Still Requiring Separate Targets Or Entitlements

- Lock Screen widgets require a widget extension.
- Live Activities and Dynamic Island require ActivityKit integration.
- Control Center controls require a Control Widget target on supported OSes.
- Mac global hotkey dictation requires hotkey handling and Accessibility
  permission onboarding.
- Mac meeting recording requires a capture strategy, permission UX, and consent
  language before implementation.
