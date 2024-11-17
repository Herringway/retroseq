module m4a.internal;

enum C_V = 0x40; // center value for PAN, BEND, and TUNE

enum SOUND_MODE_REVERB_VAL = 0x0000007F;
enum SOUND_MODE_REVERB_SET = 0x00000080;
enum SOUND_MODE_MAXCHN = 0x00000F00;
enum SOUND_MODE_MAXCHN_SHIFT = 8;
enum SOUND_MODE_MASVOL = 0x0000F000;
enum SOUND_MODE_MASVOL_SHIFT = 12;
enum SOUND_MODE_FREQ_05734 = 0x00010000;
enum SOUND_MODE_FREQ_07884 = 0x00020000;
enum SOUND_MODE_FREQ_10512 = 0x00030000;
enum SOUND_MODE_FREQ_13379 = 0x00040000;
enum SOUND_MODE_FREQ_15768 = 0x00050000;
enum SOUND_MODE_FREQ_18157 = 0x00060000;
enum SOUND_MODE_FREQ_21024 = 0x00070000;
enum SOUND_MODE_FREQ_26758 = 0x00080000;
enum SOUND_MODE_FREQ_31536 = 0x00090000;
enum SOUND_MODE_FREQ_36314 = 0x000A0000;
enum SOUND_MODE_FREQ_40137 = 0x000B0000;
enum SOUND_MODE_FREQ_42048 = 0x000C0000;
enum SOUND_MODE_FREQ = 0x000F0000;
enum SOUND_MODE_FREQ_SHIFT = 16;
enum SOUND_MODE_DA_BIT_9 = 0x00800000;
enum SOUND_MODE_DA_BIT_8 = 0x00900000;
enum SOUND_MODE_DA_BIT_7 = 0x00A00000;
enum SOUND_MODE_DA_BIT_6 = 0x00B00000;
enum SOUND_MODE_DA_BIT = 0x00B00000;
enum SOUND_MODE_DA_BIT_SHIFT = 20;

struct WaveData
{
    ushort type;
    ubyte padding;
    ubyte loopFlags;
    uint freq;
    uint loopStart;
    uint size; // number of samples
    byte[1] data; // samples
};

enum TONEDATA_TYPE_CGB = 0x07;
enum TONEDATA_TYPE_FIX = 0x08;
enum TONEDATA_TYPE_SPL = 0x40; // key split
enum TONEDATA_TYPE_RHY = 0x80; // rhythm

enum TONEDATA_P_S_PAN = 0xc0;
enum TONEDATA_P_S_PAM = TONEDATA_P_S_PAN;

struct ToneData
{
    ubyte type;
    union {
        ubyte key;
        ubyte drumKey;
    };
    ubyte length; // sound length (compatible sound)
    ubyte panSweep; // pan or sweep (compatible sound ch. 1)
    union {
        uint wav;  // struct WaveData *wav;
        uint group;  // struct ToneData *group;
        uint cgbSample;  // uint *cgb3Sample;
        uint squareNoiseConfig;
    };
    union {
        struct {
            ubyte attack;
            ubyte decay;
            ubyte sustain;
            ubyte release;
        };
        uint keySplitTable;  // ubyte *keySplitTable;
    };
};

enum SOUND_CHANNEL_SF_START = 0x80;
enum SOUND_CHANNEL_SF_STOP = 0x40;
enum SOUND_CHANNEL_SF_LOOP = 0x10;
enum SOUND_CHANNEL_SF_IEC = 0x04;
enum SOUND_CHANNEL_SF_ENV = 0x03;
enum SOUND_CHANNEL_SF_ENV_ATTACK = 0x03;
enum SOUND_CHANNEL_SF_ENV_DECAY = 0x02;
enum SOUND_CHANNEL_SF_ENV_SUSTAIN = 0x01;
enum SOUND_CHANNEL_SF_ENV_RELEASE = 0x00;
enum SOUND_CHANNEL_SF_ON = (SOUND_CHANNEL_SF_START | SOUND_CHANNEL_SF_STOP | SOUND_CHANNEL_SF_IEC | SOUND_CHANNEL_SF_ENV);

enum CGB_CHANNEL_MO_PIT = 0x02;
enum CGB_CHANNEL_MO_VOL = 0x01;

enum CGB_NRx2_ENV_DIR_DEC = 0x00;
enum CGB_NRx2_ENV_DIR_INC = 0x08;

