///
module retroseq.nspc.player;

import retroseq.nspc.common;
import retroseq.nspc.song;
import retroseq.nspc.sequence;
import retroseq.nspc.samples;

import std.algorithm.comparison;
import std.exception;
import std.experimental.logger;
import std.format;
import std.typecons;

enum uint nativeSamplingRate = 32000; ///

///
private struct SongState {
	ChannelState[] channels; ///
	byte transpose; ///
	Slider volume = Slider(0xC000); ///
	Slider tempo; ///
	int nextTimerTick; ///
	int cycleTimer = 255; ///
	ubyte percussionBase; /// set with FA
	ubyte repeatCount; ///
	int phraseCounter = -1; ///

	ubyte fadeTicks; ///
	ubyte targetEchoVolumeLeft; ///
	ubyte targetEchoVolumeRight; ///
	bool echoWrites; ///
	ubyte echoRemaining = 1; ///
	ubyte echoVolumeLeft; ///
	ubyte echoVolumeRight; ///
	ubyte echoDelay; ///
	ubyte echoFeedbackVolume; ///
	ushort echoBufferIndex; ///
	ubyte firBufferIndex; ///
	short[15000] echoBuffer; ///
	ubyte[8] firCoefficients; ///
	short[8] firLeft; ///
	short[8] firRight; ///
	//amk state
	bool amkFixSampleLoadTuning; ///
	bool useAltRTable; ///
}

///
private struct Slider {
	ushort current; ///
	ushort delta; ///
	ubyte cycles; ///
	ubyte target; ///

	///
	private void slide() nothrow @safe pure {
		if (cycles) {
			if (--cycles == 0) {
				current = target << 8;
			} else {
				current += delta;
			}
		}
	}
}

///
enum ADSRPhase {
	attack, ///
	decay, ///
	sustain, ///
	gain, ///
	release, ///
}

///
enum SeekStyle {
	absolute, ///
	relative, ///
}

///
private struct ChannelState {
	bool enabled = true; ///
	int next; /// time left in note

	Slider note; ///
	ubyte currentPortStartCounter; ///
	ubyte noteLength; ///
	ubyte noteStyle; ///

	ubyte noteRelease; /// time to release note, in cycles

	Parser parser; ///

	ubyte instrument; /// instrument
	ADSRGain instrumentADSRGain; ///
	ubyte finetune; ///
	byte transpose; ///
	Slider panning = Slider(0x0A00); ///
	ubyte panFlags; ///
	Slider volume = Slider(0xFF00); ///
	ubyte totalVolume; ///
	byte leftVolume; ///
	byte rightVolume; ///

	ubyte portType; ///
	ubyte portStart; ///
	ubyte portLength; ///
	ubyte portRange; ///
	ubyte vibratoStart; ///
	ubyte vibratoSpeed; ///
	ubyte vibratoMaxRange; ///
	ubyte vibratoFadeIn; ///
	ubyte tremoloStart; ///
	ubyte tremoloSpeed; ///
	ubyte tremoloRange; ///

	ubyte vibratoPhase; ///
	ubyte vibratoStartCounter; ///
	ubyte currentVibratoRange; ///
	ubyte vibratoFadeInCounter; ///
	ubyte vibratoRangeDelta; ///
	ubyte tremoloPhase; ///
	ubyte tremoloStartCounter; ///

	ubyte sampleID; ///
	int samplePosition = -1; ///
	int noteFrequency; ///

	short gain; ///
	ADSRPhase adsrPhase; ///
	ushort adsrCounter; ///
	ubyte adsrRate; ///

	short[8] interpolationBuffer; ///
	short lastSample; ///

	bool echoEnabled; ///

	// Konami-specific state
	ushort loopStart; ///
	ushort loopCount; ///
	ubyte noteDelta; /// TODO: implement this. what unit does this use?
	ubyte volumeDelta; /// ditto
	ushort tuning; ///
	// AMK specific state
	ushort semitoneTune; ///
	ubyte volumeBoost; ///
	ushort[ubyte] remotes; ///
	// Pseudo VCMD state
	Nullable!ubyte releaseOverride; ///
	Nullable!Parser remoteParser; ///
	///
	void setADSRPhase(ADSRPhase phase) @safe pure nothrow {
		adsrCounter = 0;
		adsrPhase = phase;
		final switch (phase) {
			case ADSRPhase.attack:
				adsrRate = cast(ubyte)(instrumentADSRGain.attackRate * 2 + 1);
				break;
			case ADSRPhase.decay:
				adsrRate = cast(ubyte)(instrumentADSRGain.decayRate * 2 + 16);
				break;
			case ADSRPhase.sustain:
				adsrRate = instrumentADSRGain.sustainRate;
				break;
			case ADSRPhase.gain:
				if (instrumentADSRGain.mode == ADSRGainMode.customGain) {
					adsrRate = instrumentADSRGain.gainRate;
				}
				assert(instrumentADSRGain.mode != ADSRGainMode.adsr);
				break;
			case ADSRPhase.release:
				adsrRate = 31;
				break;
		}
	}
	void setNewTrack(ushort track, const(Track[ushort])* tracks) nothrow pure @safe {
		this.parser = Parser.initialize(assumeWontThrow((*tracks).get(track, Track.init)), tracks);
		this.volume.cycles = 0;
		this.panning.cycles = 0;
		this.next = 0;
		this.enabled = true;
	}
	///
	this(ushort track, const(Track[ushort])* tracks) nothrow pure @safe {
		this.enabled = false;
		setNewTrack(track, tracks);
	}
	void clearTrack() @safe pure nothrow {
		parser.sequenceData = Track.init;
	}
	private ref auto currentParser() inout => remoteParser.isNull ? parser : remoteParser.get();
	bool empty() const @safe pure nothrow => currentParser.empty;
	bool done() const @safe pure nothrow => currentParser.done;
	auto front() const @safe pure nothrow => currentParser.front;
	void popFront() @safe pure nothrow => currentParser.popFront;
	auto ref followSubroutines() inout => currentParser.followSubroutines;
}

