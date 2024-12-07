///
module m4a.internal;

import retroseq.utility;

import m4a.m4a;

///
struct RelativePointer(Element, Offset) {
	align(1):
	Offset offset; ///
	enum Base = 0x8000000; ///
	///
	bool isValid() const @safe pure {
		return offset >= Base;
	}
	///
	const(Element)[] toAbsoluteArray(const(ubyte)[] base) const {
		const realOffset = offset - Base;
		return sliceMax!(const Element)(cast(const(ubyte)[])base, realOffset);
	}
	///
	Offset opAssign(Offset newValue) {
		return offset = newValue;
	}
}

enum C_V = 0x40; /// center value for PAN, BEND, and TUNE

enum SOUND_MODE_REVERB_VAL = 0x0000007F; ///
enum SOUND_MODE_REVERB_SET = 0x00000080; ///
enum SOUND_MODE_MAXCHN = 0x00000F00; ///
enum SOUND_MODE_MAXCHN_SHIFT = 8; ///
enum SOUND_MODE_MASVOL = 0x0000F000; ///
enum SOUND_MODE_MASVOL_SHIFT = 12; ///
enum SOUND_MODE_FREQ_05734 = 0x00010000; ///
enum SOUND_MODE_FREQ_07884 = 0x00020000; ///
enum SOUND_MODE_FREQ_10512 = 0x00030000; ///
enum SOUND_MODE_FREQ_13379 = 0x00040000; ///
enum SOUND_MODE_FREQ_15768 = 0x00050000; ///
enum SOUND_MODE_FREQ_18157 = 0x00060000; ///
enum SOUND_MODE_FREQ_21024 = 0x00070000; ///
enum SOUND_MODE_FREQ_26758 = 0x00080000; ///
enum SOUND_MODE_FREQ_31536 = 0x00090000; ///
enum SOUND_MODE_FREQ_36314 = 0x000A0000; ///
enum SOUND_MODE_FREQ_40137 = 0x000B0000; ///
enum SOUND_MODE_FREQ_42048 = 0x000C0000; ///
enum SOUND_MODE_FREQ = 0x000F0000; ///
enum SOUND_MODE_FREQ_SHIFT = 16; ///
enum SOUND_MODE_DA_BIT_9 = 0x00800000; ///
enum SOUND_MODE_DA_BIT_8 = 0x00900000; ///
enum SOUND_MODE_DA_BIT_7 = 0x00A00000; ///
enum SOUND_MODE_DA_BIT_6 = 0x00B00000; ///
enum SOUND_MODE_DA_BIT = 0x00B00000; ///
enum SOUND_MODE_DA_BIT_SHIFT = 20; ///

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

enum TONEDATA_TYPE_CGB = 0x07; ///
enum TONEDATA_TYPE_FIX = 0x08; ///
enum TONEDATA_TYPE_SPL = 0x40; /// key split
enum TONEDATA_TYPE_RHY = 0x80; /// rhythm

enum TONEDATA_P_S_PAN = 0xc0; ///
enum TONEDATA_P_S_PAM = TONEDATA_P_S_PAN; ///

///
struct ToneData {
	align(1):
	ubyte type; ///
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

enum SOUND_CHANNEL_SF_START = 0x80; ///
enum SOUND_CHANNEL_SF_STOP = 0x40; ///
enum SOUND_CHANNEL_SF_LOOP = 0x10; ///
enum SOUND_CHANNEL_SF_IEC = 0x04; ///
enum SOUND_CHANNEL_SF_ENV = 0x03; ///
enum SOUND_CHANNEL_SF_ENV_ATTACK = 0x03; ///
enum SOUND_CHANNEL_SF_ENV_DECAY = 0x02; ///
enum SOUND_CHANNEL_SF_ENV_SUSTAIN = 0x01; ///
enum SOUND_CHANNEL_SF_ENV_RELEASE = 0x00; ///
enum SOUND_CHANNEL_SF_ON = (SOUND_CHANNEL_SF_START | SOUND_CHANNEL_SF_STOP | SOUND_CHANNEL_SF_IEC | SOUND_CHANNEL_SF_ENV); ///

enum CGB_CHANNEL_MO_PIT = 0x02; ///
enum CGB_CHANNEL_MO_VOL = 0x01; ///

enum CGB_NRx2_ENV_DIR_DEC = 0x00; ///
enum CGB_NRx2_ENV_DIR_INC = 0x08; ///

struct SoundChannel {
	ubyte statusFlags; ///
	ubyte type; ///
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
	ubyte NR10x; ///
	ubyte NR11; ///
	ubyte NR12; ///
	union{
		ushort SOUND1CNT_X; ///
		struct{
			ubyte NR13; ///
			ubyte NR14; ///
		}
	}
	ubyte NR21; ///
	ubyte NR22; ///
	union{
		ushort SOUND2CNT_H; ///
		struct{
			ubyte NR23; ///
			ubyte NR24; ///
		}
	}
	ubyte NR30; ///
	ubyte NR30x; ///
	ubyte NR31; ///
	ubyte NR32; ///
	union{
		ushort SOUND3CNT_X; ///
		struct{
			ubyte NR33; ///
			ubyte NR34; ///
		}
	}
	ubyte NR41; ///
	ubyte NR42; ///
	ubyte NR43; ///
	ubyte NR44; ///
	ubyte NR50; ///
	ubyte NR51; ///
	ushort SOUNDCNT_H; ///
	ubyte NR52; ///
	ushort SOUNDBIAS_H; ///
}

///
struct SoundMixerState {
	// This field is normally equal to ID_NUMBER but it is set to other
	// values during sensitive operations for locking purposes.
	// This field should be volatile but isn't. This could potentially cause
	// race conditions.
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
	SoundChannel[] cgbChans; ///
	MPlayMainFunc firstPlayerFunc; ///
	MusicPlayerInfo *firstPlayer; ///
	CgbSoundFunc cgbMixerFunc; ///
	CgbOscOffFunc cgbNoteOffFunc; ///
	MidiKeyToCgbFreqFunc cgbCalcFreqFunc; ///
	MPlayFunc[] mp2kEventFuncTable; ///
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
