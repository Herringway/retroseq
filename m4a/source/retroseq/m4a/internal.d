///
module retroseq.m4a.internal;

import retroseq.utility;

import retroseq.m4a.m4a;

import std.bitmanip;
import std.typecons;

alias RelativePointer(Element, Offset) = retroseq.utility.RelativePointer!(Element, Offset, 0x8000000, 0xA000000);

enum C_V = 0x40; /// center value for PAN, BEND, and TUNE

union SoundMode {
	uint value; ///
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

///
struct ToneData {
	align(1):
	union {
		ubyte type; ///
		mixin(bitfields!(
			ubyte, "cgbType", 3,
			bool, "fix", 1,
			ubyte, "", 2,
			bool, "spl", 1,
			bool, "rhy", 1,
		));
	}
	union {
		ubyte key; ///
		ubyte drumKey; ///
	}
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
	union {
		ubyte statusFlags; ///
		mixin(bitfields!(
			EnvelopeState, "envelopeState", 2,
			bool, "echoEnabled", 1,
			ubyte, "", 1,
			bool, "loop", 1,
			ubyte, "", 1,
			bool, "stop", 1,
			bool, "start", 1,
		));
		bool isActive() const @safe pure => start || stop || echoEnabled || (envelopeState != EnvelopeState.release);
	}
	union {
		ubyte type; ///
		mixin(bitfields!(
			ubyte, "cgbType", 3,
			bool, "fix", 1,
			ubyte, "", 2,
			bool, "spl", 1,
			bool, "rhy", 1,
		));
	}
	ubyte rightVolume; ///
	ubyte leftVolume; ///
	ubyte attack; ///
	ubyte decay; ///
	ubyte sustain; ///
	ubyte release; ///
	ubyte key; /// midi key as it was translated into final pitch
	ubyte envelopeVolume; ///
	union {
		ubyte envelopeVolumeRight; ///
		ubyte envelopeGoal; ///
	}
	union {
		ubyte envelopeVolumeLeft; ///
		ubyte envelopeCounter; ///
	}
	ubyte echoVolume; ///
	ubyte echoLength; ///
	ubyte[2] padding; ///
	ubyte gateTime; ///
	ubyte midiKey; /// midi key as it was used in the track data
	ubyte velocity; ///
	ubyte priority; ///
	ubyte rhythmPan; ///
	ubyte[3] padding2; ///
	union {
		uint count; ///
		struct {
			ubyte padding6; ///
			ubyte sustainGoal; ///
			ubyte n4; ///
			ubyte pan; ///
		}
	}
	union {
		float fw = 0; ///
		struct {
			ubyte panMask; ///
			mixin(bitfields!(
				bool, "cgbVolumeChange", 1,
				bool, "cgbPitchChange", 1,
				ubyte, "", 6,
			));
			ubyte length; ///
			ubyte sweep; ///
		}
	}
	uint freq; ///
	Wave wav; ///
	byte[16] gbWav; ///
	uint squareNoiseConfig; ///
	const(byte)[] currentPointer; ///
	MusicPlayerTrack *track; ///
	SoundChannel* prevChannelPointer; ///
	SoundChannel* nextChannelPointer; ///
	uint padding3; ///
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
	union {
		ubyte NR50; ///
		mixin(bitfields!(
			ubyte, "rightVolume", 3,
			bool, "vinRight", 1,
			ubyte, "leftVolume", 3,
			bool, "vinLeft", 1,
		));
	}
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
	union {
		ubyte NR52; ///
		mixin(bitfields!(
			bool, "enableCh1", 1,
			bool, "enableCh2", 1,
			bool, "enableCh3", 1,
			bool, "enableCh4", 1,
			ubyte, "", 3,
			bool, "enableAPU", 1,
		));
	}
	ushort SOUNDBIAS_H; ///
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
	ubyte pcmDmaPeriod; /// number of V-blanks per PCM DMA
	ubyte[3] padding; ///
	int samplesPerFrame; ///
	int samplesPerDma; /// samplesPerFrame * pcmDmaPeriod
	int sampleRate; ///
	float origFreq = 0; /// for adjusting original freq to the new sample rate
	float divFreq = 0; ///
	SoundChannel[4] cgbChans; ///
	SoundIO reg; ///
	SoundChannel[16] chans; ///
	float[2][] outBuffer; ///
	float[2][] cgbBuffer; ///
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
	static enum Flags : ubyte {
		none = 0,
		volumeSet = 1 << 0,
		unknown2 = 1 << 1,
		pitchSet = 1 << 2,
		unknown8 = 1 << 3,
		unknown16 = 1 << 4,
		unknown32 = 1 << 5,
		start = 1 << 6,
		exists = 1 << 7,
	}
	BitFlags!Flags flags;
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