///
private struct Parser {
	Track sequenceData; ///
	Track subroutineReturnData; /// the sequence data that will be restored upon return from subroutine
	ushort subroutineStartAddress; /// Starting address of the subroutine
	ubyte subroutineCount; /// Number of times to repeat the subroutine
	const(Command)[] loopStart; /// Sequence data at  the start of a loop
	bool followSubroutines = true; /// Whether or not to follow subroutines when looking for the next note
	/// Number of times to loop
	ubyte loopCount = 0xFF; ///
	const(Track[ushort])* tracks;
	bool done;
	static Parser initialize(Track track, const(Track[ushort])* tracks) @safe pure nothrow {
		Parser initialized;
		initialized.subroutineCount = 0;
		initialized.sequenceData = track;
		initialized.tracks = tracks;
		return initialized;
	}
	///
	bool empty() const @safe pure nothrow => sequenceData.data.length == 0;
	Command front() const @safe pure nothrow => sequenceData.data[0];
	Command popCommand() nothrow @safe pure {
		scope(exit) popFront();
		return front;
	}
	///
	void popFront() nothrow @safe pure {
		done = false;
		const command = front;
		if (command.type == VCMDClass.terminator) {
			done = subroutineCount == 0;
			if (!done) {
				sequenceData = --subroutineCount ? (*tracks)[subroutineStartAddress] : subroutineReturnData;
			} else {
				sequenceData = Track.init;
			}
		} else if ((command.type == VCMDClass.special) && (command.special == VCMD.konamiLoopStart)) {
			sequenceData.data = sequenceData.data[1 .. $];
			loopStart = sequenceData.data[];
		} else if ((command.type == VCMDClass.special) && (command.special == VCMD.amkSubloop)) {
			if (command.parameters[0] == 0) {
				sequenceData.data = sequenceData.data[1 .. $];
				loopStart = sequenceData.data[];
			} else {
				if (loopCount == 0xFF) {
					loopCount = cast(ubyte)(command.parameters[0]);
				}
				if (loopCount > 0) {
					sequenceData.data = loopStart;
					loopCount--;
				} else {
					loopCount = 0xFF;
					sequenceData.data = sequenceData.data[1 .. $];
				}
			}
		} else if ((command.type == VCMDClass.special) && (command.special == VCMD.konamiLoopEnd)) {
			if (loopCount == 0xFF) {
				loopCount = cast(ubyte)(command.parameters[0] - 1);
			}
			if (loopCount > 0) {
				sequenceData.data = loopStart;
				loopCount--;
			} else {
				loopCount = 0xFF;
				sequenceData.data = sequenceData.data[1 .. $];
			}
		} else if (followSubroutines && (command.type == VCMDClass.special) && (command.special == VCMD.subRoutine)) {
			subroutineReturnData.data = sequenceData.data[1 .. $];
			subroutineStartAddress = read!ushort(command.parameters);
			subroutineCount = command.parameters[2];
			sequenceData = (*tracks)[subroutineStartAddress];
		} else {
			sequenceData.data = sequenceData.data[1 .. $];
		}
	}
}

@safe pure unittest {
	{
		Parser parser;
		assert(parser.empty);
	}
	{
		auto parser = Parser(
			sequenceData: decompileTrack([0x00], Variant.standard)
		);
		assert(parser.front.type == VCMDClass.terminator);
		parser.popFront();
		assert(parser.empty);
	}
	{
		auto parser = Parser(
			sequenceData: decompileTrack([0x80, 0x81, 0x00], Variant.standard)
		);
		assert(parser.front.type == VCMDClass.note);
		parser.popFront();
		assert(parser.front.type == VCMDClass.note);
		parser.popFront();
		assert(parser.front.type == VCMDClass.terminator);
		parser.popFront();
		assert(parser.empty);
	}
}

/// Rates (in samples) until next step is applied
private immutable adsrGainRates = [ 0, 2048, 1536, 1280, 1024, 768, 640, 512, 384, 320, 256, 192, 160, 128, 96, 80, 64, 48, 40, 32, 24, 20, 16, 12, 10, 8, 6, 5, 4, 3, 2, 1 ];

///
void doADSR(ref ChannelState channel) nothrow @safe pure {
	ushort level() {
		return cast(ushort)(((channel.gain - 1) >> 8) + 1);
	}
	final switch (channel.adsrPhase) {
		case ADSRPhase.attack:
			channel.gain += (channel.adsrRate == 31) ? 1024 : 32;
			if (channel.gain > 0x7E0) {
				channel.setADSRPhase(ADSRPhase.decay);
			}
			break;
		case ADSRPhase.decay:
			channel.gain -= level;
			if (channel.gain < channel.instrumentADSRGain.sustainLevel) {
				channel.setADSRPhase(ADSRPhase.sustain);
			}
			break;
		case ADSRPhase.sustain:
			channel.gain -= level;
			break;
		case ADSRPhase.gain:
			final switch(channel.instrumentADSRGain.gainMode) {
				case GainMode.linearDecreaseGain:
					channel.gain -= 32;
					break;
				case GainMode.expDecreaseGain:
					channel.gain -= level;
					break;
				case GainMode.linearIncreaseGain:
					channel.gain += 32;
					break;
				case GainMode.bentIncreaseGain:
					channel.gain +=  (channel.gain < 0x600) ? 32 : 8;
					break;
			}
			break;
		case ADSRPhase.release:
			channel.gain -= 8;
			if (channel.gain < 0) {
				channel.samplePosition = -1;
			}
			break;
	}
	channel.gain = clamp(channel.gain, cast(short)0, cast(short)0x7FF);
}

