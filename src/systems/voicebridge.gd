# voicebridge.gd - the browser's side of party voice (0.43.0): the JavaScript
# that makes the calls, and the GDScript that talks to it.
#
# WHY THE BROWSER. Godot's own WebRTC carries data, not sound, and has no echo
# cancellation. The browser's has everything a voice call needs - the
# microphone, Opus, a jitter buffer, echo cancellation, noise suppression,
# gain - so on the web the game hands the call to it: SOURCE below is put into
# the page once (JavaScriptBridge.eval) as window.elusionVoice, and this file
# calls it. Nothing in the game's own audio changes.
#
# ONE CALL PER OTHER PLAYER, a mesh: a party is at most four, so each game
# sends its voice three ways at most - tens of kilobits each. Every call goes
# through the TURN relay the server named (iceTransportPolicy "relay"), so no
# game ever sees another's address; only a test on one computer is told "all".
#
# WHAT GOES WHERE. The page keeps the calls; voice.gd (the Voice autoload)
# decides who to call and carries each call's setup over the presence socket:
# dial() starts a call (the one who joined voice later calls - presence.py
# PARTY VOICE), hear() takes the other side's setup, take_outbox() is the setup
# this side wants sent, and levels() how loud each is, for who is speaking.
#
# THE JAVASCRIPT HAS NO BACKSLASH IN IT, ON PURPOSE: it sits inside a GDScript
# string, where one would be read as an escape before the browser saw it. The
# suite checks.
#
# THE SETTINGS (0.45.0, the Party window's Voice settings). The microphone goes
# out through the page's own audio: its volume (setMicVolume, to 200%), then
# the open-mic gate (setGate: only what is louder than the line goes out), into
# a track every call sends - so a new microphone, for the noise and echo
# switches (setProcessing), is put in at the start and no call notices. Each
# voice's volume (setVolume, to 200%) is the call's own up to 100%; over it,
# the page makes the voice louder, through a limiter, and plays it through a
# call to itself, because the browser's echo cancellation hears only what a
# call plays (Chrome, issue 687574): a voice boosted straight to the speakers
# would come back to its owner as an echo. levels() says the microphone's level
# whether or not it is going out, for the level bar.
#
# Off the web there is no bridge (make() returns null) and voice says it is in
# the browser version.
extends RefCounted
class_name VoiceBridge


