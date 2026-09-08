# Gunplay and character performance

The AR remains semi-automatic: one press fires one round. Its cadence cap is now
600 RPM (100 ms between shots), up from 400 RPM. One click arriving within the
last 80 ms of the cooldown is retained until the next legal shot. Reloading,
switching weapons, death and stun discard pending input.

AR camera kick is reduced from 1.4 to 0.55 vertical degrees and from 0.4 to 0.18
horizontal degrees before the existing 0.6 camera multiplier. Recoil now returns
95% over the weapon's recovery time (AR: 0.14 seconds), independently of frame
rate. Mouse aim is stored separately, so firing no longer permanently raises
the camera. Level aim launches a horizontal projectile; authored bullet drop
and damage remain active. These are KOTM tuning values, not verified H1Z1 data.

The imported character's skeleton modifiers now advance with the existing bot
animation LOD. Previously they continued evaluating every frame even when the
animation player skipped updates. Rig binding, muzzle-chain and shared material
data are also cached. The local player's rig continues at full rate.

A controlled native Windows/GTX 1070 run with 30 close characters and the same
draft character binary measured mean frame time of 43.06 ms before the modifier
LOD change and 25.38 ms afterwards; p95 was 53.44 and 45.93 ms. This measures the
character scene, not a complete multiplayer match. The final exported character
still needs multiplayer load testing before setting a supported player count.

Regression checks cover one shot per press, early-click retention, reload/swap
cancellation, ten distinct AR taps per second, horizontal initial velocity and
equivalent recoil recovery at 30 and 144 FPS. The damage matrix's AR time-to-kill
expectation has been updated for the faster cadence.