///
void doEcho(ref SongState state, ref short leftSample, ref short rightSample, int mixrate) nothrow pure @safe {
	const echoAddress = state.echoBufferIndex * 2;

	state.firLeft[state.firBufferIndex] = state.echoBuffer[echoAddress % state.echoBuffer.length] >> 1;

	state.firRight[state.firBufferIndex] = state.echoBuffer[(echoAddress + 1) % state.echoBuffer.length] >> 1;
	int sumLeft = 0;
	int sumRight = 0;
	for(int i = 0; i < 8; i++) {
		sumLeft += (state.firLeft[(state.firBufferIndex + i + 1) & 0x7] * state.firCoefficients[i]) >> 6;
		sumRight += (state.firRight[(state.firBufferIndex + i + 1) & 0x7] * state.firCoefficients[i]) >> 6;
	}
	sumLeft = clamp(sumLeft, short.min, short.max);
	sumRight = clamp(sumRight, short.min, short.max);

	leftSample = cast(short)clamp(leftSample + ((sumLeft * state.echoVolumeLeft) / 128.0), short.min, short.max);
	rightSample = cast(short)clamp(rightSample + ((sumRight * state.echoVolumeRight) / 128.0), short.min, short.max);

	int inLeft = 0;
	int inRight = 0;
	foreach(channel; state.channels) {
		if(channel.echoEnabled) {
			inLeft += cast(short)((channel.lastSample * channel.leftVolume) / 128.0);
			inRight += cast(short)((channel.lastSample * channel.rightVolume) / 128.0);
			inLeft = clamp(inLeft, short.min, short.max);
			inRight = clamp(inRight, short.min, short.max);
		}
	}
	inLeft += cast(int)((sumLeft * state.echoFeedbackVolume) / 128.0);
	inRight += cast(int)((sumRight * state.echoFeedbackVolume) / 128.0);
	inLeft = clamp(inLeft * nativeSamplingRate / mixrate, short.min, short.max);
	inRight = clamp(inRight * nativeSamplingRate / mixrate, short.min, short.max);
	inLeft &= 0xfffe;
	inRight &= 0xfffe;
	if(state.echoWrites) {
		state.echoBuffer[echoAddress] = cast(short)inLeft;
		state.echoBuffer[echoAddress + 1] = cast(short)inRight;
	}

	state.firBufferIndex = (state.firBufferIndex + 1) & 7;
	state.echoBufferIndex++;
	if(--state.echoRemaining == 0) {
		state.echoRemaining = state.echoDelay;
		state.echoBufferIndex = 0;
	}
}

version(purePlayer) {
	alias Callback = void function(scope NSPCPlayer*) @safe pure nothrow; ///
} else {
	alias Callback = void function(scope NSPCPlayer*) @safe nothrow; ///
}

///
struct NSPCPlayer {
	enum defaultSpeed = 500; ///
	private size_t songIndex;
	ref currentSong() inout => loadedSongs[songIndex];
	const(Song)[] loadedSongs; ///
	SongState state; ///
	private SongState backupState; ///
	private int _mixrate = nativeSamplingRate; ///
	private int timerSpeed = defaultSpeed; ///
	private bool songPlaying; ///

	private bool loopEnabled = true; ///

	Interpolation interpolation = Interpolation.gaussian; ///

	size_t onTimerTicksLeft; ///
	bool repeatTimer; ///
	Callback onTimerTick; ///
	Callback onPhraseChange; ///
	///
	short[2][] fillBuffer()(scope short[2][] buffer) {
		enum left = 0;
		enum right = 1;
		if (!songPlaying) {
			buffer[] = [0, 0];
			return buffer;
		}
		size_t length;
		foreach (ref sample; buffer) {
			sample[] = 0;
			if ((state.nextTimerTick -= timerSpeed) < 0) {
				state.nextTimerTick += mixrate;
				if (!doTimer()) {
					break;
				}
			}
			length++;
			double[2] tempSample = 0.0;
			foreach (i, ref channel; state.channels) {
				if (channel.sampleID >= 128) {
					continue; //NYI
				}
				const loadedSample = currentSong.samples[channel.sampleID];
				if (!channel.enabled) {
					continue;
				}

				if (channel.samplePosition < 0) {
					continue;
				}

				foreach (idx, ref interpolationSample; channel.interpolationBuffer) {
					size_t offset = (channel.samplePosition >> 15) + idx;
					while (loadedSample.loopLength && (offset >= loadedSample.data.length)) {
						offset -= loadedSample.loopLength;
					}
					if (offset < loadedSample.data.length) {
						interpolationSample = loadedSample.data[offset];
					} else if (loadedSample.data && (idx > 0)) {
						interpolationSample = channel.interpolationBuffer[idx - 1];
					} else { //no sample data?
					}
				}
				channel.lastSample = interpolate(interpolation, channel.interpolationBuffer[], channel.samplePosition >> 3);

				if (channel.adsrRate && (++channel.adsrCounter >= cast(int)(adsrGainRates[channel.adsrRate] * (mixrate / cast(double)nativeSamplingRate)))) {
					doADSR(channel);
					channel.adsrCounter = 0;
				}
				if (channel.gain == 0) {
					continue;
				}
				int s1 = (channel.lastSample * channel.gain) >> 11;

				tempSample[left] += s1 * channel.leftVolume / 128.0;
				tempSample[right] += s1 * channel.rightVolume / 128.0;

				channel.samplePosition += channel.noteFrequency;
				if ((channel.samplePosition >> 15) >= loadedSample.data.length) {
					if (loadedSample.loopLength) {
						channel.samplePosition -= loadedSample.loopLength << 15;
					} else {
						channel.samplePosition = -1;
						channel.adsrPhase = ADSRPhase.release;
					}
				}
			}
			sample[left] = cast(short)(clamp(tempSample[left] * currentSong.masterVolumeL / 128.0, short.min, short.max));
			sample[right] = cast(short)(clamp(tempSample[right] * currentSong.masterVolumeR / 128.0, short.min, short.max));
			doEcho(state, sample[0] , sample[1] , mixrate);
		}
		return buffer[0 .. length];
	}

