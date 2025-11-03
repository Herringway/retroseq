///
module retroseq.m4a.internal;

import retroseq.interpolation;
import retroseq.utility;

import retroseq.m4a.m4a;

import std.bitmanip;
import std.typecons;

alias RelativePointer(Element, Offset) = retroseq.utility.RelativePointer!(Element, Offset, 0x8000000, 0xA000000);

enum C_V = 0x40; /// center value for PAN, BEND, and TUNE

struct SoundMode {
	mixin(bitfields!(
		ubyte, "reverbVolume", 7,
		bool, "reverbEnabled", 1,
		ubyte, "maxChannels", 4,
		ubyte, "masterVolume", 4,
		ubyte, "frequency", 4,
		ubyte, "bias", 2,
		ubyte, "", 1,
		bool, "biasEnable", 1,
		ubyte, "", 8,
	));
}


///
struct Wave {
	WaveData header; ///
	const(byte)[] sample; ///
}
///
struct WaveData {
	align(1):
	ushort type; ///
	ubyte padding; ///
	ubyte loopFlags; ///
	uint freq; ///
	uint loopStart; ///
	uint size; /// number of samples
}

enum CGBType {
	directsound,
	pulse1,
	pulse2,
	gbWave,
	noise,
}

struct ToneType {
	mixin(bitfields!(
		CGBType, "cgbType", 3,
		bool, "fix", 1,
		ubyte, "", 2,
		bool, "spl", 1,
		bool, "rhy", 1,
	));
}

///
struct ToneData {
	align(1):
	ToneType type;
	ubyte key; ///
	alias drumKey = key; ///
	ubyte length; /// sound length (compatible sound)
	ubyte panSweep; /// pan or sweep (compatible sound ch. 1)
	union {
		RelativePointer!(WaveData, uint) wav; ///
		RelativePointer!(ToneData, uint) group; ///
		RelativePointer!(byte[16], uint) cgbSample; ///
		uint squareNoiseConfig; ///
	}
	union {
		struct {
			ubyte attack; ///
			ubyte decay; ///
			ubyte sustain; ///
			ubyte release; ///
		}
		RelativePointer!(ubyte, uint) keySplitTable; ///
	}
}

enum CGB_NRx2_ENV_DIR_DEC = 0x00; ///
enum CGB_NRx2_ENV_DIR_INC = 0x08; ///

enum EnvelopeState {
	release,
	sustain,
	decay,
	attack,
}

struct SoundChannel {
	EnvelopeState envelopeState;
	bool echoEnabled;
	bool loop;
	bool stop;
	bool start;
	bool isActive() const @safe pure => start || stop || echoEnabled || (envelopeState != EnvelopeState.release);
	void clearStatusFlags() @safe pure {
		envelopeState = EnvelopeState.release;
		echoEnabled = false;
		loop = false;
		stop = false;
		start = false;
	}
	ToneType type;
	ubyte rightVolume; ///
	ubyte leftVolume; ///
	ubyte attack; ///
	ubyte decay; ///
	ubyte sustain; ///
	ubyte release; ///
	ubyte key; /// midi key as it was translated into final pitch
	ubyte envelopeVolume; ///
	ubyte envelopeVolumeRight; ///
	alias envelopeGoal = envelopeVolumeRight; ///
	ubyte envelopeVolumeLeft; ///
	alias envelopeCounter = envelopeVolumeLeft; ///
	ubyte echoVolume; ///
	ubyte echoLength; ///
	ubyte gateTime; ///
	ubyte midiKey; /// midi key as it was used in the track data
	ubyte velocity; ///
	ubyte priority; ///
	ubyte rhythmPan; ///
	uint count; ///
	ubyte sustainGoal; ///
	ubyte n4; ///
	ubyte pan; ///
	float samplePosition = 0; ///
	ubyte panMask; ///
	bool cgbVolumeChange;
	bool cgbPitchChange;
	ubyte length; ///
	ubyte sweep; ///
	uint freq; ///
	Wave wav; ///
	byte[16] gbWav; ///
	uint squareNoiseConfig; ///
	const(byte)[] currentPointer; ///
	MusicPlayerTrack* track; ///
	SoundChannel* prevChannelPointer; ///
	SoundChannel* nextChannelPointer; ///
	ushort xpi; ///
	ushort xpc; ///
}

alias MPlayFunc = void function(ref M4APlayer, ref MusicPlayerTrack) @safe pure; ///
alias PlyNoteFunc = void function(ref M4APlayer, uint, ref MusicPlayerTrack) @safe pure; ///
alias MPlayMainFunc = void function(ref M4APlayer) @safe pure; ///

