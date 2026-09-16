# HeadUp 更新日志 / Changelog

## HeadUp 0.3.3 [2026-09-16]

### 中文

#### 修复与可靠性

- 修复 AirPods 短暂断开并重连后，屏幕保护错误要求重新录入中心、左、右、上、下五个点的问题。系统的“显示器参数变化”通知有时会随音频设备重连发出；现在会核对显示器 ID 和实际位置/尺寸，只有显示器确实新增、移除或改变布局时才作废已保存的五点校准。普通耳机重连后只需重新对准中心。

#### 验证

- 新增回归测试，覆盖无实际显示器布局变化的通知不会作废校准，以及真实新增显示器仍会要求重新校准。

### English

#### Fixes and reliability

- Fixed screen protection incorrectly asking to re-enter the center, left, right, upper, and lower calibration points after a brief AirPods disconnect and reconnect. macOS can post a display-parameter notification during an audio-device reconnect; HeadUp now compares display IDs and actual positions/sizes, invalidating saved five-point calibration only when a display is added, removed, or its layout changes. A normal reconnection only needs a recenter.

#### Verification

- Added a regression test proving that a notification without a real display-layout change preserves calibration, while adding a display still requires recalibration.

## HeadUp 0.3.2 [2026-09-15]

### 中文

#### 新功能

- 多显示器下摘戴耳机后，不再需要重新校准全部屏幕。AirPods 的水平角零点每次连接都是任意的，但各屏之间的相对角度不变，所以只需一次对准就能恢复：遮挡界面正中会出现"对准这里"按钮，正视它并点按即可立即恢复保护，已保存的逐屏校准原样复用。菜单栏面板也提供"对准中心"（3 秒倒计时后自动采样）。
- 遮挡时随时可以手动对准：如果觉得边界偏了，不必重新校准，正视屏幕中心点一下按钮即可重新对齐。

#### 修复与可靠性

- 修复摘下再戴上耳机后"设置像是丢了"的问题。此前多显示器配置在每次追踪中断（以及每次启动）都会被标记为需要重新校准，逐屏配置虽然一直保存在本地却不被使用，重新校准又会用新采集值覆盖旧值。现在改为只需一次轻量对准。
- 修复长时间佩戴后漂移修正会彻底失效的问题：此前学习只在“未遮挡”状态进行，而样本又只在工作区内部采集，一旦漂移把头部推到边界之外就会互锁——修正被永久冻结，只能重新校准。现在遮挡期间会单独收集静止姿态，若工作区连续 3 分钟无法回到、且头部一直稳定停在边界外不远处，会自动重新对准并恢复显示。
- 修复 AirPods 短暂断流后工作区突然跑偏的问题：传感器时间跳变只清空采样缓冲，不再丢弃已学到的修正量。物理漂移不会因为断流而归零，此前一并清零会让工作区瞬间跳回原始校准中心，偏移量正好等于已累积的漂移，往往直接触发上面的互锁。
- 取消修正量的固定上限（原为 `min(15°, 最小边界角 × 0.5)`）。漂移随时间无界增长，任何固定上限最终都会被突破并让工作区永久偏置；窄工作区尤其受限。现在改为依靠单次步长限制、对称采样窗口和分布宽度门控来约束错误修正，仅保留 90° 的兜底上限。
- 加入漂移速率前馈：纯比例控制对匀速漂移存在固定稳态滞后，此前边界余量会被这部分滞后长期占用。
- 修正采样的删失偏差：此前样本在工作区边界处被裁剪，中位数被系统性拉回中心，导致漂移被低估、且漂移越大低估越重。现在改为在当前中心周围的对称窗口内采样。
- 单显示器配置现在也享受漂移修正。此前只有逐屏校准走漂移估计，单一配置仅依赖追踪中断后的重新对中，与 README 中“逐屏学习并抵消漂移”的说明不一致。
- 稳态单次步长收紧到 0.5°（校准后前 90 秒仍为 1°，用于快速消除已存在的偏移），使其接近真实漂移速率，降低“长时间偏坐”被当成漂移的程度。
- 采样节流改为逐屏独立，此前为全局共享。

#### 验证

- 新增 11 项测试：越界后自动恢复、大角度转头不触发恢复、短时遮挡不触发、姿态不稳不触发、多屏归属歧义不触发、断流保留修正量、窄工作区可跟踪大漂移、匀速漂移残差、跨屏交界采样节流、单显示器路径漂移修正。

### English

#### Features

- Refitting an earbud on a multi-display setup no longer requires recalibrating every screen. The AirPods yaw datum is arbitrary per connection, but the angles between displays are not, so one aim restores the whole layout: an "Aim here" target appears at the center of the covered screen, and facing it and tapping resumes protection immediately, reusing the saved per-display calibration. The menu bar panel offers "Recenter" as well, with a 3-second countdown.
- Recentering is available by hand whenever a screen is covered, so boundaries that feel off can be re-aimed without a full recalibration.