	///
	private void calcTotalVolume(ref ChannelState c, byte tremoloPhase) nothrow @safe pure {
		ubyte v = (tremoloPhase << 1 ^ tremoloPhase >> 7) & 0xFF;
		v = ~(v * c.tremoloRange >> 8) & 0xFF;

		v = v * (state.volume.current >> 8) >> 8;
		v = v * currentSong.volumeTable[c.noteStyle & 15] >> 8;
		v = v * (c.volume.current >> 8) >> 8;
		c.totalVolume = v * v >> 8;
	}

	///
	private int calcVolume3(const ChannelState c, int pan, int flag) nothrow pure @safe {
		static immutable ubyte[] panTable = [0x00, 0x01, 0x03, 0x07, 0x0D, 0x15, 0x1E, 0x29, 0x34, 0x42, 0x51, 0x5E, 0x67, 0x6E, 0x73, 0x77, 0x7A, 0x7C, 0x7D, 0x7E, 0x7F, 0x7F];
		const ubyte[] ph = panTable[pan >> 8 .. (pan >> 8) + 2];
		int v = ph[0] + ((ph[1] - ph[0]) * (pan & 255) >> 8);
		v = v * c.totalVolume >> 8;
		v += v * c.volumeBoost >> 8;
		if (c.panFlags & flag) {
			v = -v;
		}
		return v;
	}

	///
	private void calcVolume2(ref ChannelState c, int pan) nothrow pure @safe {
		c.leftVolume = cast(byte) calcVolume3(c, pan, 0x80);
		c.rightVolume = cast(byte) calcVolume3(c, 0x1400 - pan, 0x40);
	}

	///
	private void makeSlider(ref Slider s, int cycles, int target) nothrow pure @safe {
		if (cycles) {
			s.delta = cast(ushort)(((target << 8) - (s.current & 0xFF00)) / cycles);
			s.cycles = cast(ubyte) cycles;
			s.target = cast(ubyte) target;
		}
	}

	///
	private void setInstrument(ref ChannelState c, size_t instrument) nothrow pure @safe {
		const idata = currentSong.instruments[instrument];
		c.instrument = cast(ubyte)instrument;
		c.sampleID = currentSong.instruments[instrument].sampleID;
		setADSRGain(c, idata.adsrGain);
		c.tuning = idata.tuning;
	}
	///
	private void setADSRGain(ref ChannelState c, const ADSRGain adsrGain) nothrow pure @safe {
		c.instrumentADSRGain = adsrGain;
		if (adsrGain.mode == ADSRGainMode.directGain) {
			c.gain = adsrGain.fixedVolume;
		}
	}

	/// calculate how far to advance the sample pointer on each output sample
	private void setFrequency(ref ChannelState c, int note16) const nothrow pure @safe {

		// What is this for???
		if (note16 >= 0x3400) {
			note16 += (note16 >> 8) - 0x34;
		} else if (note16 < 0x1300) {
			note16 += ((note16 >> 8) - 0x13) << 1;
		}

		if (cast(ushort) note16 >= 0x5400) {
			c.noteFrequency = 0;
			return;
		}

		int octave = (note16 >> 8) / 12;
		int tone = (note16 >> 8) % 12;
		int freq = currentSong.noteFrequencyTable[tone];
		freq += (currentSong.noteFrequencyTable[tone + 1] - freq) * (note16 & 0xFF) >> 8;
		freq <<= 1;
		freq >>= 6 - octave;


		freq *= c.tuning;
		freq >>= 8;
		freq &= 0x3fff;

		c.noteFrequency = (freq * (nativeSamplingRate << (15 - 12))) / mixrate;
	}

