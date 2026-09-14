# Privacy

HeadUp is designed to process posture information on the Mac where it runs.

## Data HeadUp uses

- Head orientation and, on macOS 15 or later, motion-activity classifications supplied by Apple's Core Motion framework for compatible AirPods.
- Calibration settings, screen-protection preferences, reminder preferences, daily summary counters, and up to 60 minutes of downsampled posture history.

## Storage and transmission

- Head-orientation processing and screen protection happen locally on the Mac.
- HeadUp does not contain analytics, advertising, accounts, or cloud synchronization.
- Weather is optional. When enabled, the city entered by the user is sent to Open-Meteo to resolve the location and retrieve current conditions. Head orientation, screen contents, and custom overlay text are never included in weather requests.
- HeadUp does not record, upload, or save images of the protected screens. The blur is rendered locally from the content behind each overlay window.
- Settings and posture summaries are stored in the app's local `UserDefaults` container.
- System notifications are scheduled through Apple's local User Notifications framework.

## Deleting data

Use **Settings → Data → Clear posture history** to remove daily counters and recent posture history. Removing the app and its preferences also removes the remaining local settings.

## Scope

HeadUp is a wellness utility, not a medical device. AirPods provide head-motion information; they do not directly measure spinal, shoulder, sitting, or standing posture.
