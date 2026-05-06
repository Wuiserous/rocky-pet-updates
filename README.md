![Rocky Desktop Pet Banner](rocky-banner.png)
# Rocky Desktop Pet

Rocky is a voice-first desktop pet powered by the Gemini Live API. It lives on your screen as an animated companion, listens through your microphone, speaks back with realtime audio, remembers personal preferences, checks weather and news, sets reminders, sleeps and wakes, dances, and can optionally see your screen when you explicitly ask.

The current main application file is `rocky.py`.

## What Rocky Can Do

- Talk with you in realtime using Gemini Live audio.
- Stay in character as a tiny magical rock golem.
- Show animated states with GIFs: idle, talking, walking, dragging, thinking, happy/dancing, and sleeping.
- Remember personal details such as your name, favorite topics, preferred news topics, work hours, reminder style, favorite jokes, and small notes.
- Greet you based on local time of day.
- Detect approximate location and timezone from the system/network.
- Tell current weather through the free Open-Meteo API.
- Search latest news through Google News RSS without enabling Gemini's session-wide Google Search grounding quota path.
- Set alarms, reminders, timers, and scheduled sleep.
- Wake up for reminders even if Rocky was asleep.
- Walk back to the user's saved sleep position before sleeping.
- Run tiny proactive events while idle, such as hydration nudges, rain/cold/heat comments, morning news prompts, and happy dances.
- Optionally see your screen only when requested, with a visible indicator while active.
- Show a one-time setup GUI for name and Gemini API key.
- Store the Gemini API key encrypted locally with Windows DPAPI.
- Check for updates from a remote version JSON URL.

## Project Structure

Important files:

- `rocky.py`: Main application.
- `rocky.spec`: PyInstaller build specification.
- `icon.ico`: App/tray icon.
- `idle.gif`, `talking_confused.gif`, `walking_right.gif`, `walking_left.gif`, `happy.gif`, `drag_up.gif`, `drag_down.gif`, `sleeping.gif`, `thinking.gif`: Core pet animations.
- `dist/`: PyInstaller output folder, if built.
- `build/`: PyInstaller build cache, if built.
- `Installer/`: Installer-related output.
- `installer_script.iss`: Inno Setup installer script.

State is not saved in the project folder. Runtime state is saved to:

```text
%APPDATA%\rocky_pet_state.json
```

That state file stores reminders, sleep position, user profile memory, and an encrypted API key blob.

## Requirements

Rocky is currently designed for Windows.

Core runtime requirements:

- Python 3.10 or newer recommended.
- Working microphone and speaker output.
- Gemini API key from Google AI Studio.
- Internet connection for Gemini Live, weather, news, location lookup, and update checking.
- PyQt5.
- PyAudio.
- Google Gen AI Python SDK.

Python packages used by the app:

```text
PyQt5
pyaudio
google-genai
```

Depending on your Windows/Python setup, `pyaudio` may require a compatible wheel.

## Setup

Create and activate a virtual environment:

```powershell
cd C:\Users\Aman\PycharmProjects\gemini-ass
python -m venv .venv
.\.venv\Scripts\activate
```

Install dependencies:

```powershell
python -m pip install --upgrade pip
python -m pip install PyQt5 pyaudio google-genai
```

Run Rocky:

```powershell
python rocky.py
```

On first launch, Rocky shows a setup window asking for:

- Your name.
- Gemini API key.

The setup window includes a button that opens:

```text
https://aistudio.google.com/app/api-keys
```

After setup, Rocky saves the API key encrypted with Windows DPAPI. It should not ask again unless the saved state is deleted or the encrypted key can no longer be decrypted by your Windows user account.

You can also provide an API key through an environment variable:

```powershell
$env:GEMINI_API_KEY="your_api_key_here"
python rocky.py
```

or:

```powershell
$env:GOOGLE_API_KEY="your_api_key_here"
python rocky.py
```

Environment variables take priority over the saved encrypted key.

## Basic Usage

Start the app and talk naturally.

Example commands:

```text
Rocky, what time is it?
Rocky, what's the weather?
Rocky, what's the latest AI news?
Set a reminder in 10 minutes to drink water.
Wake me at 7 AM.
Go to sleep.
Wake up.
Dance.
Remember that I like space news.
Remember my work hours are 10 AM to 7 PM.
What's my usual news topic?
See my screen.
Stop seeing my screen.
```

Rocky can also be controlled with the right-click context menu on the pet:

- Sleep / Wake Up
- Dance
- Start Seeing Screen / Stop Seeing Screen
- Quit App

## One-Time Setup and Secure API Key Storage

The setup GUI is implemented by `SetupDialog`.

What it does:

- Asks for your display name.
- Asks for your Gemini API key.
- Opens Google AI Studio API key page from a button.
- Saves your name into the user profile memory.
- Encrypts the API key using Windows DPAPI through `CryptProtectData`.
- Stores the encrypted blob in `%APPDATA%\rocky_pet_state.json`.

The saved key is only decryptable by the same Windows user account on the same Windows installation.

If you want to reset setup, close Rocky and delete:

```text
%APPDATA%\rocky_pet_state.json
```

Next launch will show the setup dialog again.

## Memory System

Rocky maintains a small personal memory in the state file.

Memory categories include:

- `name`
- `favorite_topics`
- `preferred_news_topics`
- `favorite_jokes`
- `work_hours`
- `reminder_style`
- `notes`

The Gemini Live session receives this memory in the system instruction each time it connects. Rocky can also update memory dynamically through the `remember_user_fact` function tool.

Examples:

```text
Remember that my favorite topic is AI.
Remember I like space news.
My work hours are 10 AM to 7 PM.
Keep my reminders short and direct.
My favorite jokes are rock puns.
```

Important behavior:

- Memory updates depend on Gemini choosing to call the memory tool.
- The memory is intentionally small and lightweight.
- List-like memory values are deduplicated and capped so the prompt stays manageable.

## Reminders and Alarms

Rocky can create reminders, alarms, timers, and scheduled sleep through `set_alarm_or_reminder`.

Examples:

```text
Remind me in 20 minutes to check the oven.
Set an alarm for 6:30 AM.
Go to sleep at 11 PM.
```

Reminder behavior:

- Reminders are stored in `%APPDATA%\rocky_pet_state.json`.
- A Qt timer checks due reminders every second.
- If Rocky is asleep when a normal reminder fires, it wakes silently and speaks the reminder first.
- The celebration dance is delayed until after Rocky finishes speaking.
- Scheduled sleep reminders tell Rocky to sleep instead of waking for a normal reminder.

## Sleep Behavior

Rocky saves the last position where the user dragged it. When Rocky is told to sleep, it walks back to that saved sleep position and then switches to the sleeping animation.

Sleep can happen through:

- Voice command: `Go to sleep.`
- Context menu: `Sleep`
- Idle timeout.
- Scheduled sleep reminder.

Wake can happen through:

- Voice command: `Wake up.`
- Left-click while sleeping.
- Context menu: `Wake Up`
- Due normal reminder.

## Weather

Weather uses:

- IP-based approximate location lookup from `ip-api.com`.
- Weather data from Open-Meteo.
- Open-Meteo geocoding when the user asks for weather in a named place.

Examples:

```text
What's the weather?
What's the weather in Delhi?
Will it rain today?
```

While checking weather, Rocky shows:

```text
Checking weather...
```

and uses the `thinking.gif` animation.

## Latest News Search

News search uses Google News RSS through `search_latest_news`.

This was chosen because enabling Gemini's Live-session Google Search tool globally can trigger a separate quota path immediately when the Live session connects. The RSS approach keeps search on demand and avoids destabilizing the audio session.

Examples:

```text
Latest AI news.
What's happening with OpenAI today?
Tell me the latest India tech news.
```

While searching, Rocky shows:

```text
Searching...
```

and uses the `thinking.gif` animation. When results return, the tool response includes compact `voice_summary_material`, and Rocky is instructed to speak it aloud.

Good-news detection can trigger a small dance when result titles/snippets contain positive words like breakthrough, success, milestone, peace, recovery, and similar terms.