const SOURCE := """(function () {
	"use strict";
	var VERSION = "2";
	if (window.elusionVoice && window.elusionVoice.version === VERSION) return;
	if (window.elusionVoice && window.elusionVoice.stop) {
		try { window.elusionVoice.stop(); } catch (e) {}
	}
	// Voices above BOOST_FROM are made louder in the page's own audio, then
	// played through a call to itself: the browser's echo cancellation only
	// hears what a call plays, so a voice boosted straight to the speakers
	// would come back to its owner as an echo.
	var BOOST_FROM = 1;
	var MOST = 2;
	// The open-mic gate: how long it stays open after the last loud moment,
	// and how often it looks.
	var GATE_HOLD_MS = 350;
	var GATE_EVERY_MS = 20;
	var V = {
		version: VERSION,
		st: "off",
		why: "",
		cfg: { ice_servers: [], policy: "relay", me: 0 },
		raw: null,
		stream: null,
		track: null,
		open: false,
		peers: new Map(),
		out: [],
		chains: new Map(),
		vols: new Map(),
		ctx: null,
		micSrc: null,
		micGain: null,
		gateNode: null,
		micOut: null,
		micMeter: null,
		micVol: 1,
		gateLevel: 0,
		gateOpen: true,
		loudAt: 0,
		gateTimer: 0,
		ec: true,
		ns: true
	};

	function send(to, d) {
		V.out.push([to, d]);
	}

	function clamp(v, lo, hi) {
		var n = Number(v);
		if (!isFinite(n)) n = lo;
		return Math.max(lo, Math.min(hi, n));
	}

	function audioCtx() {
		if (!V.ctx) V.ctx = new (window.AudioContext || window.webkitAudioContext)();
		if (V.ctx.state === "suspended") V.ctx.resume().catch(function () {});
		return V.ctx;
	}

	function stopTracks(stream) {
		if (stream) stream.getTracks().forEach(function (t) { t.stop(); });
	}

	function analyse(node) {
		var analyser = V.ctx.createAnalyser();
		analyser.fftSize = 512;
		node.connect(analyser);
		var buf = new Uint8Array(analyser.fftSize);
		return function () {
			analyser.getByteTimeDomainData(buf);
			var sum = 0;
			for (var i = 0; i < buf.length; i++) {
				var v = (buf[i] - 128) / 128;
				sum += v * v;
			}
			return Math.sqrt(sum / buf.length);
		};
	}

	function meter(stream) {
		try {
			audioCtx();
			return analyse(V.ctx.createMediaStreamSource(stream));
		} catch (e) {
			return function () { return 0; };
		}
	}

	function constraints() {
		return {
			audio: { echoCancellation: V.ec, noiseSuppression: V.ns, autoGainControl: true },
			video: false
		};
	}

	// THE MICROPHONE'S WAY OUT: microphone, its volume, the open-mic gate, and
	// a track of its own that every call sends. A new microphone (the noise or
	// echo switch) is put in at the start and no call notices. Null where the
	// page has no audio of its own: the microphone is then sent as it is.
	function buildMic(raw) {
		try {
			audioCtx();
			if (!V.micOut) {
				V.micGain = V.ctx.createGain();
				V.gateNode = V.ctx.createGain();
				V.micOut = V.ctx.createMediaStreamDestination();
				V.micGain.connect(V.gateNode);
				V.gateNode.connect(V.micOut);
				V.micMeter = analyse(V.micGain);
			}
			V.micGain.gain.value = V.micVol;
			V.gateNode.gain.value = 1;
			V.micSrc = V.ctx.createMediaStreamSource(raw);
			V.micSrc.connect(V.micGain);
			return V.micOut.stream;
		} catch (e) {
			V.micSrc = null;
			return null;
		}
	}

	function micLevel() {
		if (V.micMeter) return V.micMeter();
		return 0;
	}

	function setGate(open) {
		if (open === V.gateOpen) return;
		V.gateOpen = open;
		if (V.gateNode) {
			V.gateNode.gain.setTargetAtTime(open ? 1 : 0, V.ctx.currentTime, open ? 0.005 : 0.04);
		} else if (V.track) {
			V.track.enabled = V.open && open;
		}
	}

	function gateTick() {
		if (V.st !== "live") return;
		if (V.gateLevel <= 0 || document.hidden) {
			setGate(true);
			return;
		}
		var now = Date.now();
		if (micLevel() >= V.gateLevel) V.loudAt = now;
		setGate(now - V.loudAt < GATE_HOLD_MS);
	}

	// A CALL TO ITSELF, for a boosted voice: what the page made louder goes in
	// one end and comes out the other as a call the speakers play.
	function loopback(stream, done) {
		var a = new RTCPeerConnection();
		var b = new RTCPeerConnection();
		a.onicecandidate = function (e) { if (e.candidate) b.addIceCandidate(e.candidate).catch(function () {}); };
		b.onicecandidate = function (e) { if (e.candidate) a.addIceCandidate(e.candidate).catch(function () {}); };
		b.ontrack = function (e) { done((e.streams && e.streams[0]) ? e.streams[0] : new MediaStream([e.track])); };
		stream.getAudioTracks().forEach(function (t) { a.addTrack(t, stream); });
		a.createOffer().then(function (o) {
			return a.setLocalDescription(o);
		}).then(function () {
			return b.setRemoteDescription(a.localDescription);
		}).then(function () {
			return b.createAnswer();
		}).then(function (o) {
			return b.setLocalDescription(o);
		}).then(function () {
			return a.setRemoteDescription(b.localDescription);
		}).catch(function () {});
		return { a: a, b: b };
	}

	function unboost(p) {
		var k = p.boost;
		if (!k) return;
		p.boost = null;
		try { k.loop.a.close(); } catch (e) {}
		try { k.loop.b.close(); } catch (e) {}
		try { k.src.disconnect(); } catch (e) {}
		try { k.gain.disconnect(); } catch (e) {}
		try { k.limit.disconnect(); } catch (e) {}
	}

	function play(p, stream) {
		if (p.audio.srcObject !== stream) p.audio.srcObject = stream;
		var playing = p.audio.play();
		if (playing && playing.catch) playing.catch(function () {});
	}

	// How loud one voice is, 0 to MOST. Up to BOOST_FROM the call plays as it
	// comes, at that volume; over it, through the page's gain and a limiter
	// (so a shout does not crackle) and the call to itself.
	function applyVolume(p) {
		if (!p.remote) return;
		var vol = p.vol;
		if (vol <= BOOST_FROM || !window.RTCPeerConnection) {
			unboost(p);
			play(p, p.remote);
			p.audio.volume = Math.min(1, vol);
			return;
		}
		try {
			audioCtx();
			if (!p.boost) {
				var k = { src: V.ctx.createMediaStreamSource(p.remote), gain: V.ctx.createGain(),
					limit: V.ctx.createDynamicsCompressor(), dest: V.ctx.createMediaStreamDestination(),
					loop: null, ready: false };
				k.limit.threshold.value = -6;
				k.limit.knee.value = 0;
				k.limit.ratio.value = 20;
				k.limit.attack.value = 0.003;
				k.limit.release.value = 0.1;
				k.src.connect(k.gain);
				k.gain.connect(k.limit);
				k.limit.connect(k.dest);
				p.boost = k;
				k.loop = loopback(k.dest.stream, function (looped) {
					if (p.boost !== k) return;
					k.ready = true;
					play(p, looped);
					p.audio.volume = 1;
				});
			}
			p.boost.gain.gain.value = vol;
			if (!p.boost.ready) {
				play(p, p.remote);
				p.audio.volume = 1;
			}
		} catch (e) {
			unboost(p);
			play(p, p.remote);
			p.audio.volume = 1;
		}
	}

	function makePeer(id, caller) {
		var pc = new RTCPeerConnection({
			iceServers: V.cfg.ice_servers || [],
			iceTransportPolicy: V.cfg.policy === "all" ? "all" : "relay"
		});
		var audio = document.createElement("audio");
		audio.autoplay = true;
		audio.style.display = "none";
		document.body.appendChild(audio);
		// THE CALL, PLAYED SILENT: the page's own audio hears nothing from a
		// call no element is playing, so the speaking light and the boost
		// read it from here while the audible element may play something else.
		var sink = document.createElement("audio");
		sink.autoplay = true;
		sink.muted = true;
		sink.style.display = "none";
		document.body.appendChild(sink);
		var p = { pc: pc, audio: audio, sink: sink, caller: caller, remote: null, boost: null,
			vol: V.vols.has(id) ? V.vols.get(id) : 1, meter: null, queued: [] };
		pc.onicecandidate = function (e) {
			if (e.candidate) send(id, { k: "ice", c: e.candidate.toJSON() });
		};
		pc.ontrack = function (e) {
			var s = (e.streams && e.streams[0]) ? e.streams[0] : new MediaStream([e.track]);
			p.remote = s;
			sink.srcObject = s;
			var silent = sink.play();
			if (silent && silent.catch) silent.catch(function () {});
			p.meter = meter(s);
			applyVolume(p);
		};
		pc.onconnectionstatechange = function () {
			if (pc.connectionState === "failed" && p.caller) {
				try { pc.restartIce(); } catch (e) {}
			}
		};
		pc.onnegotiationneeded = function () {
			if (!p.caller) return;
			pc.setLocalDescription().then(function () {
				send(id, { k: "sdp", sdp: pc.localDescription.toJSON() });
			}).catch(function () {});
		};
		V.peers.set(id, p);
		return p;
	}

	function flushQueued(p) {
		var queued = p.queued;
		p.queued = [];
		return queued.reduce(function (chain, c) {
			return chain.then(function () { return p.pc.addIceCandidate(c).catch(function () {}); });
		}, Promise.resolve());
	}

	function handle(from, d) {
		var p = V.peers.get(from);
		if (d.k === "sdp" && d.sdp && d.sdp.type === "offer") {
			if (p && p.caller) {
				// BOTH CALLED: the lower id keeps calling, the higher answers.
				if (V.cfg.me < from) return Promise.resolve();
				V.hangup(from);
				p = null;
			}
			if (!p) p = makePeer(from, false);
			var pc = p.pc;
			return pc.setRemoteDescription(d.sdp).then(function () {
				var t = pc.getTransceivers().find(function (x) {
					return x.receiver && x.receiver.track && x.receiver.track.kind === "audio";
				});
				if (t) {
					t.direction = "sendrecv";
					if (t.sender.setStreams) t.sender.setStreams(V.stream);
					return t.sender.replaceTrack(V.track);
				}
			}).then(function () {
				return pc.setLocalDescription();
			}).then(function () {
				send(from, { k: "sdp", sdp: pc.localDescription.toJSON() });
				return flushQueued(p);
			});
		}
		if (d.k === "sdp" && d.sdp && d.sdp.type === "answer" && p) {
			return p.pc.setRemoteDescription(d.sdp).then(function () { return flushQueued(p); });
		}
		if (d.k === "ice" && d.c && p) {
			if (!p.pc.remoteDescription) {
				p.queued.push(d.c);
				return Promise.resolve();
			}
			return p.pc.addIceCandidate(d.c).catch(function () {});
		}
		return Promise.resolve();
	}

	V.start = function (cfgJson) {
		if (V.st === "live" || V.st === "starting") return V.st;
		try {
			V.cfg = JSON.parse(cfgJson);
		} catch (e) {
			V.st = "error";
			V.why = "bad settings";
			return V.st;
		}
		if (!window.RTCPeerConnection || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
			V.st = "error";
			V.why = "this browser has no voice calling";
			return V.st;
		}
		V.st = "starting";
		V.why = "";
		try { audioCtx(); } catch (e) {}
		navigator.mediaDevices.getUserMedia(constraints()).then(function (raw) {
			if (V.st !== "starting") {
				stopTracks(raw);
				return;
			}
			V.raw = raw;
			V.stream = buildMic(raw) || raw;
			V.track = V.stream.getAudioTracks()[0];
			V.gateOpen = true;
			V.track.enabled = V.open;
			V.loudAt = 0;
			V.gateTimer = setInterval(gateTick, GATE_EVERY_MS);
			V.st = "live";
		}).catch(function (err) {
			var name = err && err.name ? err.name : String(err);
			V.st = (name === "NotAllowedError" || name === "SecurityError") ? "denied" : "error";
			V.why = name;
		});
		return V.st;
	};

	V.stop = function () {
		Array.from(V.peers.keys()).forEach(function (id) { V.hangup(id); });
		if (V.gateTimer) clearInterval(V.gateTimer);
		V.gateTimer = 0;
		if (V.micSrc) {
			try { V.micSrc.disconnect(); } catch (e) {}
		}
		V.micSrc = null;
		stopTracks(V.raw);
		if (V.stream && V.stream !== V.raw) stopTracks(V.stream);
		if (V.micOut) {
			try { V.micGain.disconnect(); } catch (e) {}
			try { V.gateNode.disconnect(); } catch (e) {}
		}
		V.micOut = null;
		V.micGain = null;
		V.gateNode = null;
		V.micMeter = null;
		V.raw = null;
		V.stream = null;
		V.track = null;
		V.out = [];
		V.chains = new Map();
		V.st = "off";
		V.why = "";
	};

	V.status = function () { return V.st; };
	V.reason = function () { return V.why; };

	V.dial = function (id) {
		if (V.st !== "live" || V.peers.has(id)) return false;
		var p = makePeer(id, true);
		p.pc.addTransceiver(V.track, { direction: "sendrecv", streams: [V.stream] });
		return true;
	};

	V.hear = function (from, json) {
		if (V.st !== "live") return;
		var d;
		try {
			d = JSON.parse(json);
		} catch (e) {
			return;
		}
		if (!d || typeof d !== "object") return;
		var chain = (V.chains.get(from) || Promise.resolve()).then(function () {
			return handle(from, d);
		}).catch(function () {});
		V.chains.set(from, chain);
	};

	V.hangup = function (id) {
		var p = V.peers.get(id);
		if (!p) return;
		unboost(p);
		try { p.pc.close(); } catch (e) {}
		[p.audio, p.sink].forEach(function (el) {
			el.srcObject = null;
			if (el.parentNode) el.parentNode.removeChild(el);
		});
		V.peers.delete(id);
		V.chains.delete(id);
	};

	V.setMic = function (open) {
		V.open = !!open;
		if (V.track) V.track.enabled = V.open && (V.gateNode ? true : V.gateOpen);
	};

	V.setVolume = function (id, v) {
		var vol = clamp(v, 0, MOST);
		V.vols.set(id, vol);
		var p = V.peers.get(id);
		if (!p) return;
		p.vol = vol;
		applyVolume(p);
	};

	// The settings: kept while voice is off, used when it starts.
	V.setMicVolume = function (v) {
		V.micVol = clamp(v, 0, MOST);
		if (V.micGain) V.micGain.gain.value = V.micVol;
	};

	V.setGate = function (level) {
		V.gateLevel = clamp(level, 0, 1);
		if (V.gateLevel <= 0) setGate(true);
	};

	V.setProcessing = function (ec, ns) {
		var changed = V.ec !== !!ec || V.ns !== !!ns;
		V.ec = !!ec;
		V.ns = !!ns;
		if (!changed || V.st !== "live") return;
		navigator.mediaDevices.getUserMedia(constraints()).then(function (raw) {
			if (V.st !== "live") {
				stopTracks(raw);
				return;
			}
			var old = V.raw;
			V.raw = raw;
			if (V.micSrc) {
				try { V.micSrc.disconnect(); } catch (e) {}
				V.micSrc = V.ctx.createMediaStreamSource(raw);
				V.micSrc.connect(V.micGain);
			} else {
				var t = raw.getAudioTracks()[0];
				t.enabled = V.track ? V.track.enabled : V.open;
				V.stream = raw;
				V.track = t;
				V.peers.forEach(function (p) {
					p.pc.getSenders().forEach(function (s) {
						if (s.track && s.track.kind === "audio") s.replaceTrack(t).catch(function () {});
					});
				});
			}
			stopTracks(old);
		}).catch(function () {});
	};

	V.takeOutbox = function () {
		var out = V.out;
		V.out = [];
		return JSON.stringify(out);
	};

	V.levels = function () {
		if (V.ctx && V.ctx.state === "suspended" && V.st === "live") V.ctx.resume().catch(function () {});
		var peers = {};
		V.peers.forEach(function (p, id) {
			peers[id] = { lv: p.meter ? p.meter() : 0, st: p.pc.connectionState,
				boost: !!(p.boost && p.boost.ready) };
		});
		var mic = V.st === "live" ? micLevel() : 0;
		var t = V.raw ? V.raw.getAudioTracks()[0] : null;
		var made = t && t.getSettings ? t.getSettings() : {};
		return JSON.stringify({
			st: V.st,
			mic: mic,
			me: (V.open && V.gateOpen) ? mic : 0,
			gate: V.gateOpen,
			ec: made.echoCancellation === undefined ? V.ec : !!made.echoCancellation,
			ns: made.noiseSuppression === undefined ? V.ns : !!made.noiseSuppression,
			peers: peers
		});
	};

	// For the browser test: bytes of voice each way, per call.
	V.stats = function () {
		var ids = Array.from(V.peers.keys());
		return Promise.all(ids.map(function (id) {
			return V.peers.get(id).pc.getStats().then(function (report) {
				var sent = 0, got = 0, relay = false;
				report.forEach(function (r) {
					if (r.type === "outbound-rtp" && r.kind === "audio") sent += r.bytesSent || 0;
					if (r.type === "inbound-rtp" && r.kind === "audio") got += r.bytesReceived || 0;
					if (r.type === "local-candidate" && r.candidateType === "relay") relay = true;
				});
				return [id, { sent: sent, got: got, relay: relay, st: V.peers.get(id).pc.connectionState }];
			});
		})).then(function (rows) {
			var out = {};
			rows.forEach(function (r) { out[r[0]] = r[1]; });
			return out;
		});
	};

	window.elusionVoice = V;
})();
"""

