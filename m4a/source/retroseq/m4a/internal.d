///
module retroseq.m4a.internal;

import retroseq.utility;

import retroseq.m4a.m4a;

import std.bitmanip;

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

enum TONEDATA_P_S_PAN = 0xc0; ///
enum TONEDATA_P_S_PAM = TONEDATA_P_S_PAN; ///

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

enum CGB_CHANNEL_MO_PIT = 0x02; ///
enum CGB_CHANNEL_MO_VOL = 0x01; ///

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
			ubyte cgbStatus; ///
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

enum MAX_DIRECTSOUND_CHANNELS = 16; ///

alias MPlayFunc = void function(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack) @safe pure; ///
alias PlyNoteFunc = void function(ref M4APlayer, uint, ref MusicPlayerInfo, ref MusicPlayerTrack) @safe pure; ///
alias CgbSoundFunc = void function(ref M4APlayer) @safe pure; ///
alias CgbOscOffFunc = void function(ref M4APlayer, ubyte) @safe pure; ///
alias MidiKeyToCgbFreqFunc = uint function(ubyte, ubyte, ubyte) @safe pure; ///
alias ExtVolPitFunc = void function() @safe pure; ///
alias MPlayMainFunc = void function(ref M4APlayer, ref MusicPlayerInfo) @safe pure; ///

// SOUNDCNT_H
enum SOUND_CGB_MIX_QUARTER = 0x0000; ///
enum SOUND_CGB_MIX_HALF = 0x0001; ///
enum SOUND_CGB_MIX_FULL = 0x0002; ///
enum SOUND_A_MIX_HALF = 0x0000; ///
enum SOUND_A_MIX_FULL = 0x0004; ///
enum SOUND_B_MIX_HALF = 0x0000; ///
enum SOUND_B_MIX_FULL = 0x0008; ///
enum SOUND_ALL_MIX_FULL = 0x000E; ///
enum SOUND_A_RIGHT_OUTPUT = 0x0100; ///
enum SOUND_A_LEFT_OUTPUT = 0x0200; ///
enum SOUND_A_TIMER_0 = 0x0000; ///
enum SOUND_A_TIMER_1 = 0x0400; ///
enum SOUND_A_FIFO_RESET = 0x0800; ///
enum SOUND_B_RIGHT_OUTPUT = 0x1000; ///
enum SOUND_B_LEFT_OUTPUT = 0x2000; ///
enum SOUND_B_TIMER_0 = 0x0000; ///
enum SOUND_B_TIMER_1 = 0x4000; ///
enum SOUND_B_FIFO_RESET = 0x8000; ///

// SOUNDCNT_X
enum SOUND_1_ON = 0x0001; ///
enum SOUND_2_ON = 0x0002; ///
enum SOUND_3_ON = 0x0004; ///
enum SOUND_4_ON = 0x0008; ///
enum SOUND_MASTER_ENABLE = 0x0080; ///

///
struct SoundIO {
	ubyte NR10; ///
	ubyte NR11; ///
	ubyte NR12; ///
	union{
		ushort SOUND1CNT_X; ///
		struct{
			ubyte NR13; ///
			ubyte NR14; ///
		}
	}
	ubyte NR20; /// Unused register
	ubyte NR21; ///
	ubyte NR22; ///
	union{
		ushort SOUND2CNT_H; ///
		struct{
			ubyte NR23; ///
			ubyte NR24; ///
		}
	}
	union {
		ubyte NR30; ///
		mixin(bitfields!(
			ubyte, "", 7,
			bool, "channel3DACEnable", 1,
		));
	}
	ubyte NR31; ///
	ubyte NR32; ///
	union{
		ushort SOUND3CNT_X; ///
		struct{
			ubyte NR33; ///
			ubyte NR34; ///
		}
	}
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
	ushort SOUNDCNT_H; ///
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
	ubyte numChans; ///
	ubyte masterVol; ///
	ubyte freq; ///

	ubyte mode; ///
	ubyte cgbCounter15; /// periodically counts from 14 down to 0 (15 states)
	ubyte pcmDmaPeriod; /// number of V-blanks per PCM DMA
	ubyte maxScanlines; ///
	ubyte[3] padding; ///
	int samplesPerFrame; ///
	int samplesPerDma; /// samplesPerFrame * pcmDmaPeriod
	int sampleRate; ///
	float origFreq = 0; /// for adjusting original freq to the new sample rate
	float divFreq = 0; ///
	SoundChannel[4] cgbChans; ///
	MPlayMainFunc firstPlayerFunc; ///
	MusicPlayerInfo *firstPlayer; ///
	CgbSoundFunc cgbMixerFunc; ///
	CgbOscOffFunc cgbNoteOffFunc; ///
	MidiKeyToCgbFreqFunc cgbCalcFreqFunc; ///
	PlyNoteFunc mp2kEventNxxFunc; ///
	ExtVolPitFunc ExtVolPit; ///
	void *reserved2; ///
	void *reserved3; ///
	void *reversed4; ///
	void *reserved5; ///
	SoundIO reg; ///
	SoundChannel[MAX_DIRECTSOUND_CHANNELS] chans; ///
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

enum MPT_FLG_VOLSET = 0x01; ///
enum MPT_FLG_VOLCHG = 0x03; ///
enum MPT_FLG_PITSET = 0x04; ///
enum MPT_FLG_PITCHG = 0x0C; ///
enum MPT_FLG_START = 0x40; ///
enum MPT_FLG_EXIST = 0x80; ///

///
struct MusicPlayerTrack {
	ubyte flags; ///
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

enum MUSICPLAYER_STATUS_TRACK = 0x0000ffff; ///
enum MUSICPLAYER_STATUS_PAUSE = 0x80000000; ///

enum MAX_MUSICPLAYER_TRACKS = 16; ///

enum TEMPORARY_FADE = 0x0001; ///
enum FADE_IN = 0x0002; ///
enum FADE_VOL_MAX = 64; ///
enum FADE_VOL_SHIFT = 2; ///

///
struct MusicPlayerInfo {
	uint playing = uint.max; ///
	SongHeader songHeader; ///
	uint status; ///
	ubyte trackCount; ///
	ubyte priority; ///
	ubyte cmd; ///
	ubyte checkSongPriority; ///
	uint clock; ///
	ubyte[8] padding; ///
	ubyte[] memAccArea; ///
	ushort tempoRawBPM; ///
	ushort tempoScale; ///
	ushort tempoInterval; ///
	ushort tempoCounter; ///
	ushort fadeInterval; ///
	ushort fadeCounter; ///
	ushort fadeVolume; ///
	MusicPlayerTrack[] tracks; ///
	const(ToneData)[] voicegroup; ///
	MPlayMainFunc nextPlayerFunc; ///
	MusicPlayerInfo *nextPlayer; ///
}

///
struct SongPointer {
	RelativePointer!(SongHeader, uint) header; ///
	ushort ms; ///
	ushort me; ///
}

alias XcmdFunc = void function(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack) @safe pure; ///

enum MAX_LINES = 0; ///
