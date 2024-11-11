module sseq.consts;

__gshared const uint ARM7_CLOCK = 33513982;
__gshared const double SecondsPerClockCycle = 64.0 * 2728.0 / ARM7_CLOCK;

uint BIT(uint n) { return 1 << n; }

enum { TS_ALLOCBIT, TS_NOTEWAIT, TS_PORTABIT, TS_TIEBIT, TS_END, TS_BITS };

enum { TUF_VOL, TUF_PAN, TUF_TIMER, TUF_MOD, TUF_LEN, TUF_BITS };

enum { CS_NONE, CS_START, CS_ATTACK, CS_DECAY, CS_SUSTAIN, CS_RELEASE };

enum { CF_UPDVOL, CF_UPDPAN, CF_UPDTMR, CF_BITS };

enum { TYPE_PCM, TYPE_PSG, TYPE_NOISE };

__gshared const int FSS_TRACKCOUNT = 16;
__gshared const int FSS_MAXTRACKS = 32;
__gshared const int FSS_TRACKSTACKSIZE = 3;
__gshared const int AMPL_K = 723;
__gshared const int AMPL_MIN = -AMPL_K;
__gshared const int AMPL_THRESHOLD = AMPL_MIN << 7;

int SOUND_FREQ(int n) { return -0x1000000 / n; }

uint SOUND_VOL(int n) { return n; }
uint SOUND_VOLDIV(int n) { return n << 8; }
uint SOUND_PAN(int n) { return n << 16; }
uint SOUND_DUTY(int n) { return n << 24; }
__gshared const uint SOUND_REPEAT = BIT(27);
__gshared const uint SOUND_ONE_SHOT = BIT(28);
uint SOUND_LOOP(bool a) { return a ? SOUND_REPEAT : SOUND_ONE_SHOT; }
__gshared const uint SOUND_FORMAT_PSG = 3 << 29;
uint SOUND_FORMAT(int n) { return n << 29; }
__gshared const uint SCHANNEL_ENABLE = BIT(31);

enum Interpolation
{
	INTERPOLATION_NONE,
	INTERPOLATION_LINEAR,
	INTERPOLATION_4POINTLEGRANGE,
	INTERPOLATION_6POINTLEGRANGE,
	INTERPOLATION_SINC
}
