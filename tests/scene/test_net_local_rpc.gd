extends TestCase
## Verifies the single-player assumption: with no multiplayer peer set, this process is
## the server (id 1) and call_local RPCs execute immediately with sender id 1.

class Pinger extends Node:
	var got := -1
	var sender := -99
	@rpc("authority", "call_local", "reliable")
	func _ping(v: int) -> void:
		got = v
		sender = multiplayer.get_remote_sender_id()

func test_offline_peer_is_server() -> void:
	var p := Pinger.new()
	await add_to_tree(p)
	assert_true(p.multiplayer.is_server(), "offline peer acts as server")
	assert_eq(p.multiplayer.get_unique_id(), 1)
	p._ping.rpc(7)
	await settle(1)
	assert_eq(p.got, 7, "call_local rpc ran locally")
	assert_eq(p.sender, 1, "remote sender id during local call is the server id")
	p.queue_free()
