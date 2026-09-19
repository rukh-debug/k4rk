# UI feedback sounds

`click.wav` and `tick.wav` are original, synthesized k4 assets, covered by the
repository license. They are short mono, 48 kHz, 16-bit PCM samples for Qt's
preloaded `SoundEffect` player. No external sound theme is required.

Regenerate them from the repository root with:

```sh
python3 tools/generate_ui_sounds.py
```

Clicks use a soft, damped two-tone pulse. Ticks are shorter and are played at
55% of the configured feedback gain. The service limits ticks to one per 80 ms
and never queues missed interactions.

Verify sample loading, playback, throttling and mute/volume gating with
`nix develop --command python3 tools/test_ui_sounds.py`. The isolated test uses
muted players and fake audio/settings state; it does not change desktop volume.
