# Privacy

HeadUp is designed to process posture information on the Mac where it runs.

## Data HeadUp uses

- Head orientation, rotation, acceleration, and motion-activity classifications supplied by Apple's Core Motion framework for compatible AirPods.
- Calibration settings, reminder preferences, daily summary counters, and up to 60 minutes of downsampled posture history.

## Storage and transmission

- Posture processing happens locally on the Mac.
- HeadUp does not contain analytics, advertising, accounts, network clients, or cloud synchronization.
- Settings and posture summaries are stored in the app's local `UserDefaults` container.
- System notifications are scheduled through Apple's local User Notifications framework.

## Deleting data

Use **Settings → Data → Clear posture history** to remove daily counters and recent posture history. Removing the app and its preferences also removes the remaining local settings.

## Scope

HeadUp is a wellness utility, not a medical device. AirPods provide head-motion information; they do not directly measure spinal, shoulder, sitting, or standing posture.
