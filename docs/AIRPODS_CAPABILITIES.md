# AirPods posture-related capabilities

HeadUp uses only public Apple APIs.

## Available now

### Headphone device motion — macOS 14+

[`CMHeadphoneMotionManager`](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager) delivers [`CMDeviceMotion`](https://developer.apple.com/documentation/coremotion/cmdevicemotion), including:

- Attitude as Euler angles, a quaternion, and a rotation matrix.
- Bias-corrected rotation rate.
- Gravity expressed in the headphone coordinate frame.
- User acceleration separated from gravity.
- Headphone sensor location.

HeadUp currently uses calibrated relative pitch for low-head detection. Quaternion/gravity-based tilt and rotation/acceleration gating are viable future refinements, but require hardware tuning before they should affect reminders.

### Headphone activity — macOS 15+

[`CMHeadphoneActivityManager`](https://developer.apple.com/documentation/coremotion/cmheadphoneactivitymanager) delivers [`CMMotionActivity`](https://developer.apple.com/documentation/coremotion/cmmotionactivity) classifications and confidence. Public classifications relevant on macOS are stationary, walking, running, and unknown. Apple's SDK notes that automotive and cycling are not currently supported for headphone activity.

HeadUp uses walking/running updates to suspend posture reminders while the wearer is moving. macOS 14 continues to use head orientation without activity classification.

## What AirPods cannot determine alone

The public APIs do not directly report:

- Sitting versus standing.
- Spinal curvature, shoulder position, hip position, or whether the back is supported.
- Desk, screen, or keyboard location.
- A medical assessment of posture.

Those require an explicit user mode, another sensor, or optional camera-based body-pose analysis. HeadUp should describe its AirPods-only result as **head posture**, not full-body posture.

## Product roadmap

1. Validate quaternion/gravity tilt against the current relative-pitch result across supported AirPods models.
2. Collect opt-in local diagnostics for rotation and acceleration thresholds without uploading raw motion data.
3. Add manual sitting and standing calibration profiles.
4. Evaluate an optional, clearly permissioned camera mode for shoulder/torso posture.
