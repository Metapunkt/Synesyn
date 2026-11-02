// ScenSyn Ambient Sound Engine — SuperCollider receiver
// Launch: open this file in SuperCollider IDE and evaluate the whole buffer (Ctrl+Enter on the block).
// Or from command line: sclang scensyn_ambient.scd
//
// Listens for OSC from Godot's AmbientSoundBridge on port 57120 (SC default).
// All synths output through a master bus for ducking control.

(
s.options.memSize = 65536;

if(s.serverRunning, {
	"ScenSyn SC: Server already running — freeing all nodes".postln;
	s.freeAll;
});

s.waitForBoot({

	// ---- Buses ----
	// All ambient synths write to a private bus; a master synth copies to hardware
	// with a controllable volume multiplier for ducking.
	~ambientBus = Bus.audio(s, 2);

	// ---- SynthDefs ----

	// Master volume control — sits at tail of default group, reads ambient bus
	SynthDef(\scensyn_master, { |in=0, out=0, duckLevel=1.0|
		var sig = In.ar(in, 2);
		Out.ar(out, sig * duckLevel.lag(3));
	}).add;

	// Breathing pad — slow LFO on amplitude gives organic swell instead of constant drone
	SynthDef(\scensyn_pad, { |out=0, freq=110, amp=0.12, gate=1, cutoff=800, res=0.3|
		var sig, env, breath;
		sig = Mix.fill(4, { |i|
			LFSaw.ar(freq * (1 + (i * 0.007)), Rand(0, 2pi))
		}) * 0.25;
		sig = RLPF.ar(sig, cutoff.lag(4), res);
		// Slow breathing: amplitude swells over 8-14 seconds
		breath = LFNoise1.kr(Rand(0.07, 0.12)).range(0.2, 1.0);
		env = EnvGen.kr(Env.asr(8, 1, 10), gate, doneAction: 2);
		Out.ar(out, Pan2.ar(sig * env * amp.lag(3) * breath, LFNoise1.kr(0.05).range(-0.3, 0.3)));
	}).add;

	// Spectral shimmer — granular-ish texture from filtered noise
	SynthDef(\scensyn_shimmer, { |out=0, amp=0.06, gate=1, density=4, brightness=2000|
		var sig, env, trig;
		trig = Dust.kr(density);
		sig = Ringz.ar(trig * WhiteNoise.ar(0.3), TRand.kr(200, brightness, trig), 0.8);
		sig = HPF.ar(sig, 300);
		env = EnvGen.kr(Env.asr(4, 1, 6), gate, doneAction: 2);
		Out.ar(out, Pan2.ar(sig * env * amp.lag(3), LFNoise1.kr(0.2)));
	}).add;

	// Deep drone — sub-bass pulse, with breathing envelope so it's not constant
	SynthDef(\scensyn_drone, { |out=0, freq=55, amp=0.1, gate=1|
		var sig, env, breath;
		sig = SinOsc.ar(freq, 0, amp) + SinOsc.ar(freq * 1.5, 0, amp * 0.3);
		// Slow pulse: present for ~60% of each 10s cycle, then retreats
		breath = LFNoise1.kr(0.08).range(0.0, 1.0);
		sig = LPF.ar(sig, 200);
		env = EnvGen.kr(Env.asr(10, 1, 12), gate, doneAction: 2);
		Out.ar(out, Pan2.ar(sig * env * breath, 0));
	}).add;

	// Percussive texture — soft metallic hits
	SynthDef(\scensyn_perc, { |out=0, freq=800, amp=0.05, pan=0|
		var sig, env;
		sig = Ringz.ar(Impulse.ar(0), freq, 0.3, amp);
		sig = sig + Ringz.ar(Impulse.ar(0), freq * 1.618, 0.2, amp * 0.5);
		env = EnvGen.kr(Env.perc(0.005, 1.5), doneAction: 2);
		Out.ar(out, Pan2.ar(sig * env, pan));
	}).add;

	s.sync;

	if(s.serverRunning.not, {
		"ERROR: scsynth did not boot. Check your audio device settings.".postln;
	}, {

	// ---- Master synth (must be at tail so it reads after ambient synths write) ----
	~masterSynth = Synth(\scensyn_master, [\in, ~ambientBus.index, \out, 0], s, \addToTail);

	// ---- State ----
	~activeSynths = Dictionary.new;
	~currentMood = \silence;
	~currentIntensity = 0.3;
	~lastMoodChangeTime = 0;

	// Note: all mood synths write to ~ambientBus, not hardware out directly
	~moodMap = (
		contemplative: [
			(\def: \scensyn_pad,   \args: [\out, ~ambientBus.index, \freq, 110, \cutoff, 600, \amp, 0.08]),
			(\def: \scensyn_shimmer, \args: [\out, ~ambientBus.index, \density, 2, \brightness, 1500, \amp, 0.04])
		],
		tension: [
			(\def: \scensyn_pad,   \args: [\out, ~ambientBus.index, \freq, 73.4, \cutoff, 400, \amp, 0.10, \res, 0.5]),
			(\def: \scensyn_drone, \args: [\out, ~ambientBus.index, \freq, 36.7, \amp, 0.08]),
			(\def: \scensyn_shimmer, \args: [\out, ~ambientBus.index, \density, 6, \brightness, 3000, \amp, 0.04])
		],
		wonder: [
			(\def: \scensyn_shimmer, \args: [\out, ~ambientBus.index, \density, 8, \brightness, 4000, \amp, 0.06]),
			(\def: \scensyn_pad,   \args: [\out, ~ambientBus.index, \freq, 146.8, \cutoff, 1200, \amp, 0.07])
		],
		stillness: [
			(\def: \scensyn_shimmer, \args: [\out, ~ambientBus.index, \density, 1, \brightness, 1000, \amp, 0.03]),
			(\def: \scensyn_drone, \args: [\out, ~ambientBus.index, \freq, 55, \amp, 0.05])
		],
		ceremony: [
			(\def: \scensyn_pad,   \args: [\out, ~ambientBus.index, \freq, 98, \cutoff, 900, \amp, 0.09]),
			(\def: \scensyn_drone, \args: [\out, ~ambientBus.index, \freq, 49, \amp, 0.07]),
			(\def: \scensyn_shimmer, \args: [\out, ~ambientBus.index, \density, 3, \brightness, 2000, \amp, 0.04])
		],
		silence: []
	);

	// ---- Helpers ----

	~fadeOutAll = {
		~activeSynths.keysValuesDo({ |key, synth|
			if(synth.isPlaying, { synth.set(\gate, 0) });
		});
		~activeSynths = Dictionary.new;
	};

	~applyMood = { |mood, intensity|
		var specs, now;
		now = Main.elapsedTime;
		if((now - ~lastMoodChangeTime) < 2.0, {
			"ScenSyn SC: mood change throttled".postln;
		}, {
			~lastMoodChangeTime = now;
			~currentMood = mood;
			~currentIntensity = intensity;
			specs = ~moodMap[mood];
			if(specs.isNil, {
				"ScenSyn SC: Unknown mood '%', falling back to contemplative".format([mood]).postln;
				specs = ~moodMap[\contemplative];
			});
			~fadeOutAll.value;
			specs.do({ |spec, i|
				var synth, args, ampArg;
				args = spec[\args].copy;
				ampArg = args.indexOf(\amp);
				if(ampArg.notNil, {
					args[ampArg + 1] = args[ampArg + 1] * intensity;
				});
				synth = Synth(spec[\def], args);
				~activeSynths.put(i, synth);
			});
			"ScenSyn SC: mood=% intensity=% synths=%".format([mood, intensity, ~activeSynths.size]).postln;
		});
	};

	// ---- OSC arg helper (handles bundled-array format from Godot) ----

	~oscArg = { |msg, index, fallback|
		var raw = msg[index];
		if(raw.isKindOf(Array), {
			if((index - 1) < raw.size, { raw[index - 1] }, { fallback })
		}, {
			raw ? fallback
		})
	};

	// ---- OSC Responders ----

	OSCdef(\scensyn_mood, { |msg|
		var mood = ~oscArg.value(msg, 1, \contemplative).asSymbol;
		var intensity = ~oscArg.value(msg, 2, 0.5).asFloat;
		~applyMood.value(mood, intensity);
	}, '/scensyn/mood');

	OSCdef(\scensyn_phase, { |msg|
		var phase = ~oscArg.value(msg, 1, "setup").asString;
		"ScenSyn SC: phase changed to %".format([phase]).postln;
	}, '/scensyn/phase');

	OSCdef(\scensyn_turn, { |msg|
		var turn = ~oscArg.value(msg, 1, 0).asInteger;
		"ScenSyn SC: turn [%]".format([turn]).postln;
		Synth(\scensyn_perc, [\out, ~ambientBus.index, \freq, rrand(400, 1200), \amp, 0.03 * ~currentIntensity, \pan, rrand(-0.5, 0.5)]);
	}, '/scensyn/turn');

	OSCdef(\scensyn_speaker, { |msg|
		var speaker = ~oscArg.value(msg, 1, "").asString;
		"ScenSyn SC: speaker [%]".format([speaker]).postln;
	}, '/scensyn/speaker');

	// Duck/unduck: Godot sends duck level (0.15 = ducked, 1.0 = full)
	OSCdef(\scensyn_duck, { |msg|
		var level = ~oscArg.value(msg, 1, 1.0).asFloat;
		"ScenSyn SC: duck level=%".format([level]).postln;
		if(~masterSynth.notNil, {
			~masterSynth.set(\duckLevel, level);
		});
	}, '/scensyn/duck');

	OSCdef(\scensyn_lull, { |msg|
		var tier = ~oscArg.value(msg, 1, 0).asInteger;
		var elapsed = ~oscArg.value(msg, 2, 0.0).asFloat;
		"ScenSyn SC: lull tier=% elapsed=%s".format([tier, elapsed]).postln;
		switch(tier,
			0, { /* no change */ },
			1, { ~applyMood.value(\stillness, 0.4) },
			2, { ~applyMood.value(\contemplative, 0.5) },
			3, { ~applyMood.value(\ceremony, 0.6) },
			4, { ~applyMood.value(\stillness, 0.3) }
		);
	}, '/scensyn/lull');

	OSCdef(\scensyn_stop, { |msg|
		"ScenSyn SC: stop".postln;
		~fadeOutAll.value;
	}, '/scensyn/stop');

	"".postln;
	"=== ScenSyn Ambient Sound Engine ready ===".postln;
	"Server: % (% Hz sample rate)".format([s.name, s.sampleRate]).postln;
	"Audio device: %".format([s.options.device ? "system default"]).postln;
	"Listening for OSC on port %".format([NetAddr.langPort]).postln;
	"".postln;
	">>> Playing 440Hz test tone — you should hear this <<<".postln;
	{ EnvGen.ar(Env.perc(0.05, 1.0), doneAction: 2) * SinOsc.ar(440, 0, 0.2) ! 2 }.play;

	// Start ambient after 3 seconds
	SystemClock.sched(3.0, {
		"ScenSyn SC: Starting default contemplative mood".postln;
		~applyMood.value(\contemplative, 0.3);
		nil
	});

	"".postln;
	}); // end if(s.serverRunning)
}, onFailure: {
	"".postln;
	"!!! CRITICAL: SuperCollider audio server failed to boot !!!".postln;
	"Try: ServerOptions.devices  // to list available audio devices".postln;
	"Then: s.options.device = \"your_device\"; and re-evaluate this script.".postln;
	"".postln;
});
)
