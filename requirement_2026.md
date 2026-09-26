# Fan control requirements

**Machine:** Mac mini 2018 (`Macmini8,1`), Intel Core i7-8700B, single fan.

## Goal

Keep the fan quiet at idle and never let it get loud, by replacing Apple's SMC
fan curve with a temperature-driven curve constrained to **0–2500 RPM**, applied
automatically at boot and surviving reboots.

## Requirements

1. **Speed range 0–2500 RPM.** The fan must be able to stop completely when the
   machine is idle, and must never exceed 2500 RPM under normal operation.
2. **Temperature-driven, not pinned.** A fixed speed is not acceptable: pinning
   the fan makes 2500 a floor as well as a ceiling, so the machine is as loud at
   idle as it is under load.
3. **Persist across reboots.** Installed as a LaunchDaemon, applied at startup
   without manual intervention.
4. **Thermal failsafe.** If the CPU reaches a dangerous temperature, hand control
   back to the SMC so the machine can cool itself, then resume the cap once it
   has recovered.
5. **Reversible.** A documented path back to stock SMC fan behaviour.

## Constraints discovered on this machine

- **`F0Mn` is 1700 RPM.** The hardware will not hold a speed between 1 and 1700,
  so the achievable range is `{0} ∪ [1700, 2500]`, not a smooth 0–2500. The fan
  jumps from stopped to 1700 when the curve engages.
- **`TCMX` is not implemented.** The repo's existing `-A` and `--SMC-enhanced`
  modes read CPU temperature from `TCMX`, which this Mac does not expose. Those
  modes would see 0 °C indefinitely and never spin the fan up. `TCXC` is the
  working core-temperature sensor here (41–46 °C idle, 100 °C under load).
- **The machine already saturates below 2500 RPM.** Measured with the fan pinned
  at 2800 RPM, a 25-second all-core load drove `TCXC` to 100 °C — the i7-8700B's
  throttle ceiling. A 2500 RPM cap therefore costs sustained performance, and the
  95 °C failsafe is expected to engage under heavy multi-core work.
- The repo's other auto modes also read battery, palm-rest and Thunderbolt
  sensors that do not exist on a Mac mini; they are MacBook-specific.

## Measured result (2026-09-27, after deployment)

Idle: fan fully stopped (0 RPM), as intended.

Under a 6-core `yes` load, sampled every 5 s:

| Elapsed | Target RPM | Under whose control |
| --- | --- | --- |
| 5 s | 0 | capped-auto (still below 50 °C) |
| 10 s | 1971 | capped-auto |
| 15 s | 2305 | capped-auto |
| 20 s | 2604 | **SMC** — failsafe had fired |
| 60 s+ | 4400 | SMC (hardware maximum) |

**The 2500 RPM cap holds for roughly 15 seconds of all-core load before the
95 °C failsafe releases the fan to the SMC.** Recovery works: about a minute
after the load stopped, control returned to capped-auto at 1977 RPM.

This is the failsafe behaving as designed, but it means requirement 1's ceiling
is effectively an *idle and light-load* ceiling on this machine, not an absolute
one. Deciding between a quiet machine and a hard cap is a tradeoff that cannot
be avoided on this hardware — the i7-8700B simply produces more heat than
2500 RPM can remove.

## Chosen behaviour

| Condition (avg `TCXC`, 10 s window) | Fan |
| --- | --- |
| below 50 °C | stopped (0 RPM) |
| 50–55 °C | holds its previous state (hysteresis band) |
| 55 °C (rising) | starts at 1700 RPM |
| 55 → 85 °C | linear ramp 1700 → 2500 RPM |
| 85 °C and above | 2500 RPM |
| 95 °C instantaneous | released to SMC auto (up to 4400 RPM) |
| recovered below 80 °C avg | 2500 RPM cap reapplied |

Hysteresis between 50 °C and 55 °C prevents the fan oscillating on and off:
once running it does not stop until the average falls below 50 °C, and once
stopped it does not start until 55 °C.

Because the curve reads a 10-second average, brief spikes do not start the fan —
a one-second jump to 70 °C moves the average by only about 2 °C, so short
compile bursts stay silent. The cost is that the fan reacts roughly 10 seconds
behind a genuinely sustained load. Only the 95 °C failsafe reads the
instantaneous temperature, so it is not subject to that lag.

There is no gentle spin-up: `F0Mn` is 1700, so crossing 55 °C is an audible jump
from silent to 1700 RPM.

All five thresholds are `const double`s at the top of `runCappedAuto()` in
`smc_fan_util.c` if they need retuning.

## Status bar (added after the initial requirement)

The fan speed, CPU temperature and available memory are shown in the tmux status
bar as `Fan 0 CPU 52°C Ram 55GB`, refreshed every 10 seconds.

- `fan_status.sh` gathers all three in one pass and caches the result for 10 s.
  The cache is necessary because `status-interval` is 1 — the seconds in the
  clock depend on it — so the status bar redraws far more often than the SMC
  should be polled.
- `smc_fan_util -t` was added to print the CPU temperature, so the status bar
  reads the same `TCXC` sensor the fan curve does. A generic SMC reader
  hardcoded to `TCMX` would print nothing on this machine.
- Memory is reported as *available* (free + inactive + speculative + purgeable),
  not raw `Pages free`, which understates usable memory once the file cache has
  warmed: 49 GB raw versus 55 GB available on this 64 GB machine.

## Out of scope

- Other Mac models. This targets `Macmini8,1` only.
- GUI or menu-bar integration.