	///
	private int calcVibratoDisp(ref ChannelState c, int phase) nothrow pure @safe {
		int range = c.currentVibratoRange;
		if (range > 0xF0) {
			range = (range - 0xF0) * 256;
		}

		int disp = (phase << 2) & 255; /* //// */
		if (phase & 0x40) {
			disp ^= 0xFF; /* /\/\ */
		}
		disp = (disp * range) >> 8;

		if (phase & 0x80) {
			disp = -disp; /* /\   */
		}
		return disp; /*   \/ */
	}
	/// do a Ex/Fx code
	private void doCommand(ref ChannelState c, const Command command) nothrow pure @safe {
		final switch (command.special) {
			case VCMD.instrument:
				setInstrument(c, currentSong.absoluteInstrumentID(command.parameters[0], state.percussionBase, false));
				break;
			case VCMD.panning:
			case VCMD.konamiPanning: // ???
				c.panFlags = command.parameters[0];
				c.panning.current = (command.parameters[0] & 0x1F) << 8;
				break;
			case VCMD.panningFade:
			case VCMD.konamiPanningFade: // ???
				makeSlider(c.panning, command.parameters[0], command.parameters[1]);
				break;
			case VCMD.vibratoOn:
				c.vibratoStart = command.parameters[0];
				c.vibratoSpeed = command.parameters[1];
				c.currentVibratoRange = c.vibratoMaxRange = command.parameters[2];
				c.vibratoFadeIn = 0;
				break;
			case VCMD.vibratoOff:
				c.currentVibratoRange = c.vibratoMaxRange = 0;
				c.vibratoFadeIn = 0;
				break;
			case VCMD.songVolume:
				state.volume.current = command.parameters[0] << 8;
				break;
			case VCMD.songVolumeFade:
				makeSlider(state.volume, command.parameters[0], command.parameters[1]);
				break;
			case VCMD.tempo:
				state.tempo.current = command.parameters[0] << 8;
				break;
			case VCMD.tempoFade:
				makeSlider(state.tempo, command.parameters[0], command.parameters[1]);
				break;
			case VCMD.globalAbsoluteTransposition:
				state.transpose = command.parameters[0];
				break;
			case VCMD.channelAbsoluteTransposition:
				c.transpose = command.parameters[0];
				break;
			case VCMD.tremoloOn:
				c.tremoloStart = command.parameters[0];
				c.tremoloSpeed = command.parameters[1];
				c.tremoloRange = command.parameters[2];
				break;
			case VCMD.tremoloOff:
				c.tremoloRange = 0;
				break;
			case VCMD.volume:
				c.volume.current = command.parameters[0] << 8;
				break;
			case VCMD.volumeFade:
				makeSlider(c.volume, command.parameters[0], command.parameters[1]);
				break;
			case VCMD.subRoutine:
				/// This is handled by the parser
				break;
			case VCMD.vibratoFadeIn:
				c.vibratoFadeIn = command.parameters[0];
				c.vibratoRangeDelta = c.currentVibratoRange / command.parameters[0];
				break;
			case VCMD.notePitchEnvelopeTo:
			case VCMD.notePitchEnvelopeFrom:
				c.portType = (command.special == VCMD.notePitchEnvelopeTo);
				c.portStart = command.parameters[0];
				c.portLength = command.parameters[1];
				c.portRange = command.parameters[2];
				break;
			case VCMD.notePitchEnvelopeOff:
				c.portLength = 0;
				break;
			case VCMD.fineTune:
				c.finetune = command.parameters[0];
				break;
			case VCMD.echoEnableBitsAndVolume:
				foreach (idx, ref channel; state.channels) {
					channel.echoEnabled = !!(command.parameters[0] & (1 << idx));
				}
				state.echoVolumeLeft = command.parameters[1];
				state.echoVolumeRight = command.parameters[2];
				break;
			case VCMD.echoOff:
				foreach (ref channel; state.channels) {
					channel.echoEnabled = false;
				}
				break;
			case VCMD.echoParameterSetup:
				state.echoDelay = command.parameters[0];
				state.echoFeedbackVolume = command.parameters[1];
				state.firCoefficients = currentSong.firCoefficients[command.parameters[2]];
				break;
			case VCMD.echoVolumeFade:
				state.fadeTicks = command.parameters[0];
				state.targetEchoVolumeLeft = command.parameters[1];
				state.targetEchoVolumeRight = command.parameters[2];
				break;
			case VCMD.noop0: //do nothing
			case VCMD.noop1: //do nothing
			case VCMD.noop2: //do nothing
				break;
			case VCMD.konamiLoopStart: // handled by parser
			case VCMD.konamiLoopEnd:
			case VCMD.amkSubloop:
				break;
			case VCMD.pitchSlideToNote:
				c.currentPortStartCounter = command.parameters[0];
				int target = command.parameters[2] + state.transpose;
				if (target >= 0x100) {
					target -= 0xFF;
				}
				target += c.transpose;
				makeSlider(c.note, command.parameters[1], target & 0x7F);
				break;
			case VCMD.percussionBaseInstrumentRedefine:
				state.percussionBase = command.parameters[0];
				break;
			case VCMD.konamiADSRGain:
				setADSRGain(c, konamiADSRGain(command.parameters));
				break;
			case VCMD.amkSetADSRGain:
				setADSRGain(c, amkADSRGain(command.parameters));
				break;
			case VCMD.amkSetFIR:
				state.firCoefficients = command.parameters;
				break;
			case VCMD.amkSampleLoad:
				c.sampleID = command.parameters[0];
				ubyte finetune = state.amkFixSampleLoadTuning ? 0 : cast(ubyte)currentSong.instruments[c.instrument].tuning;
				c.tuning = (cast(ushort)command.parameters[1] << 8) | finetune;
				break;
			case VCMD.amkF4:
				if (command.parameters[0] == 3) {
					c.echoEnabled = !c.echoEnabled;
					break;
				}
				if (command.parameters[0] == 9) {
					setInstrument(c, c.instrument);
					break;
				}
				debug(nspclogging) warningf("Unhandled command: %x", command);
				break;
			case VCMD.amkFA:
				if (command.parameters[0] == 1) {
					auto newGain = c.instrumentADSRGain;
					newGain.gain = command.parameters[1];
					newGain.adsr &= ~0x80;
					setADSRGain(c, newGain);
					break;
				}
				if (command.parameters[0] == 2) {
					c.semitoneTune = command.parameters[1];
					break;
				}
				if (command.parameters[0] == 3) {
					c.volumeBoost = command.parameters[1];
					break;
				}
				if (command.parameters[0] == 4) {
					// reserves echo buffer, which we don't need to do
					break;
				}
				if (command.parameters[0] == 6) {
					state.useAltRTable = !!command.parameters[1];
					break;
				}
				debug(nspclogging) warningf("Unhandled command: %x", command);
				break;
			case VCMD.amkRemoteCommand:
				if (command.parameters[2] == 0) {
					c.remotes = null;
				} else {
					c.remotes[command.parameters[2]] = read!ushort(command.parameters[]);
				}
				break;
			case VCMD.setRelease:
				c.releaseOverride = command.parameters[0];
				break;
			case VCMD.deleteTrack:
				c.clearTrack();
				break;
			case VCMD.konamiE4: // ???
			case VCMD.konamiE7: // ???
			case VCMD.konamiF5: // ???
			case VCMD.channelMute:
			case VCMD.fastForwardOn:
			case VCMD.fastForwardOff:
			case VCMD.amkWriteDSP:
			case VCMD.amkEnableNoise:
			case VCMD.amkSendData:
			case VCMD.amkFB:
				debug(nspclogging) warningf("Unhandled command: %x", command);
				break;
			case VCMD.invalid: //do nothing
				assert(0, "Invalid command");
		}
	}

