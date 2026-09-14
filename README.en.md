# HeadUp

[简体中文](README.md) · [English](README.en.md)

While you work with AirPods, HeadUp helps you look after your neck and protects what is on your screens when you turn away.

It lives in the Mac menu bar and does not use a camera. When you face your screens again, the cover disappears automatically so you can get straight back to work.

## Two practical ways HeadUp helps

### Protect your screens when you turn away

In an office or shared workspace, you may turn to speak with a coworker, look down for something, or leave your desk. When your head moves outside your normal work area, HeadUp can automatically blur and dim every display, reducing the chance that someone nearby sees private chats, customer information, or internal documents.

- Detects turns to the left and right as well as looking up and down
- Protects every connected display at the same time
- Restores your screens automatically when you face your work area again
- Keeps your setup when you temporarily remove one AirPod; protection continues when the remaining earbud still provides head tracking
- Recovers automatically after a brief AirPods reconnection without asking you to set the four boundaries again
- Lets you press `Esc` to reveal your screens immediately and pause protection

The screen cover can also become a calm information page. You can choose to show:

- The system date and time
- Current weather
- Your own message, such as “Back soon” or a note for office visitors
- A blurred and dimmed desktop or a solid-color background

### Remind you when your head stays lowered

HeadUp learns the difference between your upright position and the way you naturally look down. If your head stays lowered for longer than the time you choose, it can remind you with a notification, sound, or on-screen prompt.

The menu bar panel also shows your current downward angle, reminder countdown, posture changes over the last hour, and today's good-posture percentage.

## Get started in three minutes

1. Connect head-tracking AirPods to your Mac and open HeadUp.
2. Allow Motion & Fitness access when prompted.
3. Complete the two-step posture setup: look straight at your screen, then lower your head naturally.
4. To use screen protection, open **Settings → Screen Protection**, turn it on, and look at the center, far-left, far-right, highest, and lowest points of your work area when prompted.
5. Open **Settings → Overlay Content** to choose the cover style and whether to show the time, weather, or a custom message.

The four-direction setup adapts HeadUp to your desk. A single display, side-by-side displays, and vertically arranged displays can all have different work areas. Once setup is complete, normal earbud changes and brief disconnections will not make you repeat it.

HeadUp shows a short guide on first launch. You can open it again from the menu in the top-right corner of the menu bar panel.

## Privacy

HeadUp uses head-direction data from your AirPods. It does not use a camera and cannot tell which item on your screen you are looking at. Head-angle data and posture history stay on your Mac.

Weather is off by default. When enabled, HeadUp sends only the city you entered to Open-Meteo. See [PRIVACY.md](PRIVACY.md) for more details.

## Requirements

- macOS 14 or later
- AirPods or Beats that support head tracking and are connected to your Mac
- Motion & Fitness permission; notification permission is optional

## Download and install

The project does not yet provide a publicly distributed build notarized by Apple. Official builds will be published on [GitHub Releases](https://github.com/breezedeus/head-up/releases). For now, you can build it from source:

```bash
./script/build_and_run.sh
```

The app is created at `dist/HeadUp.app`. If you have trouble with the connection, permissions, or reminders, see [SUPPORT.md](SUPPORT.md).

## Developer information

Run tests and build verification with:

```bash
swift test
./script/build_and_run.sh --verify
```

See [RELEASING.md](RELEASING.md) for signing and release steps. HeadUp can identify head direction from AirPods motion data, but it cannot measure slouching, bending at the waist, shoulder position, or whether you are sitting or standing. It is not a medical device.