#### Fixes and reliability

- Fixed saved settings appearing to vanish after removing and refitting an earbud. A multi-display setup was marked as needing recalibration on every tracking loss (and every launch); the per-display profiles stayed on disk but went unused, and recalibrating then overwrote them. A one-tap recenter now covers this.
- Fixed drift correction becoming permanently unusable in a long session. Learning ran only while uncovered, and samples were only collected inside the work area, so once drift pushed the head past a boundary the two conditions deadlocked and the correction froze until a recalibration. Stationary poses are now collected while covered, and if the work area stays unreachable for 3 minutes while the head is parked steadily just outside it, the work area re-aligns and the screen is revealed.
- Fixed the work area jumping off-target after a brief AirPods dropout. A sensor time gap now clears only the sample buffer and keeps the learned correction. Physical drift does not reset because the stream broke, so discarding the correction snapped the work area back by exactly the drift it had removed — usually straight into the deadlock above.
- Removed the fixed ceiling on accumulated correction (previously `min(15°, smallest boundary × 0.5)`). Drift grows without bound, so any fixed ceiling is eventually exceeded and leaves the work area permanently offset; narrow work areas were capped hardest. A wrong correction is now contained by the per-check slew limit, a symmetric acceptance window, and the spread gate, with a 90° runaway guard.
- Added drift-rate feed-forward. A pure proportional controller trails steady drift by a fixed residual, which was consuming boundary margin for the whole session.
- Fixed censoring bias in sampling. Samples were clipped at the work-area boundary, which pulled the median back toward the center and under-estimated the drift — worsening as the drift grew. Samples now come from a symmetric window around the current center.
- Single-display setups now get drift correction too. Only per-display calibration ran through the estimator; the single-profile path relied on recentering after a dropout, which did not match the README.
- Tightened the steady-state step to 0.5° (the first 90 s after calibration still uses 1° to clear a pre-existing offset), keeping it near the real drift rate so sitting off-center is less able to drag the work area.
- Sample throttling is now per display instead of shared.

#### Verification

- 11 new tests: recovery past a boundary, no recovery on a deliberate large turn, no recovery on a short stall, no recovery on an unsteady pose, no recovery when the display is ambiguous, corrections kept across a stream gap, large drift tracked in a narrow work area, steady-drift residual, seam-crossing sample throttling, and single-display drift correction.

## HeadUp 0.3.1 [2026-09-14]

### 中文

#### 新功能

- 每块已校准屏幕的左、右、上、下四个角度现在可以在“已校准屏幕”中直接展开调整，拖动后立即生效并保存，无需重新校准。

#### 修复与可靠性

- 改进漂移修正：不再把第一段采样锁定为零偏基线，校准时已经存在的传感器偏移也会被逐步修正。
- 单次微调上限由 0.5° 提升到 1°（最快每分钟约 6°），并同时修正水平（偏航）与垂直（俯仰）两个方向的漂移。
- 新增漂移诊断：设置中逐屏显示累计修正量、有效样本数和当前状态，包括样本不足、采样时长不足、分布过宽、暂停学习等跳过原因；每次微调与重置都会写入 Privacy 日志类别，可在“控制台”App 中核查。
- 新增 preview 构建开关：`HEADUP_PREVIEW=1 ./script/build_and_run.sh build`（调试包）或 `HEADUP_PREVIEW=1 HEADUP_SIGNING_IDENTITY=- ./script/package_release.sh`（release 包）会以 `-DHEADUP_DEBUG` 编译，记录样本归属、速度门控、每屏修正后中心与偏移等逐秒调试日志（正式构建中这些高频日志会被编译移除）。
- 去掉设置中所有滑块轨道下方的刻度点，改为连续轨道并按原步长吸附，界面更简洁。

#### 验证

- 新增既有偏移消除、垂直方向漂移、暂停学习诊断、样本不足诊断、逐屏角度调整持久化、调试日志开关，以及源码本地化调用点与文案表一致性扫描测试；普通与 preview 两种构建均编译验证通过。

### English

#### Features

- Each calibrated screen now exposes editable left, right, upper, and lower angles under “Calibrated Screens”; changes apply and persist immediately without recalibration.

#### Fixes and reliability