struct CgbChannel
{
    ubyte statusFlags;
    ubyte type;
    ubyte rightVolume;
    ubyte leftVolume;
    ubyte attack;
    ubyte decay;
    ubyte sustain;
    ubyte release;
    ubyte key;
    ubyte envelopeVolume;
    ubyte envelopeGoal;
    ubyte envelopeCounter;
    ubyte echoVolume;
    ubyte echoLength;
    ubyte dummy1;
    ubyte dummy2;
    ubyte gateTime;
    ubyte midiKey;
    ubyte velocity;
    ubyte priority;
    ubyte rhythmPan;
    ubyte[3] dummy3;
    ubyte dummy5;
    ubyte sustainGoal;
    ubyte n4;                  // NR[1-4]4 register (initial, length bit)
    ubyte pan;
    ubyte panMask;
    ubyte modify;
    ubyte length;
    ubyte sweep;
    uint freq;
    uint *wavePointer;       // instructs CgbMain to load targeted wave
    uint *currentPointer;    // stores the currently loaded wave
    MusicPlayerTrack* track;
    void *prevChannelPointer;
    void *nextChannelPointer;
    ubyte[8] dummy4;
};

struct SoundChannel
{
    align(1):
    ubyte statusFlags;
    ubyte type;
    ubyte rightVolume;
    ubyte leftVolume;
    ubyte attack;
    ubyte decay;
    ubyte sustain;
    ubyte release;
    ubyte key;             // midi key as it was translated into final pitch
    ubyte envelopeVolume;
    union {
        ubyte envelopeVolumeRight;
        ubyte envelopeGoal;
    }
    union {
        ubyte envelopeVolumeLeft;
        ubyte envelopeCtr;
    }
    ubyte echoVolume;
    ubyte echoLength;
    ubyte[2] padding;
    ubyte gateTime;
    ubyte midiKey;         // midi key as it was used in the track data
    ubyte velocity;
    ubyte priority;
    ubyte rhythmPan;
    ubyte[3] padding2;
    union {
        uint count;
        struct {
            ubyte padding6;
            ubyte sustainGoal;
            ubyte nrx4;
            ubyte pan;
        };
    };
    union {
        float fw;
        struct {
            ubyte panMask;
            ubyte cgbStatus;
            ubyte length;
            ubyte sweep;
        };
    };
    uint freq;
    WaveData *wav;
    byte *currentPointer;
    MusicPlayerTrack *track;
    void *prevChannelPointer;
    void *nextChannelPointer;
    uint padding3;
    ushort xpi;
    ushort xpc;
};

enum MAX_DIRECTSOUND_CHANNELS = 16;

alias MPlayFunc = void function();
alias PlyNoteFunc = void function(uint, MusicPlayerInfo *, MusicPlayerTrack *);
alias CgbSoundFunc = void function();
alias CgbOscOffFunc = void function(ubyte);
alias MidiKeyToCgbFreqFunc = uint function(ubyte, ubyte, ubyte);
alias ExtVolPitFunc = void function();
alias MPlayMainFunc = void function(MusicPlayerInfo *);

// SOUNDCNT_H
enum SOUND_CGB_MIX_QUARTER = 0x0000;
enum SOUND_CGB_MIX_HALF = 0x0001;
enum SOUND_CGB_MIX_FULL = 0x0002;
enum SOUND_A_MIX_HALF = 0x0000;
enum SOUND_A_MIX_FULL = 0x0004;
enum SOUND_B_MIX_HALF = 0x0000;
enum SOUND_B_MIX_FULL = 0x0008;
enum SOUND_ALL_MIX_FULL = 0x000E;
enum SOUND_A_RIGHT_OUTPUT = 0x0100;
enum SOUND_A_LEFT_OUTPUT = 0x0200;
enum SOUND_A_TIMER_0 = 0x0000;
enum SOUND_A_TIMER_1 = 0x0400;
enum SOUND_A_FIFO_RESET = 0x0800;
enum SOUND_B_RIGHT_OUTPUT = 0x1000;
enum SOUND_B_LEFT_OUTPUT = 0x2000;
enum SOUND_B_TIMER_0 = 0x0000;
enum SOUND_B_TIMER_1 = 0x4000;
enum SOUND_B_FIFO_RESET = 0x8000;

// SOUNDCNT_X
enum SOUND_1_ON = 0x0001;
enum SOUND_2_ON = 0x0002;
enum SOUND_3_ON = 0x0004;
enum SOUND_4_ON = 0x0008;
enum SOUND_MASTER_ENABLE = 0x0080;