## Screen Sharing

Rocky can optionally see your screen when you explicitly ask.

Start commands:

```text
See my screen.
Look at my screen.
Inspect this window.
Read what's on my screen.
Watch my screen for a moment.
```

Stop commands:

```text
Stop seeing my screen.
Stop watching.
Turn off screen sharing.
Hide my screen.
```

You can also start/stop screen sharing from the right-click pet menu.

When screen sharing is active:

- A minimal always-on-top indicator appears: `REC Rocky is seeing your screen`.
- Rocky captures the primary screen once per second.
- Frames are resized to a maximum width of 768 pixels.
- Frames are JPEG-compressed at moderate quality.
- Frames are sent to Gemini Live as `image/jpeg` video blobs.
- Screen sharing stays off unless explicitly started.
- Queued screen frames are cleared when sharing stops.

Privacy notes:

- Rocky does not capture the screen unless screen sharing is active.
- The indicator is meant to make active capture obvious.
- Anything visible on the screen during sharing may be sent to Gemini.
- Say `stop seeing my screen` whenever you want sharing to stop.

## Proactive Mini Events

Rocky has idle-time mini events that make it feel more alive.

Examples:

- Asks if you want your usual news roundup in the morning if preferred news topics are known.
- Makes weather-based comments about rain, cold, or heat.
- Gives hydration nudges.
- Does tiny happy wiggles.
- Suggests winding down at night.
- Celebrates completed reminders with a dance after speaking.

Safety rules:

- Proactive events do not run while Rocky is talking, sleeping, dragging, chasing the cursor, thinking, or already dancing.
- Events are rate-limited so Rocky does not constantly interrupt.

## Animations

Core animation states:

- `IDLE`: `idle.gif`
- `TALKING`: `talking_confused.gif`
- `WALKING_RIGHT`: `walking_right.gif`
- `WALKING_LEFT`: `walking_left.gif`
- `HAPPY`: `happy.gif`
- `DRAG_UP`: `drag_up.gif`
- `DRAG_DOWN`: `drag_down.gif`
- `SLEEP`: `sleeping.gif`
- `THINKING`: `thinking.gif`

The `resource_path()` helper makes these work both in development and in PyInstaller builds.

## Architecture Overview

Rocky combines a Qt GUI thread with a background asyncio Gemini Live loop.

Main pieces:

- `DesktopPet`: Main pet window, animation state, dragging, sleep/wake, reminders, screen capture, proactive events.
- `SpeechBubble`: Floating speech bubble above the pet.
- `ScreenShareIndicator`: Minimal indicator shown while screen sharing is active.
- `SetupDialog`: One-time setup for name and API key.
- `WorkerSignals`: Qt signals used to safely communicate from async/background tasks to the GUI.
- `gemini_loop`: Connect/reconnect loop for Gemini Live.
- `audio_listen_task`: Streams microphone audio to Gemini Live.
- `audio_receive_task`: Receives model audio/transcription/tool calls.
- `audio_play_task`: Plays model audio through PyAudio.
- `text_prompt_task`: Sends queued text prompts into the Live session.
- `screen_share_task`: Streams screen JPEG frames while screen sharing is active.
- `execute_function_call`: Handles Gemini function calls such as weather, news, reminders, memory, sleep/wake/dance, and screen sharing.

Queues:

- `prompt_queue`: GUI/proactive/reminder prompts to Gemini.
- `audio_queue`: Model audio chunks waiting for playback.
- `screen_frame_queue`: Latest screen frames waiting to be sent to Gemini.

## Gemini Live Configuration

Rocky uses:

```python
MODEL_ID = "gemini-3.1-flash-live-preview"
```

Live config includes:

- Audio response modality.
- System instruction with personality, behavior rules, current context, and personal memory.
- Puck voice.
- Output audio transcription.
- Function declarations for tools.

Rocky's tools include:

- `get_current_context`
- `get_weather`
- `search_latest_news`
- `get_personal_memory`
- `remember_user_fact`
- `set_alarm_or_reminder`
- `pet_go_to_sleep`
- `pet_wake_up`
- `pet_dance`
- `start_screen_sharing`
- `stop_screen_sharing`
- `show_thinking_emote`

## Building a Windows EXE

The repository includes `rocky.spec`.

Install PyInstaller:

```powershell
python -m pip install pyinstaller
```

Build:

```powershell
pyinstaller rocky.spec
```

The spec currently includes:

```python
datas=[('*.gif', '.'), ('icon.ico', '.')]
```

This bundles the GIF animations and icon with the app.

The executable output should appear under:

```text
dist\rocky.exe
```

## Installer

The project also includes:

```text
installer_script.iss
```

This appears intended for Inno Setup packaging after PyInstaller builds the executable.

Typical flow:

```text
1. Build with PyInstaller.
2. Confirm dist\rocky.exe runs.
3. Compile installer_script.iss with Inno Setup.
```

## Update Checking

Rocky has an update-check worker that reads:

```text
https://raw.githubusercontent.com/Wuiserous/rocky-pet-updates/refs/heads/main/version.json
```

The local version is:

```python
APP_VERSION = "1.0"
```

If the remote version differs, Rocky can prompt the user to download an update.

## Troubleshooting

### Rocky does not ask for setup again

Delete:

```text
%APPDATA%\rocky_pet_state.json
```

Then restart Rocky.

### Gemini API key problems

Check that the key is valid in Google AI Studio.

You can bypass saved key storage with:

```powershell
$env:GEMINI_API_KEY="your_api_key_here"
python rocky.py
```

### Quota error on connection

If you see quota errors immediately on connection, avoid enabling session-wide Google Search grounding in the Live config. Rocky currently uses Google News RSS for on-demand news to avoid that specific issue.

### Audio stutters or duplicates

The receive loop should only enqueue model audio once from `part.inline_data.data`. Avoid also enqueueing top-level `response.data`, because that can double-play the same audio.

### Reminder wakes but does not speak

The current reminder path wakes silently for reminders and queues the reminder prompt first. Celebration dance happens after talking ends. If it wakes but still does not speak, check terminal logs for Gemini connection errors or quota/network failures.

### Screen sharing starts but Rocky cannot describe the screen

Make sure:

- The indicator says `REC Rocky is seeing your screen`.
- You wait a second or two for frames to reach Gemini.
- You ask a clear screen question after starting sharing.
- The Gemini Live model being used supports image/video input in Live sessions.

### Missing GIF warnings

Make sure all core GIF files are in the same folder as `rocky.py` during development, or bundled through `rocky.spec` for EXE builds.

### PyAudio installation fails

On Windows, install a Python/PyAudio wheel matching your Python version, or use a Python version with available PyAudio wheels.

## Privacy and Security

Rocky handles sensitive data in several places:

- Gemini API key is encrypted locally with Windows DPAPI.
- Personal memory is stored locally in `%APPDATA%\rocky_pet_state.json`.
- Screen frames are sent to Gemini only while screen sharing is active.
- The screen sharing indicator is always shown while capture is active.
- Weather/location uses approximate network/IP location.
- News search requests are sent to Google News RSS.
- Voice audio is streamed to Gemini Live while the app is running and not sleeping.

If you need to fully clear local data, close Rocky and delete:

```text
%APPDATA%\rocky_pet_state.json
```

## Development Notes

This app is intentionally built as one file to preserve the current stable setup. Future refactors should be careful around:

- The audio pipeline.
- Gemini Live receive/tool-response flow.
- Reminder ordering.
- Screen-sharing opt-in behavior.
- State file compatibility.

Recommended future improvements:

- Add a local command router for sleep, wake, dance, reminders, memory, and screen-sharing commands before Gemini interpretation.
- Add a mood engine for sleepy, curious, focused, excited, rainy-day, and lonely states.
- Add a stronger local memory extractor for phrases like `remember that...`.
- Add a settings window for memory, API key reset, voice, screen sharing, proactive behavior, and animation choices.
- Add local fallback reminder sounds/bubbles if Gemini is offline.

