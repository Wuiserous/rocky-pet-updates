# Rocky Desktop Pet

Rocky is a tiny AI-powered desktop pet that lives on your screen.

It can talk with you, remember little things about you, check the weather, search latest news, set reminders, go to sleep, wake up, dance, and even look at your screen when you explicitly ask it to.

Rocky is designed to feel less like a chatbot and more like a small companion sitting on your desktop.

![Rocky Desktop Pet Banner](rocky-banner.png)

## Highlights

- Realtime voice conversations.
- Cute animated desktop pet behavior.
- Personal memory for small preferences.
- Weather, time, and local awareness.
- Latest news search.
- Alarms and reminders.
- Sleep, wake, dance, and idle behavior.
- Optional screen sharing with a visible indicator.
- One-time setup for your name and Gemini API key.
- Local encrypted API-key storage on Windows.
- Update support, so Rocky can get better over time.

## What Rocky Feels Like

Rocky is a small magical rock golem with a loyal, curious personality. It reacts with animations, speaks in short friendly responses, makes little rock-themed jokes, and occasionally gives tiny nudges like hydration reminders or weather comments.

You can drag Rocky around the screen, put it to sleep, wake it up, ask it questions, or let it sit quietly while you work.

## Getting Started

Download and install Rocky from the release/install link.

When Rocky starts for the first time, it will ask for:

- Your name.
- A Gemini API key.

There is a button in the setup window that opens the Gemini API key page directly:

[Create a Gemini API key](https://aistudio.google.com/app/api-keys)

After setup, Rocky remembers this information and should not ask again.

## Example Things To Say

```text
Rocky, what time is it?
Rocky, what's the weather?
What's the latest AI news?
Remind me in 10 minutes to drink water.
Set an alarm for 7 AM.
Remember that I like space news.
What's my usual news topic?
Go to sleep.
Wake up.
Dance.
See my screen.
Stop seeing my screen.
```

## Personal Memory

Rocky can remember small personal details so it feels more familiar over time.

Examples:

```text
Remember that my favorite topic is AI.
Remember I like space news.
My work hours are 10 AM to 7 PM.
Keep my reminders short and direct.
My favorite jokes are rock puns.
```

Rocky may use this memory later for things like:

```text
Want your usual AI news roundup?
```

Memory is meant for small preferences, not sensitive information.

## Reminders And Alarms

Rocky can set reminders, timers, alarms, and scheduled sleep.

Examples:

```text
Remind me in 20 minutes to check the oven.
Set an alarm for 6:30 AM.
Go to sleep at 11 PM.
```

If Rocky is sleeping when a reminder is due, it wakes up and tells you the reminder.

## Weather And News

Rocky can check current weather and forecasts.

Examples:

```text
What's the weather?
Will it rain today?
What's the weather in Delhi?
```

Rocky can also search latest news.

Examples:

```text
Latest AI news.
What's happening in tech today?
Tell me the latest India news.
```

When Rocky is checking weather or searching news, it shows a thinking animation and a small status bubble such as `Searching...` or `Checking weather...`.

## Screen Sharing

Rocky can look at your screen only when you ask.

Start screen sharing:

```text
See my screen.
Look at my screen.
Read what's on my screen.
Inspect this window.
```

Stop screen sharing:

```text
Stop seeing my screen.
Turn off screen sharing.
Stop watching.
```

When screen sharing is active, Rocky shows a small always-on-top indicator:

```text
REC Rocky is seeing your screen
```

If you do not see that indicator, Rocky is not actively seeing your screen.

## Controls

You can interact with Rocky directly:

- Drag Rocky to move it.
- Left-click Rocky while sleeping to wake it.
- Right-click Rocky for quick actions.

Right-click menu actions include:

- Sleep / Wake Up
- Dance
- Start Seeing Screen / Stop Seeing Screen
- Quit App

## Privacy

Rocky is built to make important privacy states visible.

- Rocky asks before setup is completed.
- Your Gemini API key is stored locally in encrypted form on Windows.
- Personal memory is stored locally on your device.
- Screen sharing is off by default.
- A visible indicator appears whenever Rocky is seeing your screen.
- You can stop screen sharing at any time by saying `stop seeing my screen`.
- Voice interaction requires sending audio to Gemini.
- Weather and approximate location features may use network-based location lookup.
- News search uses online news results.

Avoid sharing passwords, private documents, financial information, or other sensitive content while screen sharing is active.

## Resetting Rocky

If you want Rocky to forget setup, memory, reminders, and saved preferences, close Rocky and clear its saved app data.

On Windows, Rocky stores its local state under your AppData folder.

After clearing saved state, Rocky will show the setup screen again on next launch.

## Updates

Rocky supports updates, so improvements can be shipped after release.

Future updates may include:

- Better memory behavior.
- More animations.
- More reliable local commands.
- Better screen understanding.
- Custom personality settings.
- Focus mode and work sessions.
- More pet-like moods and reactions.

## Notes

Rocky is an early personal app and will keep improving. Some behavior may depend on Gemini API availability, internet connection, microphone access, and your current API quota.

If Rocky pauses, reconnects, or behaves strangely, restarting the app usually restores the session.