struct SoundIO
{
    ubyte NR10;
    ubyte NR10x;
    ubyte NR11;
    ubyte NR12;
    union{
        ushort SOUND1CNT_X;
        struct{
            ubyte NR13;
            ubyte NR14;
        };
    };
    ubyte NR21;
    ubyte NR22;
    union{
        ushort SOUND2CNT_H;
        struct{
            ubyte NR23;
            ubyte NR24;
        };
    };
    ubyte NR30;
    ubyte NR30x;
    ubyte NR31;
    ubyte NR32;
    union{
        ushort SOUND3CNT_X;
        struct{
            ubyte NR33;
            ubyte NR34;
        };
    };
    ubyte NR41;
    ubyte NR42;
    ubyte NR43;
    ubyte NR44;
    ubyte NR50;
    ubyte NR51;
    ushort SOUNDCNT_H;
    ubyte NR52;
    ushort SOUNDBIAS_H;
};

struct SoundMixerState
{
    // This field is normally equal to ID_NUMBER but it is set to other
    // values during sensitive operations for locking purposes.
    // This field should be volatile but isn't. This could potentially cause
    // race conditions.
    ubyte dmaCounter;

    // Direct Sound
    ubyte reverb;
    ubyte numChans;
    ubyte masterVol;
    ubyte freq;

    ubyte mode;
    ubyte cgbCounter15;          // periodically counts from 14 down to 0 (15 states)
    ubyte pcmDmaPeriod; // number of V-blanks per PCM DMA
    ubyte maxScanlines;
    ubyte[3] padding;
    int samplesPerFrame;
    int samplesPerDma;  // samplesPerFrame * pcmDmaPeriod
    int sampleRate;
    float origFreq;  // for adjusting original freq to the new sample rate
    float divFreq;
    CgbChannel *cgbChans;
    MPlayMainFunc firstPlayerFunc;
    MusicPlayerInfo *firstPlayer;
    CgbSoundFunc cgbMixerFunc;
    CgbOscOffFunc cgbNoteOffFunc;
    MidiKeyToCgbFreqFunc cgbCalcFreqFunc;
    MPlayFunc *mp2kEventFuncTable;
    PlyNoteFunc mp2kEventNxxFunc;
    ExtVolPitFunc ExtVolPit;
    void *reserved2;
    void *reserved3;
    void *reversed4;
    void *reserved5;
    SoundIO reg;
    SoundChannel[MAX_DIRECTSOUND_CHANNELS] chans;
    float[] outBuffer;
    float[] cgbBuffer;
};

struct SongHeader
{
    ubyte trackCount;
    ubyte blockCount;
    ubyte priority;
    ubyte reverb;
    uint instrument;  // struct ToneData *instrument;
    uint[1] part; // ubyte *part[1];
};

enum MPT_FLG_VOLSET = 0x01;
enum MPT_FLG_VOLCHG = 0x03;
enum MPT_FLG_PITSET = 0x04;
enum MPT_FLG_PITCHG = 0x0C;
enum MPT_FLG_START = 0x40;
enum MPT_FLG_EXIST = 0x80;

struct MusicPlayerTrack
{
    ubyte flags;
    ubyte wait;
    ubyte patternLevel;
    ubyte repeatCount;
    ubyte gateTime;
    ubyte key;
    ubyte velocity;
    ubyte runningStatus;
    ubyte keyShiftCalculated;
    ubyte pitchCalculated;
    byte keyShift;
    byte keyShiftPublic;
    byte tune;
    ubyte pitchPublic;
    byte bend;
    ubyte bendRange;
    ubyte volRightCalculated;
    ubyte volLeftCalculated;
    ubyte vol;
    ubyte volPublic;
    byte pan;
    byte panPublic;
    byte modCalculated;
    ubyte modDepth;
    ubyte modType;
    ubyte lfoSpeed;
    ubyte lfoSpeedCounter;
    ubyte lfoDelay;
    ubyte lfoDelayCounter;
    ubyte priority;
    ubyte echoVolume;
    ubyte echoLength;
    SoundChannel *chan;
    ToneData instrument;
    ubyte[10] padding;
    ushort unk_3A;
    uint count;
    ubyte *cmdPtr;
    ubyte*[3] patternStack;
};

enum MUSICPLAYER_STATUS_TRACK = 0x0000ffff;
enum MUSICPLAYER_STATUS_PAUSE = 0x80000000;

enum MAX_MUSICPLAYER_TRACKS = 16;

enum TEMPORARY_FADE = 0x0001;
enum FADE_IN = 0x0002;
enum FADE_VOL_MAX = 64;
enum FADE_VOL_SHIFT = 2;

