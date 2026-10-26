## Finds games on the local network. A host broadcasts a small UDP beacon every
## second; browsing clients listen for it and list the hosts they hear.
## (UDP is not available in web builds; there the player types the host's IP.)
class_name LanDiscovery
extends Node

signal hosts_changed(hosts: Array)

const BEACON_INTERVAL := 1.0
const HOST_TIMEOUT := 3.5
const MAGIC := "KARTCLASH"

var port := 24681
var _udp := PacketPeerUDP.new()
var _advertising := false
var _listening := false
var _beacon: Dictionary = {}
var _timer := 0.0
## ip -> {ip, name, players, mode, port, age}
var _hosts: Dictionary = {}


static func is_supported() -> bool:
	return not OS.has_feature("web")


## Host side: broadcast `info` (name, players, mode, port) until stop().
func advertise(info: Dictionary) -> void:
	stop()
	if not is_supported():
		return
	_beacon = info
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", port)
	_advertising = true
	_timer = BEACON_INTERVAL


func update_info(info: Dictionary) -> void:
	_beacon = info


## Client side: listen for beacons.
func browse() -> Error:
	stop()
	if not is_supported():
		return ERR_UNAVAILABLE
	var err := _udp.bind(port, "*")
	if err != OK:
		return err
	_listening = true
	_hosts.clear()
	return OK


func stop() -> void:
	_udp.close()
	_udp = PacketPeerUDP.new()
	_advertising = false
	_listening = false


func get_hosts() -> Array:
	return _hosts.values()


func _process(delta: float) -> void:
	if _advertising:
		_timer += delta
		if _timer >= BEACON_INTERVAL:
			_timer = 0.0
			var msg := _beacon.duplicate()
			msg["magic"] = MAGIC
			_udp.put_packet(JSON.stringify(msg).to_utf8_buffer())
	if _listening:
		var changed := false
		while _udp.get_available_packet_count() > 0:
			var data := _udp.get_packet().get_string_from_utf8()
			var ip := _udp.get_packet_ip()
			var msg: Variant = JSON.parse_string(data)
			if msg is Dictionary and msg.get("magic", "") == MAGIC:
				var entry: Dictionary = msg
				entry["ip"] = ip
				entry["age"] = 0.0
				if not _hosts.has(ip):
					changed = true
				_hosts[ip] = entry
		for ip in _hosts.keys():
			_hosts[ip]["age"] = float(_hosts[ip]["age"]) + delta
			if float(_hosts[ip]["age"]) > HOST_TIMEOUT:
				_hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit(get_hosts())
