# Snow vehicle test yard

Open `game/dev/vehicle_test_yard.tscn` in Godot 4.6.3 and press **F6**, or run:

```sh
godot --path . res://game/dev/vehicle_test_yard.tscn
```

The yard starts with the game's character seated in each vehicle. **F1** selects the snow truck's driver; **F2** selects the snow mobile UTV's driver. Both use the normal character, vehicle and input systems.

| Control | Action |
| --- | --- |
| W / S | Accelerate, brake, reverse |
| A / D | Steer |
| Space | Handbrake |
| F | Exit beside the vehicle; press again nearby to enter |
| Mouse | Look around the vehicle or character |
| F3 | Toggle a close exterior inspection view |
| R | Return both vehicles and drivers to their starting positions |
| Esc | Release or capture the cursor |

Use the inspection view to check the driver's face through the truck windows, the seated posture, and hands and feet touching the controls. Drive, reverse and steer to check that moving parts respond to the vehicle. The posts are 10 metres apart. The yard resets automatically near its edge.

The imported snow truck is used by the `pickup_truck` and `police_car` game definitions; the snow mobile UTV is used by `atv` and `offroader`. They therefore also appear at the existing vehicle spawn locations in normal matches.

Run the vehicle regression checks with:

```sh
godot --headless --path . --script res://tools/godot/run_tests.gd -- --filter=test_vehicle
```