struct MusicPlayerInfo
{
    SongHeader *songHeader;
    uint status;
    ubyte trackCount;
    ubyte priority;
    ubyte cmd;
    ubyte checkSongPriority;
    uint clock;
    ubyte[8] padding;
    ubyte *memAccArea;
    ushort tempoRawBPM;
    ushort tempoScale;
    ushort tempoInterval;
    ushort tempoCounter;
    ushort fadeInterval;
    ushort fadeCounter;
    ushort fadeVolume;
    MusicPlayerTrack *tracks;
    ToneData *voicegroup;
    MPlayMainFunc nextPlayerFunc;
    MusicPlayerInfo *nextPlayer;
};


struct Song
{
    uint header;  // struct SongHeader *header;
    ushort ms;
    ushort me;
};


//extern ubyte gMPlayMemAccArea[];

//extern char SoundMainRAM[];

//extern MPlayFunc gMPlayJumpTable[];

alias XcmdFunc = void function(MusicPlayerInfo *, MusicPlayerTrack *);
//extern const XcmdFunc gXcmdTable[];

//extern struct CgbChannel gCgbChans[];

//extern const ubyte gScaleTable[];
//extern const uint gFreqTable[];
//extern const ushort gPcmSamplesPerVBlankTable[];

//extern const ubyte gCgbScaleTable[];
//extern const short gCgbFreqTable[];
//extern const ubyte gNoiseTable[];

//extern const struct ToneData voicegroup000;

enum MAX_LINES = 0;

//uint umul3232H32(uint multiplier, uint multiplicand);
//void SoundMain(void);
//void SoundMainBTM(void *ptr);
//void TrackStop(struct MusicPlayerInfo *player, struct MusicPlayerTrack *track);
//void MPlayMain(struct MusicPlayerInfo *);
//void MP2KClearChain(struct SoundChannel *chan);

//void MPlayContinue(struct MusicPlayerInfo *mplayInfo);
//void MPlayStart(struct MusicPlayerInfo *mplayInfo, struct SongHeader *songHeader);
//void m4aMPlayStop(struct MusicPlayerInfo *mplayInfo);
//void FadeOutBody(struct MusicPlayerInfo *mplayInfo);
//void TrkVolPitSet(struct MusicPlayerInfo *mplayInfo, struct MusicPlayerTrack *track);
//void MPlayFadeOut(struct MusicPlayerInfo *mplayInfo, ushort speed);
//void ClearChain(void *x);
//void SoundInit(struct SoundMixerState *soundInfo);
//void MPlayExtender(struct CgbChannel *cgbChans);
//void m4aSoundMode(uint mode);
//void MPlayOpen(struct MusicPlayerInfo *mplayInfo, struct MusicPlayerTrack *track, ubyte a3);
//void cgbMixerFunc(void);
//void cgbNoteOffFunc(ubyte);
//void CgbModVol(struct CgbChannel *chan);
//uint cgbCalcFreqFunc(ubyte, ubyte, ubyte);
//void DummyFunc(void);
//void MPlayJumpTableCopy(void **mplayJumpTable);
//void SampleFreqSet(uint freq);

//void m4aMPlayTempoControl(struct MusicPlayerInfo *mplayInfo, ushort tempo);
//void m4aMPlayVolumeControl(struct MusicPlayerInfo *mplayInfo, ushort trackBits, ushort volume);
//void m4aMPlayPitchControl(struct MusicPlayerInfo *mplayInfo, ushort trackBits, short pitch);
//void m4aMPlayPanpotControl(struct MusicPlayerInfo *mplayInfo, ushort trackBits, byte pan);
//void ClearModM(struct MusicPlayerTrack *track);
//void m4aMPlayModDepthSet(struct MusicPlayerInfo *mplayInfo, ushort trackBits, ubyte modDepth);
//void m4aMPlayLFOSpeedSet(struct MusicPlayerInfo *mplayInfo, ushort trackBits, ubyte lfoSpeed);

//// sound command handler functions
//void MP2K_event_fine(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_goto(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_patt(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_pend(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_rept(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_memacc(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_prio(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_tempo(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_keysh(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_voice(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_vol(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_pan(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_bend(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_bendr(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_lfos(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_lfodl(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_mod(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_modt(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_tune(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_port(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xcmd(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void MP2K_event_endtie(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_note(struct MusicPlayerInfo *, struct MusicPlayerTrack *);

//// extended sound command handler functions
//void ply_xxx(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xwave(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xtype(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xatta(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xdeca(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xsust(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xrele(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xiecv(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xiecl(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xleng(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xswee(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xcmd_0C(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
//void ply_xcmd_0D(struct MusicPlayerInfo *, struct MusicPlayerTrack *);
