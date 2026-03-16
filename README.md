# Aagedal Audio Synopsis

An open-source, privacy-focused macOS app for audio transcription and summarization — powered by Whisper.cpp and MLX. All processing happens on-device.

## Features

### Recording
- Live microphone and optional system audio capture
- Pause and resume recording
- Real-time audio frequency visualizer (9-band)
- Silence-based segmentation for fast live transcription feedback

### Transcription
- On-device speech-to-text via Whisper.cpp
- Multiple model sizes from Tiny (78 MB) to Large v3 (3.1 GB)
- Language-specific models: English, Norwegian (NbAiLab), and Swedish (KBLab)
- Auto-language detection
- Timestamped transcript segments with clickable timecodes
- Live transcription during recording
- Retranscribe with updated settings at any time

### Summarization
- **MLX models** (fully local, no internet required): Qwen 3.5, Gemma 3, GPT-OSS — ranging from ~3 GB to ~12 GB memory
- **Apple Intelligence** fallback (macOS 15.1+)
- Summarization modes: General, Meeting (decisions & action items), Lecture (structured themes)
- Custom system prompts and output language override
- Automatic chunked summarization for long transcripts

### Notes
- Side panel with live Markdown rendering (headings, bold, italic, checklists, code, etc.)
- Auto-insert recording timecodes on Enter
- Debounced auto-save

### Playback
- High-quality audio playback with interactive timeline
- Variable speed (0.5×–2.0×)
- Click transcript timecodes to seek

### Search
- Filter recordings by title, transcript, or notes
- Full-text search within transcripts and summaries with match highlighting and navigation

### Export
- Transcription: plain text (.txt) or SRT subtitles (.srt)
- Summary: plain text (.txt) or Markdown (.md)
- Combined transcript + summary Markdown export
- Copy to clipboard

### Settings
- Whisper and MLX model download manager with progress display
- Import custom Whisper models (files) and MLX models (folders)
- Configurable max output tokens, language, summarization mode, and system prompt

## Tech Stack
- SwiftUI for the native macOS interface
- Whisper.cpp for speech-to-text transcription
- MLX / MLXLLM for on-device summarization
- AVFoundation for audio recording and playback

## Requirements
- macOS 15+ on Apple Silicon

## License
GPL 3
