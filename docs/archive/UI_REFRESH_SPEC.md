# SpokenLog UI Refresh Specification

Historical design notes, retained for reference. These describe an earlier layout, not the current demo. See [current features](../features.md) and [known issues](../installation.md#known-issues).

## Goals
- Keep the app visually clean and professional: white/light-gray surfaces with orange used only for primary actions and selection.
- Make app language, transcription language, quick engine switching, and advanced transcription settings clearly separate.
- Add a real calendar-based recording browser.
- Keep desktop and mobile behavior consistent while preserving existing recording/transcription features.

## Information architecture
### Desktop
1. Left navigation
   - New recording
   - Import file
   - All recordings
   - Calendar
   - App settings
   - Advanced transcription settings
   - Current engine status/switcher
2. Middle column
   - Recording search and list
3. Right workspace
   - Recording metadata
   - Playback/waveform
   - Transcription actions
   - Transcript

### Mobile / narrow layouts
- Brand + App Settings at the top.
- Quick transcription engine/language panel below the header.
- Record/import actions remain thumb-friendly.
- Records / Calendar segmented navigation.

## Settings behavior
### App Settings
- Program language: System default / Korean / English.
- Program language is explicitly separate from spoken/transcription language.

### Quick Transcription
- Engine
- Spoken language
- Groq model when applicable
- Link to advanced settings

### Engine Switcher
- Current engine status.
- Ready engines switch immediately.
- Engines requiring a model/API setup open advanced settings.

### Advanced Transcription
- API credentials
- Local model downloads
- Speaker diarization
- Usage/quota information
- Detailed engine configuration

## Calendar
- Month navigation.
- Recording count badge per date.
- Today shortcut.
- Selecting a date shows recordings from that date.
- Selecting a recording returns to the normal recording workspace with that recording selected.

## Visual system
- Primary accent: muted orange.
- Surfaces: white / neutral light gray.
- No decorative gradients in the main workspace.
- Fox mascot appears only as the application/brand icon, not as workspace decoration.
- Rounded corners remain restrained and consistent.