	// $0654 + $08D4-$8EF
	///
	private void doNote(ref ChannelState c, const Command command) nothrow pure @safe {
		ubyte note = command.note;
		executeRemote(255, c);
		// using >=CA as a note switches to that instrument and plays a predefined note
		if (command.type == VCMDClass.percussion) {
			setInstrument(c, currentSong.absoluteInstrumentID(note, state.percussionBase, true));
			note = cast(ubyte)(currentSong.percussionNotes[note]);
		}
		if (command.type.among(VCMDClass.percussion, VCMDClass.note)) {
			c.vibratoPhase = c.vibratoFadeIn & 1 ? 0x80 : 0;
			c.vibratoStartCounter = 0;
			c.vibratoFadeInCounter = 0;
			c.tremoloPhase = 0;
			c.tremoloStartCounter = 0;

			c.samplePosition = 0;
			//c.sampleID = currentSong.instruments[c.instrument].sampleID;
			c.gain = 0;
			c.setADSRPhase((currentSong.instruments[c.instrument].adsrGain.mode == ADSRGainMode.adsr) ? ADSRPhase.attack : ADSRPhase.gain);

			note += state.transpose + c.transpose + c.semitoneTune;
			c.note.current = cast(ushort)(note << 8 | c.finetune);

			c.note.cycles = c.portLength;
			if (c.note.cycles) {
				int target = note;
				c.currentPortStartCounter = c.portStart;
				if (c.portType == 0) {
					c.note.current -= c.portRange << 8;
				} else {
					target += c.portRange;
				}
				makeSlider(c.note, c.portLength, target & 0x7F);
			}

			setFrequency(c, c.note.current);
		}

		// Search forward for the next note (to see if it's C8). This is annoying
		// but necessary - C8 can continue the last note of a subroutine as well
		// as a normal note.
		VCMDClass nextNote;
		{
			auto channelCopy = c;
			while (!channelCopy.done && !channelCopy.empty) {
				const tmpCommand = channelCopy.front();
				channelCopy.popFront();
				if (tmpCommand.type.among(VCMDClass.note, VCMDClass.tie, VCMDClass.rest, VCMDClass.percussion)) {
					nextNote = tmpCommand.type;
					break;
				}
			}
		}

		int rel;
		if (nextNote == VCMDClass.tie) {
			// if the note will be continued, don't release yet
			rel = c.noteLength;
		} else {
			const releaseTable = state.useAltRTable ? currentSong.altReleaseTable : currentSong.releaseTable;
			rel = (c.noteLength * c.releaseOverride.get(releaseTable[c.noteStyle >> 4])) >> 8;
			if (rel > c.noteLength - 2) {
				rel = c.noteLength - 2;
			}
			if (rel < 1) {
				rel = 1;
			}
		}
		c.noteRelease = cast(ubyte) rel;
	}

	///
	private void loadPattern()() {
		state.phraseCounter = cast(uint)((state.phraseCounter + 1) % currentSong.order.length);
		const nextPhrase = currentSong.order[state.phraseCounter];
		debug(nspclogging) tracef("Next phrase: %s", nextPhrase);
		final switch (nextPhrase.type) {
			case PhraseType.end:
				state.phraseCounter--;
				songPlaying = false;
				return;
			case PhraseType.jumpLimited:
				if (--state.repeatCount >= 0x80) {
					state.repeatCount = cast(ubyte)nextPhrase.jumpTimes;
				}
				if (state.repeatCount > 0) {
					state.phraseCounter = nextPhrase.id - 1;
				}
				debug(nspclogging) tracef("%s more repeats", state.repeatCount);
				loadPattern();
				break;
			case PhraseType.jump:
				if (loopEnabled) {
					state.phraseCounter = nextPhrase.id - 1;
					loadPattern();
				} else {
					state.phraseCounter--;
					songPlaying = false;
				}
				break;
			case PhraseType.fastForwardOn:
				assert(0, "Not yet implemented");
			case PhraseType.fastForwardOff:
				assert(0, "Not yet implemented");
			case PhraseType.pattern:
				const trackList = currentSong.trackLists[nextPhrase.id];
				state.channels.length = max(state.channels.length, trackList.length);
				backupState.channels.length = state.channels.length;
				foreach (idx, ref channel; state.channels) {
					channel.setNewTrack(trackList[idx], &currentSong.tracks);
				}
				break;
		}
		if (onPhraseChange !is null) {
			onPhraseChange(&this);
		}
	}