- Improved drift correction: the first samples are no longer locked as the zero baseline, so sensor offset already present at calibration time is removed gradually.
- Raised the per-step correction cap from 0.5° to 1° (up to about 6° per minute) and now corrects pitch drift alongside yaw drift.
- Added drift diagnostics: per-screen correction totals, valid-sample counts, and the current status (including skip reasons such as insufficient samples, short windows, wide spread, and suspended learning). Every correction and reset is written to the Privacy log category for inspection in Console.app.
- Added a preview build switch: `HEADUP_PREVIEW=1 ./script/build_and_run.sh build` (debug) or `HEADUP_PREVIEW=1 HEADUP_SIGNING_IDENTITY=- ./script/package_release.sh` (release) compiles with `-DHEADUP_DEBUG` and records per-second debug traces (sample attribution, speed gating, corrected centers and offsets per screen); these hot-path traces are compiled out of release builds.
- Removed the tick marks under every settings slider in favor of continuous tracks that still snap to the previous increments.

#### Verification

- Added tests for pre-existing offset removal, pitch drift, suspended-learning diagnostics, insufficient-sample diagnostics, per-screen angle persistence, the debug-trace switch, and source-to-table localization coverage; both normal and preview builds compile cleanly.

## HeadUp 0.3.0 [2026-09-14]

### 中文

#### 新功能

- 新增可选的 AirPods 屏幕保护功能：当佩戴者的头部转出已校准的工作区时，自动遮挡所有已连接的显示器。
- 新增五步工作区校准，依次设置中心、最左、最右、最高和最低边界，并可分别调整四个方向的角度与响应延迟。
- 新增模糊压暗和纯色两种遮挡样式，可显示系统日期与时间、可选的 Open-Meteo 天气和自定义文字。
- 将设置页重新整理为“通用”“低头提醒”“屏幕保护”和“遮挡内容”，并在菜单栏面板中加入屏幕保护状态与快捷控制。

#### 可靠性与隐私

- 加入迟滞区间，并分别设置遮挡和恢复延迟，减少头部靠近边界时的画面闪烁。
- AirPods 头部追踪中断时默认保持屏幕保护，同时提供 `Esc` 紧急退出方式，并过滤存活检测中的重复 Core Motion 数据帧。
- 将四向校准结果保存在本机；摘下一只 AirPod 或追踪短暂重连时不会丢失设置，新姿态数据恢复后会自动重新对中。
- 头部方向数据只在本机处理；可选天气功能仅会将用户设置的城市发送给 Open-Meteo。

#### 验证

- 新增四向边界判断、跨越正负 180 度的偏航角校准、设置持久化、天气代码映射和重复姿态数据过滤测试。
- 已验证设置页签、全屏模糊预览、`Esc` 恢复、应用构建和启动流程。

### English

#### Features

- Added optional AirPods-based screen protection that covers every connected display when the wearer turns outside a calibrated work area.
- Added five-step calibration for the center, left, right, upper, and lower work-area boundaries, with independent angle and response-delay controls.
- Added blur-and-dim and solid-color overlays with system date and time, optional Open-Meteo weather, and custom text.
- Reorganized settings into General, Posture Reminder, Screen Protection, and Overlay Content tabs, with quick protection status and controls in the menu bar dashboard.

#### Reliability and privacy

- Added hysteresis and separate cover/reveal delays to avoid flickering near a boundary.
- Kept protection active when AirPods tracking is lost, with an `Esc` escape path, and filtered duplicate Core Motion frames from liveness checks.
- Saved the four-direction calibration locally, kept it when one AirPod is removed or tracking briefly reconnects, and automatically recentered protection when fresh motion data resumed.
- Kept head-orientation processing local; optional weather requests send only the configured city to Open-Meteo.

#### Verification

- Added tests for four-direction boundary detection, wrapped yaw calibration, persistence, weather-code mapping, and duplicate motion samples.
- Verified the settings tabs, full-screen blur preview, `Esc` recovery, application build, and launch flow.

## HeadUp 0.2.6 [2026-07-08]

### 中文

#### 修复

- 修复暂停后恢复监测的问题：HeadUp 现在会重新启动 AirPods 头部姿态采样，不再停留在“等待头部追踪”状态。

### English

#### Fixes

- Fixed monitoring resume after pause so HeadUp restarts AirPods head-motion sampling instead of staying stuck in the waiting-for-head-tracking state.

## HeadUp 0.2.5 [2026-06-29]

### 中文

#### 修复

- 新增独立的本地提示音开关；即使系统通知音被静音或关闭，低头提醒仍可播放声音。

### English

#### Fixes

- Added an independent local sound reminder toggle so posture reminders are audible even when system notification sounds are muted or disabled.

## HeadUp 0.2.4 [2026-06-29]

### 中文

#### 修复

- 新增 CoreAudio AirPods 连接检测，在 Core Motion 未报告初始耳机连接时作为备用判断。
- AirPods 摘下并重新戴上后，重连轮询不再受菜单运行循环模式影响。
- 已连接但仍在等待头部追踪时，不再显示代表断开连接的状态图标。
- 修复姿态会话恢复问题：音频连接轮询不再反复重置存活检测计时器，避免 HeadUp 在重启或重连后一直等待头部姿态数据。
- 防止重复启动耳机姿态监测；多次存活检测超时后会重建 Core Motion 管理器。
- 启动姿态更新后改为轮询 `deviceMotion`，兼容回调处理器没有收到数据的情况。

