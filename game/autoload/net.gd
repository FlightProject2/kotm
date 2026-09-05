extends Node
## RPC hub. Everything that must reach other peers goes through here so that the
## game runs identically in single player (Godot's default OfflineMultiplayerPeer
## makes this peer the server with id 1 and call_local RPCs execute immediately)
## and, later, over ENet.

const SERVER_ID := 1

func is_server() -> bool:
	return multiplayer.is_server()

func local_id() -> int:
	return multiplayer.get_unique_id()

## Reliable gameplay event to every peer (kill feed, zone state, loot changes...).
func event_all(event_name: String, args: Array = []) -> void:
	_rx_event.rpc(event_name, args)

## Reliable event to one peer (hit confirmations, inventory snapshots...).
func event_to(peer_id: int, event_name: String, args: Array = []) -> void:
	_rx_event.rpc_id(peer_id, event_name, args)

## Unreliable cosmetic effect to every peer (tracers, impact FX, gunshot audio).
func fx_all(fx_name: String, args: Array = []) -> void:
	_rx_fx.rpc(fx_name, args)

@rpc("authority", "call_local", "reliable")
func _rx_event(event_name: String, args: Array) -> void:
	_dispatch(event_name, args)

@rpc("authority", "call_local", "unreliable")
func _rx_fx(fx_name: String, args: Array) -> void:
	_dispatch(fx_name, args)

func _dispatch(signal_name: String, args: Array) -> void:
	if not Events.has_signal(signal_name):
		push_warning("Net: unknown event '%s'" % signal_name)
		return
	Events.callv("emit_signal", [signal_name] + args)
