module retroseq.mixer;

import retroseq.interpolation;
import core.time;
import std.algorithm.comparison : clamp, max, min;
import std.math : pow;

struct Mixer {
	static struct Sound {
		private const(byte)[] samples;
		private size_t position;
		private ushort positionSubsample;
		private uint advanceDelta;
		private bool playing;
		private bool looping;
		private short volumeShared;
		private short panL;
		private short panR;
		private short volumeL;
		private short volumeR;

		/++
			Set the panning for this sound.
			Params:
				val = The panning value (millibels), ranging from -10000 (left) to 10000 (right).
		+/
		void pan(int val) @safe pure nothrow {
			panL = millibelToScale(-val);
			panR = millibelToScale(val);

			volumeL = cast(short)((panL * volumeShared) >> 8);
			volumeR = cast(short)((panR * volumeShared) >> 8);
		}
		/++
			Set the volume of this sound.
			Params:
				val = New volume (millibels), ranging from -10000 (quietest) to 0 (loudest)
		+/
		void volume(short val) @safe pure nothrow {
			volumeShared = millibelToScale(val);

			volumeL = cast(short)((panL * volumeShared) >> 8);
			volumeR = cast(short)((panR * volumeShared) >> 8);
		}
		/++
			Set the frequency for this sound.
			Params:
				val = Frequency (Hz)
		+/
		void frequency(uint val) @safe pure nothrow {
			advanceDelta = val << 16;
		}
		/++
			Start playing this sound, with optional looping
			Params:
				loop = Whether or not to loop
		+/
		void play(bool loop) @safe pure nothrow {
			playing = true;
			looping = loop;
		}
		/// Stop playing this sound
		void stop() @safe pure nothrow {
			playing = false;
		}
		/++
			Skip ahead in this sound's position
			Params:
				position = Position to seek to, in number of samples
		+/
		void seek(size_t position) @safe pure nothrow {
			this.position = position;
			positionSubsample = 0;
		}
	}
	private InterpolationMethod interpolationMethod;
	private uint outputFrequency = 48000;
	private void delegate() @safe nothrow callback;
	private Sound[] activeSoundList;
	private size_t samplesUntilNextCallback;
	private Duration callbackFrequency;
	/++
		Get a reference to an existing sound, suitable for modification.
		Params:
			id = The ID of the sound to delete, returned from createSound
	+/
	ref Sound getSound(size_t id) @safe pure nothrow {
		return activeSoundList[id];
	}
	/++
		Delete a sound.
		Params:
			id = The ID of the sound to delete, returned from createSound
	+/
	void removeSound(size_t id) @safe pure nothrow {
		import std.algorithm.mutation : remove;
		activeSoundList = activeSoundList.remove(id);
	}
	/++
		Create a new sound and add it to the sound list, returning an id to be used with getSound
		Params:
			inFrequency = The sound's default playback frequency
			inSamples = The 8-bit samples to play back
	+/
	size_t createSound(uint inFrequency, const(byte)[] inSamples) @safe pure {
		activeSoundList.length++;

		with (activeSoundList[$ - 1]) {
			samples = inSamples;

			playing = false;
			position = 0;
			positionSubsample = 0;

			frequency = inFrequency;
			volume = 0;
			pan = 0;
		}

		return activeSoundList.length - 1;
	}
	void setCallbackFrequency(Duration duration) @safe pure nothrow {
		callbackFrequency = duration;
		samplesUntilNextCallback = (duration.total!"msecs" * outputFrequency) / 1000;
	}
	/// Ditto
	size_t createSound(uint inFrequency, const(ubyte)[] inSamples) @safe pure {
		auto newSamples = new byte[](inSamples.length);
		foreach (idx, ref sample; newSamples) {
			sample = inSamples[idx] - 0x80;
		}
		return createSound(inFrequency, newSamples);
	}
	/// Get the next pair of mixed samples
	short[2] front() const @safe pure nothrow {
		short[2] result;
		foreach (const sound; activeSoundList) {
			if (!sound.playing) {
				continue;
			}
			// Interpolate the samples
			byte[8] interpolationBuffer;
			const remaining = max(cast(ptrdiff_t)0, cast(ptrdiff_t)(interpolationBuffer.length - (sound.samples.length - sound.position)));
			interpolationBuffer[0 .. $ - remaining] = sound.samples[sound.position .. min($, sound.position + 8)];
			if (sound.looping && (remaining > 0)) {
				interpolationBuffer[$ - remaining .. $] = sound.samples[0 .. remaining];
			}
			const outputSample = interpolate(interpolationMethod, interpolationBuffer[], sound.positionSubsample);

			// Mix, and apply volume
			result[0] = cast(short)clamp(result[0] + outputSample * sound.volumeL, short.min, short.max);
			result[1] = cast(short)clamp(result[1] + outputSample * sound.volumeR, short.min, short.max);
		}
		return result;
	}
	/// Pop the latest samples off, so the next pair can be mixed
	void popFront() @safe nothrow {
		if ((callback !is null) && (--samplesUntilNextCallback == 0)) {
			callback();
			samplesUntilNextCallback = (callbackFrequency.total!"msecs" * outputFrequency) / 1000;
		}
		foreach (ref sound; activeSoundList) {
			if (!sound.playing) {
				continue;
			}
			// Increment sample
			const uint nextPositionSubsample = sound.positionSubsample + sound.advanceDelta / outputFrequency;
			sound.position += nextPositionSubsample >> 16;
			sound.positionSubsample = nextPositionSubsample & 0xFFFF;

			// Stop or loop sample once it's reached its end
			if (sound.position >= (sound.samples.length)) {
				if (sound.looping) {
					sound.position %= sound.samples.length;
				} else {
					sound.playing = false;
					sound.position = 0;
					sound.positionSubsample = 0;
					break;
				}
			}
		}
	}
	/// Even if there's no sound playing, the mixer will never stop
	enum empty = false;
}
/++
	Convenience function for mixing to a stream
+/
void mixSounds(ref Mixer mixer, scope short[2][] stream) @safe nothrow {
	foreach (ref pair; stream) {
		assert(!mixer.empty);
		pair = mixer.front;
		mixer.popFront();
	}
}

@safe pure unittest {
	assert(Mixer().front == [0,0]);
	with (Mixer()) {
		interpolationMethod = InterpolationMethod.none;
		with(getSound(createSound(uint(48000), cast(const(byte)[])[1, 2, 3, 4, 5, 6, 7, 8]))) {
			pan = 0;
			volume = 32767;
			play(true);
		}
		import std.stdio; debug writeln(front);
		assert(front == [256, 256]);
	}
}

private ushort millibelToScale(int volume) @safe pure @nogc nothrow {
	// Volume is in hundredths of a decibel, from 0 to -10000
	volume = clamp(volume, -10000, 0);
	return cast(ushort)(pow(10.0, volume / 2000.0) * 256.0);
}