### English

#### Fixes

- Added CoreAudio AirPods connection detection as a fallback when Core Motion does not report the initial headphone connection.
- Made AirPods reconnection polling independent of menu run loop mode after taking headphones off and putting them back on.
- Changed the connected-but-waiting-for-head-tracking state so it no longer uses the disconnected status icon.
- Fixed a motion-session recovery bug where audio connection polling could keep resetting the liveness watchdog, leaving HeadUp stuck waiting for head-tracking samples after restart or reconnect.
- Prevented duplicate headphone motion start attempts and rebuilt the Core Motion manager after repeated liveness timeouts.
- Switched headphone motion reads to polling `deviceMotion` after starting updates, covering cases where the handler never delivers samples.

## HeadUp 0.2.3 [2026-06-29]

### 中文

#### 修复

- 修复启动连接检测：如果兼容的 AirPods 在 HeadUp 启动前已经连接，现在也能正确识别。

### English

#### Fixes

- Fixed startup connection detection when compatible AirPods are already connected before HeadUp starts.

## HeadUp 0.2.2 [2026-06-27]

### 中文

此版本修复了将打包后的应用移动到另一台 Mac 时无法启动的问题。

#### 修复

- 修复发布打包时没有将 Swift Package Manager 资源包复制到 `HeadUp.app` 的问题。
- 打包后的应用现在会在 `Contents/Resources` 中包含 `HeadUp_HeadUp.bundle`，让 `Bundle.module` 能在运行时正确加载资源。
- 修复从 Finder 启动时看似没有反应的问题；原因为应用提前崩溃并提示 `Fatal error: unable to find bundle named HeadUp_HeadUp`。

#### 打包

- 更新 `script/package_release.sh`，将 SwiftPM 生成的资源包复制到发布版应用中。
- 更新 `script/build_and_run.sh`，让本地构建使用与发布版相同的资源包布局。
- 改进缺少 Xcode 构建工具时的发布构建预检提示。

#### 验证

- `bash -n script/package_release.sh`
- `bash -n script/build_and_run.sh`
- 已确认生成的发布资源包位于 `.build/apple/Products/Release/HeadUp_HeadUp.bundle`。

### English

This release fixes the packaged app startup failure seen when moving the app to another Mac.

#### Fixes

- Fixed a release packaging issue where the Swift Package Manager resource bundle was not copied into `HeadUp.app`.
- The packaged app now includes `HeadUp_HeadUp.bundle` under `Contents/Resources`, allowing `Bundle.module` resources to load correctly at runtime.
- Fixed the symptom where Finder launch appeared to do nothing because the app crashed early with `Fatal error: unable to find bundle named HeadUp_HeadUp`.

#### Packaging

- Updated `script/package_release.sh` to copy the generated SwiftPM resource bundle into the release app bundle.
- Updated `script/build_and_run.sh` to use the same resource bundle layout as release builds.
- Improved release build preflight messaging for missing Xcode build tools.

#### Verification

- `bash -n script/package_release.sh`
- `bash -n script/build_and_run.sh`
- Confirmed the generated release resource bundle exists at `.build/apple/Products/Release/HeadUp_HeadUp.bundle`.

## HeadUp 0.1.0

### 中文

- 使用 AirPods 头部姿态数据进行坐姿监测，并提供两步校准。
- 持续低头时发送本地通知；通知不可用时使用屏幕提示作为备用方式。
- 显示最近 60 分钟的姿态时间线，并按天保存统计摘要。
- 在 macOS 15 及以上版本中，根据耳机活动数据在走路或跑步时暂停提醒。
- 提供菜单栏面板、设置窗口、开机启动选项，并将数据保存在本机。
- 提供首次启动指南、权限重试、版本信息、更新入口和支持入口。
- 提供“应用程序”文件夹安装引导、保护隐私的诊断信息复制和用于发布支持的 dSYM 归档。
- 修复 Core Motion 仅处于监听状态时错误显示耳机已连接的问题，并在耳机断开时立即取消校准。

### English

- AirPods head-motion posture monitoring and two-stage calibration.
- Sustained low-head reminders with local notification and HUD fallback.
- Recent 60-minute posture timeline and persistent daily summaries.
- Walking/running suppression using headphone activity data on macOS 15+.
- Menu bar dashboard, settings window, launch-at-login option, and local-only storage.
- First-launch guide, permission retry, version information, update link, and support entry points.
- Applications-folder guidance, privacy-safe diagnostic copy, and archived dSYM symbols for release support.
- Fixed a false connected state when Core Motion was listening without an AirPods connection, and canceled calibration immediately on disconnect.