///
struct SoundIO {
	ubyte NR10; ///
	ubyte NR11; ///
	ubyte NR12; ///
	static union FreqControl {
		mixin(bitfields!(
			ushort, "frequency", 11,
			ubyte, "", 3,
			bool, "lengthFlag", 1,
			bool, "restart", 1,
		));
		struct{
			ubyte low; ///
			ubyte high; ///
		}
	}
	FreqControl sound1CntX;
	ubyte NR20; /// Unused register
	ubyte NR21; ///
	ubyte NR22; ///
	FreqControl sound2CntH;
	union {
		ubyte NR30; ///
		mixin(bitfields!(
			ubyte, "", 7,
			bool, "channel3DACEnable", 1,
		));
	}
	ubyte NR31; ///
	ubyte NR32; ///
	FreqControl sound3CntX;
	ubyte NR40; /// Unused register
	ubyte NR41; ///
	ubyte NR42; ///
	union {
		ubyte NR43; ///
		mixin(bitfields!(
			ubyte, "clockDivider", 3,
			bool, "thinnerLFSR", 1,
			ubyte, "clockShift", 4,
		));
	}
	ubyte NR44; ///
	ubyte rightVolume;
	bool vinRight;
	ubyte leftVolume;
	bool vinLeft;
	union {
		ubyte NR51; ///
		mixin(bitfields!(
			bool, "panCh1Right", 1,
			bool, "panCh2Right", 1,
			bool, "panCh3Right", 1,
			bool, "panCh4Right", 1,
			bool, "panCh1Left", 1,
			bool, "panCh2Left", 1,
			bool, "panCh3Left", 1,
			bool, "panCh4Left", 1,
		));
	}
	bool enableAPU;
	bool[4] enabledChannels;
	ushort biasLevel;
	ubyte resolution;
}

///
struct SoundMixerState {
	// This field is normally equal to ID_NUMBER but it is set to other
	// values during sensitive operations for locking purposes.
	ubyte dmaCounter; ///

	// Direct Sound
	ubyte reverb; ///
	ubyte numChans = 8; ///
	ubyte masterVol = 15; ///
	ubyte freq; ///

	ubyte mode; ///
	ubyte cgbCounter15; /// periodically counts from 14 down to 0 (15 states)
	ubyte pcmDmaPeriod = 7; /// number of V-blanks per PCM DMA
	ubyte[3] padding; ///
	int samplesPerFrame; ///
	int samplesPerDma; /// samplesPerFrame * pcmDmaPeriod
	int sampleRate; ///
	float origFreq = 0; /// for adjusting original freq to the new sample rate
	float divFreq = 0; ///
	SoundChannel[20] allChannels;
	auto cgbChans() inout => allChannels[0 .. 4]; ///
	SoundIO reg; ///
	auto chans() inout => allChannels[4 .. $]; ///
	float[2][] outBuffer; ///
	InterpolationMethod interpolationMethod = InterpolationMethod.linear;
	void SampleFreqSet(ubyte runningFrequency, uint outputFrequency) @safe pure
		in(runningFrequency < 15, "Invalid mode!")
	{
		this.freq = runningFrequency;
		samplesPerFrame = cast(uint)((outputFrequency / 60.0f) + 0.5f);
		samplesPerDma = pcmDmaPeriod * samplesPerFrame;
		sampleRate = cast(int)(60.0f * samplesPerFrame);
		divFreq = 1.0f / sampleRate;
		origFreq = (getOrigSampleRate(this.freq) * 59.727678571);

		outBuffer = new float[2][](samplesPerDma);
		outBuffer[] = [0, 0];
	}
}

///
struct SongHeader {
	align(1):
	ubyte trackCount; ///
	ubyte blockCount; ///
	ubyte priority; ///
	ubyte reverb; ///
	RelativePointer!(ToneData, uint) instrument; ///
}

///
struct MusicPlayerTrack {
	bool volumeSet;
	bool unknown2;
	bool pitchSet;
	bool unknown8;
	bool start;
	bool exists;
	ubyte wait; ///
	ubyte patternLevel; ///
	ubyte repeatCount; ///
	ubyte gateTime; ///
	ubyte key; ///
	ubyte velocity; ///
	ubyte runningStatus; ///
	ubyte keyShiftCalculated; ///
	ubyte pitchCalculated; ///
	byte keyShift; ///
	byte keyShiftPublic; ///
	byte tune; ///
	ubyte pitchPublic; ///
	byte bend; ///
	ubyte bendRange; ///
	ubyte volRightCalculated; ///
	ubyte volLeftCalculated; ///
	ubyte vol; ///
	ubyte volPublic; ///
	byte pan; ///
	byte panPublic; ///
	byte modCalculated; ///
	ubyte modDepth; ///
	ubyte modType; ///
	ubyte lfoSpeed; ///
	ubyte lfoSpeedCounter; ///
	ubyte lfoDelay; ///
	ubyte lfoDelayCounter; ///
	ubyte priority; ///
	ubyte echoVolume; ///
	ubyte echoLength; ///
	SoundChannel *chan; ///
	ToneData instrument; ///
	ubyte[10] padding; ///
	ushort unk_3A; ///
	uint count; ///
	const(ubyte)[] cmdPtr; ///
	const(ubyte)[][3] patternStack; ///
	bool gotoSeen;
}

enum MAX_MUSICPLAYER_TRACKS = 16; ///

///
struct SongPointer {
	RelativePointer!(SongHeader, uint) header; ///
	ushort ms; ///
	ushort me; ///
}

alias XcmdFunc = void function(ref M4APlayer, ref MusicPlayerTrack) @safe pure; ///

enum MAX_LINES = 0; ///