var _js: Variant = null


static func make() -> VoiceBridge:
	"""The bridge, on the web; null anywhere else."""
	if not OS.has_feature("web"):
		return null
	JavaScriptBridge.eval(SOURCE, true)
	var bridge := VoiceBridge.new()
	bridge._js = JavaScriptBridge.get_interface("elusionVoice")
	return bridge if bridge._js != null else null


func start(config_json: String) -> void:
	_js.start(config_json)


func stop() -> void:
	_js.stop()


func status() -> String:
	return str(_js.status())


func reason() -> String:
	return str(_js.reason())


func dial(id: int) -> void:
	_js.dial(id)


func hear(from_id: int, json: String) -> void:
	_js.hear(from_id, json)


func hangup(id: int) -> void:
	_js.hangup(id)


func set_mic(open: bool) -> void:
	_js.setMic(open)


func set_volume(id: int, volume: float) -> void:
	_js.setVolume(id, volume)


func set_mic_volume(volume: float) -> void:
	_js.setMicVolume(volume)


func set_gate(level: float) -> void:
	_js.setGate(level)


func set_processing(echo: bool, noise: bool) -> void:
	_js.setProcessing(echo, noise)


func take_outbox() -> String:
	return str(_js.takeOutbox())


func levels() -> String:
	return str(_js.levels())