	///
	private void doKeySweepVibratoChecks(ref ChannelState c) nothrow pure @safe {
		// key off
		if (c.noteRelease) {
			c.noteRelease--;
		}
		if (!c.noteRelease) {
			c.setADSRPhase(ADSRPhase.release);
			executeRemote(3, c);
		}

		// sweep
		if (c.note.cycles) {
			if (c.currentPortStartCounter == 0) {
				c.note.slide();
				setFrequency(c, c.note.current);
			} else {
				c.currentPortStartCounter--;
			}
		}

		// vibrato
		if (c.currentVibratoRange) {
			if (c.vibratoStartCounter == c.vibratoStart) {
				int range;
				if (c.vibratoFadeInCounter == c.vibratoFadeIn) {
					range = c.vibratoMaxRange;
				} else {
					range = c.currentVibratoRange;
					if (c.vibratoFadeInCounter == 0) {
						range = 0;
					}
					range += c.vibratoRangeDelta;
					c.vibratoFadeInCounter++;
				} // DA0
				c.currentVibratoRange = cast(ubyte) range;
				c.vibratoPhase += c.vibratoSpeed;
				setFrequency(c, c.note.current + calcVibratoDisp(c, c.vibratoPhase));
			} else {
				c.vibratoStartCounter++;
			}
		}
	}
	///
	private void executeRemote(ubyte event, ref ChannelState channel) nothrow pure @safe {
		assert(channel.remoteParser.isNull);
		if (auto seq = event in channel.remotes) {
			channel.remoteParser = Parser.initialize(currentSong.tracks[*seq], &currentSong.tracks);
			execute(channel);
			channel.remoteParser.nullify();
		}
	}
	/**
	 * Executes vcmds until either a terminator or a note is reached
	 * Returns: false if no commands left for channel, true otherwise
	 */
	private bool execute(ref ChannelState channel) nothrow pure @safe {
		while (!channel.empty) {
			const command = channel.currentParser.popCommand();
			if (executeCommand(channel, command, channel.currentParser.done)) {
				return channel.currentParser.done;
			}
		}
		return true;
	}
	///
	private bool executeCommand(ref ChannelState channel, const Command command, ref bool noteFound) nothrow pure @safe {
		final switch (command.type) {
			case VCMDClass.terminator:
				if (noteFound) {
					noteFound = false;
					return true;
				}
				break;
			case VCMDClass.noteDuration:
				channel.noteLength = command.noteDuration;
				if (command.parameters.length > 0) {
					channel.noteStyle = command.parameters[0];
				}
				break;
			case VCMDClass.note:
			case VCMDClass.tie:
			case VCMDClass.rest:
			case VCMDClass.percussion:
				channel.next = channel.noteLength - 1;
				doNote(channel, command);
				noteFound = true;
				return true;
			case VCMDClass.special:
				doCommand(channel, command);
				break;
		}
		return false;
	}
	///
	public void executeCommand(ubyte channel, const Command command) nothrow pure @safe {
		bool _;
		executeCommand(state.channels[channel], command, _);
	}

	// $07F9 + $0625
	/**
	 * Returns: false if a channel end has been reached, true otherwise
	 */
	private bool doCycle() nothrow pure @safe {
		foreach (ref channel; state.channels) {
			if (--channel.next >= 0) {
				doKeySweepVibratoChecks(channel);
			} else {
				if (!execute(channel)) {
					return false;
				}
			}
			// $0B84
			if (channel.note.cycles == 0) {
				size_t length;
				if (!channel.empty) {
					const command = channel.front;
					if (command.special == VCMD.pitchSlideToNote) {
						doCommand(channel, command);
						channel.popFront();
					}
				}
			}
		}

		state.tempo.slide();
		state.volume.slide();

		foreach (ref channel; state.channels) {
			if (channel.empty) {
				continue;
			}

			// @ 0C40
			channel.volume.slide();

			// @ 0C4D
			int tphase = 0;
			if (channel.tremoloRange) {
				if (channel.tremoloStartCounter == channel.tremoloStart) {
					if (channel.tremoloPhase >= 0x80 && channel.tremoloRange == 0xFF) {
						channel.tremoloPhase = 0x80;
					} else {
						channel.tremoloPhase += channel.tremoloSpeed;
					}
					tphase = channel.tremoloPhase;
				} else {
					channel.tremoloStartCounter++;
				}
			}
			calcTotalVolume(channel, cast(byte) tphase);

			// 0C79
			channel.panning.slide();

			// 0C86: volume stuff
			calcVolume2(channel, channel.panning.current);
		}
		return true;
	}

	///
	private int subCycleCalc(int delta) nothrow pure @safe {
		if (delta < 0x8000) {
			return state.cycleTimer * delta >> 8;
		} else {
			return -(state.cycleTimer * (0x10000 - delta) >> 8);
		}
	}

	///
	private void doSubCycle() nothrow pure @safe {
		foreach (ref channel; state.channels) {
			if (channel.empty) {
				continue;
			}
			// $0DD0

			bool changed = false;
			if (channel.tremoloRange && channel.tremoloStartCounter == channel.tremoloStart) {
				int p = channel.tremoloPhase + subCycleCalc(channel.tremoloSpeed);
				changed = true;
				calcTotalVolume(channel, cast(byte) p);
			}
			int pan = channel.panning.current;
			if (channel.panning.cycles) {
				pan += subCycleCalc(channel.panning.delta);
				changed = true;
			}
			if (changed) {
				calcVolume2(channel, pan);
			}

			changed = false;
			int note = channel.note.current; // $0BBC
			if (channel.note.cycles && channel.currentPortStartCounter == 0) {
				note += subCycleCalc(channel.note.delta);
				changed = true;
			}
			if (channel.currentVibratoRange && channel.vibratoStartCounter == channel.vibratoStart) {
				int p = channel.vibratoPhase + subCycleCalc(channel.vibratoSpeed);
				note += calcVibratoDisp(channel, p);
				changed = true;
			}
			if (changed) {
				setFrequency(channel, note);
			}
		}
	}

	///
	private bool doTimer()() {
		state.cycleTimer += state.tempo.current >> 8;
		if (state.cycleTimer >= 256) {
			state.cycleTimer -= 256;
			while (!doCycle()) {
				loadPattern();
				if (!songPlaying) {
					return false;
				}
			}
			if (repeatTimer || onTimerTicksLeft > 0) {
				onTimerTicksLeft--;
			} else {
				if (onTimerTick !is null) {
					onTimerTick(&this);
					if (!repeatTimer) {
						onTimerTick = null;
					}
				}
			}
		} else {
			doSubCycle();
		}
		return true;
	}

	/// Initialize or reset the player state
	void initialize()() {
		state = state.init;

		if (loadedSongs.length > 0) {
			state.percussionBase = cast(ubyte)currentSong.percussionBase;
			if (currentSong.order.length) {
				loadPattern();
			} else {
				songPlaying = false;
			}
			state.tempo.current = currentSong.defaultTempo << 8;
			foreach (idx, channel; state.channels) {
				// disable any channels that are disabled by default
				channel.enabled ^= !(currentSong.defaultEnabledChannels() & (1 << idx));
				channel.followSubroutines = currentSong.defaultEnchantedReadahead;
			}
		}
	}
	///
	this(int sampleRate) nothrow pure @safe {
		mixrate = sampleRate;
	}

	/// Start playing music
	void play() @safe pure nothrow {
		songPlaying = true;
	}
	///
	void stop() @safe pure nothrow {
		songPlaying = false;
	}
	///
	void seek()(size_t ticks, SeekStyle style) {
		if (style == SeekStyle.absolute) {
			initialize();
		}
		while (ticks-- > 0) {
			doTimer();
		}
	}
	///
	void loadSong()(const Song song) {
		loadSongs([song]);
	}
	///
	void loadSongs()(const(Song)[] songs, size_t initial = 0) {
		if (songPlaying) {
			stop();
		}
		loadedSongs = songs;
		changeTrack(initial);
	}
	public void changeTrack()(size_t track) {
		if (songPlaying) {
			stop();
		}
		songIndex = track;
		initialize();
	}
	/// Sets the playback speed. Default value is NSPCPlayer.defaultSpeed.
	public void setSpeed(ushort rate) @safe nothrow pure {
		timerSpeed = rate;
	}
	/// Enable or disable song looping
	public void looping(bool enabled) @safe nothrow pure {
		loopEnabled = enabled;
	}
	/// Enable or disable a song channel
	public void setChannelEnabled(ubyte channel, bool enabled) @safe nothrow pure {
		state.channels[channel].enabled = enabled;
	}
	///
	bool isPlaying() const pure @safe nothrow {
		return songPlaying;
	}
	///
	public ref inout(int) mixrate() inout nothrow pure @safe return {
		return _mixrate;
	}
	///
	public void fade(ubyte ticks, ubyte targetVolume) @safe nothrow pure {
		backupState.volume = state.volume;
		makeSlider(state.volume, ticks, targetVolume);
	}
	///
	public void tempo(ubyte tempo) @safe nothrow pure {
		backupState.tempo = state.tempo;
		state.tempo.current = cast(ushort)(tempo << 8);
	}
	///
	public void restoreTempo() @safe nothrow pure {
		state.tempo = backupState.tempo;
	}
	///
	public ubyte tempo() @safe nothrow pure {
		return state.tempo.current >> 8;
	}
	///
	public void volume(ubyte volume) @safe nothrow pure {
		backupState.volume = state.volume;
		state.volume.current = cast(ushort)(volume << 8);
	}
	///
	public void restoreVolume() @safe nothrow pure {
		state.volume = backupState.volume;
	}
	///
	public ubyte volume() @safe nothrow pure {
		return state.volume.current >> 8;
	}
	///
	public void setChannelVolume(ubyte channel, ubyte volume) @safe nothrow pure {
		if (channel < state.channels.length) {
			backupState.channels[channel].volume = state.channels[channel].volume;
			state.channels[channel].volume.current = cast(ushort)(volume << 8);
		}
	}
	///
	public void restoreChannelVolume(ubyte channel) @safe nothrow pure {
		if (channel < state.channels.length) {
			state.channels[channel].volume = backupState.channels[channel].volume;
		}
	}
	///
	public ubyte getChannelVolume(ubyte channel) @safe nothrow pure {
		if (channel < state.channels.length) {
			return state.channels[channel].volume.current >> 8;
		}
		return 0;
	}
	///
	public void transpose(ubyte transpose) @safe nothrow pure {
		backupState.transpose = state.transpose;
		state.transpose = transpose;
	}
	///
	public void restoreTranspose() @safe nothrow pure {
		state.transpose = backupState.transpose;
	}
	///
	public void addTimer(size_t ticks, typeof(onTimerTick) func) @safe nothrow pure {
		onTimerTicksLeft = ticks;
		onTimerTick = func;
	}
	///
	public void addTimer(typeof(onTimerTick) func) @safe nothrow pure {
		onTimerTicksLeft = 0;
		repeatTimer = true;
		onTimerTick = func;
	}
	///
	auto phraseCounter() const @safe pure nothrow {
		return state.phraseCounter;
	}
	///
	void stopChannel(size_t channel) @safe pure nothrow {
		state.channels[channel].noteRelease = 0;
	}
	///
	bool isChannelPlaying(size_t channel) @safe pure nothrow {
		return state.channels[channel].samplePosition != -1;
	}
}

version(purePlayer) {
	@safe pure unittest {
		NSPCPlayer p;
		scope buf = new short[2][](20);
		p.fillBuffer(buf);
	}
}

///
private bool inRange(T)(T val, T lower, T upper) {
	return ((val >= lower) && (val <= upper));
}
