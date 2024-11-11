module sseq.track;

import sseq.channel;
import sseq.common;
import sseq.consts;
import sseq.player;
import sseq.sbnk;

import std.random;

enum StackType
{
	STACKTYPE_CALL,
	STACKTYPE_LOOP
}

struct StackValue
{
	StackType type = StackType.STACKTYPE_CALL;
	const(ubyte)[] dest = null;
}

struct Override
{
	bool overriding = false;
	int cmd;
	int value;
	int extraValue;

	int val(ref const(ubyte)[] pData, int function(ref const(ubyte)[]) @safe reader, bool returnExtra = false) @safe
	{
		if (this.overriding)
			return returnExtra ? this.extraValue : this.value;
		else
			return reader(pData);
	}
}

struct Track
{
	byte trackId = -1;

	ubyte[TS_BITS] state;
	ubyte num, prio;
	Player *ply;

	const(ubyte)[] trackData;
	const(ubyte)[] trackDataCurrent;
	StackValue[FSS_TRACKSTACKSIZE] stack;
	ubyte stackPos;
	ubyte[FSS_TRACKSTACKSIZE] loopCount;
	Override overriding;
	bool lastComparisonResult = true;

	int wait;
	ushort patch;
	ubyte portaKey, portaTime;
	short sweepPitch;
	ubyte vol, expr;
	byte pan; // -64..63
	ubyte pitchBendRange;
	byte pitchBend;
	byte transpose;

	ubyte a, d, s, r;

	ubyte modType, modSpeed, modDepth, modRange;
	ushort modDelay;

	ubyte[TUF_BITS] updateFlags;

	void Init(ubyte handle, Player *player, const(ubyte)[] dataPos, int n) @safe {
		this.trackId = handle;
		this.num = cast(ubyte)n;
		this.ply = player;
		this.trackData = dataPos;
		this.ClearState();
	}
	void Zero() @safe {
		this.trackId = -1;

		this.state = false;
		this.num = this.prio = 0;
		this.ply = null;

		this.trackDataCurrent = this.trackData = null;
		this.stack[] = StackValue();
		this.stackPos = 0;
		this.loopCount = 0;
		this.overriding = Override(false);
		this.lastComparisonResult = true;

		this.wait = 0;
		this.patch = 0;
		this.portaKey = this.portaTime = 0;
		this.sweepPitch = 0;
		this.vol = this.expr = 0;
		this.pan = 0;
		this.pitchBendRange = 0;
		this.pitchBend = this.transpose = 0;

		this.a = this.d = this.s = this.r = 0;

		this.modType = this.modSpeed = this.modDepth = this.modRange = 0;
		this.modDelay = 0;

		this.updateFlags = false;
	}
	void ClearState() @safe {
		this.state = false;
		this.state[TS_ALLOCBIT] = true;
		this.state[TS_NOTEWAIT] = true;
		this.prio = cast(ubyte)(this.ply.prio + 64);

		this.trackDataCurrent = this.trackData;
		this.stackPos = 0;

		this.wait = 0;
		this.patch = 0;
		this.portaKey = 60;
		this.portaTime = 0;
		this.sweepPitch = 0;
		this.vol = this.expr = 127;
		this.pan = 0;
		this.pitchBendRange = 2;
		this.pitchBend = this.transpose = 0;

		this.a = this.d = this.s = this.r = 0xFF;

		this.modType = 0;
		this.modRange = 1;
		this.modSpeed = 16;
		this.modDelay = 0;
		this.modDepth = 0;
	}
	void Free() @safe {
		this.state = false;
		this.updateFlags = false;
	}
	int NoteOn(int key, int vel, int len) @safe {
		auto sbnk = this.ply.sseq.bank;

		if (this.patch >= sbnk.instruments.length)
			return -1;

		bool bIsPCM = true;
		Channel *chn = null;
		int nCh = -1;

		auto instrument = &sbnk.instruments[this.patch];
		const(SBNKInstrumentRange) *noteDef = null;
		int fRecord = instrument.record;

		if (fRecord == 16)
		{
			if (!(instrument.ranges[0].lowNote <= key && key <= instrument.ranges[instrument.ranges.length - 1].highNote))
				return -1;
			int rn = key - instrument.ranges[0].lowNote;
			noteDef = &instrument.ranges[rn];
			fRecord = noteDef.record;
		}
		else if (fRecord == 17)
		{
			size_t reg, ranges;
			for (reg = 0, ranges = instrument.ranges.length; reg < ranges; ++reg)
				if (key <= instrument.ranges[reg].highNote)
					break;
			if (reg == ranges)
				return -1;

			noteDef = &instrument.ranges[reg];
			fRecord = noteDef.record;
		}

		if (!fRecord)
			return -1;
		else if (fRecord == 1)
		{
			if (!noteDef)
				noteDef = &instrument.ranges[0];
		}
		else if (fRecord < 4)
		{
			// PSG
			// fRecord = 2 . PSG tone, pNoteDef.wavid . PSG duty
			// fRecord = 3 . PSG noise
			bIsPCM = false;
			if (!noteDef)
				noteDef = &instrument.ranges[0];
			if (fRecord == 3)
			{
				nCh = this.ply.ChannelAlloc(TYPE_NOISE, this.prio);
				if (nCh < 0)
					return -1;
				chn = &this.ply.channels[nCh];
				chn.tempReg.CR = SOUND_FORMAT_PSG | SCHANNEL_ENABLE;
			}
			else
			{
				nCh = this.ply.ChannelAlloc(TYPE_PSG, this.prio);
				if (nCh < 0)
					return -1;
				chn = &this.ply.channels[nCh];
				chn.tempReg.CR = SOUND_FORMAT_PSG | SCHANNEL_ENABLE | SOUND_DUTY(noteDef.swav & 0x7);
			}
			chn.tempReg.TIMER = cast(short)-SOUND_FREQ(262 * 8); // key #60 (C4)
			chn.reg.samplePosition = -1;
			chn.reg.psgX = 0x7FFF;
		}

		if (bIsPCM)
		{
			nCh = this.ply.ChannelAlloc(TYPE_PCM, this.prio);
			if (nCh < 0)
				return -1;
			chn = &this.ply.channels[nCh];

			auto swav = &sbnk.waveArc[noteDef.swar].swavs[noteDef.swav];
			chn.tempReg.CR = SOUND_FORMAT(swav.waveType & 3) | SOUND_LOOP(!!swav.loop) | SCHANNEL_ENABLE;
			chn.tempReg.SOURCE = swav;
			chn.tempReg.TIMER = swav.time;
			chn.tempReg.REPEAT_POINT = swav.loopOffset;
			chn.tempReg.LENGTH = swav.nonLoopLength;
			chn.reg.samplePosition = -3;
		}

		chn.state = CS_START;
		chn.trackId = this.trackId;
		chn.flags = false;
		chn.prio = this.prio;
		chn.key = cast(ubyte)key;
		chn.orgKey = noteDef.noteNumber;
		chn.velocity = cast(short)Cnv_Sust(vel);
		chn.pan = cast(byte)(cast(int)(noteDef.pan) - 64);
		chn.modDelayCnt = 0;
		chn.modCounter = 0;
		chn.noteLength = len;
		chn.reg.sampleIncrease = 0;

		chn.attackLvl = cast(ubyte)Cnv_Attack(this.a == 0xFF ? noteDef.attackRate : this.a);
		chn.decayRate = cast(ushort)Cnv_Fall(this.d == 0xFF ? noteDef.decayRate : this.d);
		chn.sustainLvl = this.s == 0xFF ? noteDef.sustainLevel : this.s;
		chn.releaseRate = cast(ushort)Cnv_Fall(this.r == 0xFF ? noteDef.releaseRate : this.r);

		chn.UpdateVol(this);
		chn.UpdatePan(this);
		chn.UpdateTune(this);
		chn.UpdateMod(this);
		chn.UpdatePorta(this);

		this.portaKey = cast(ubyte)key;

		return nCh;
	}
	int NoteOnTie(int key, int vel) @safe {
		// Find an existing note
		int i;
		Channel *chn = null;
		for (i = 0; i < 16; ++i)
		{
			chn = &this.ply.channels[i];
			if (chn.state > CS_NONE && chn.trackId == this.trackId && chn.state != CS_RELEASE)
				break;
		}

		if (i == 16)
			// Can't find note . create an endless one
			return this.NoteOn(key, vel, -1);

		chn.flags = false;
		chn.prio = this.prio;
		chn.key = cast(ubyte)key;
		chn.velocity = cast(short)Cnv_Sust(vel);
		chn.modDelayCnt = 0;
		chn.modCounter = 0;

		chn.UpdateVol(this);
		//chn.UpdatePan(this);
		chn.UpdateTune(this);
		chn.UpdateMod(this);
		chn.UpdatePorta(this);

		this.portaKey = cast(ubyte)key;
		chn.flags[CF_UPDTMR] = true;

		return i;
	}
	void ReleaseAllNotes() @safe {
		for (int i = 0; i < 16; ++i)
		{
			Channel* chn = &this.ply.channels[i];
			if (chn.state > CS_NONE && chn.trackId == this.trackId && chn.state != CS_RELEASE)
				chn.Release();
		}
	}
	void Run() @safe {

		// Indicate "heartbeat" for this track
		this.updateFlags[TUF_LEN] = true;

		// Exit if the track has already ended
		if (this.state[TS_END])
			return;

		if (this.wait)
		{
			--this.wait;
			if (this.wait)
				return;
		}

		while (!this.wait)
		{
			int cmd;
			if (this.overriding.overriding)
				cmd = this.overriding.cmd;
			else
				cmd = read8(this.trackDataCurrent);
			if (cmd < 0x80)
			{
				// Note on
				int key = cmd + this.transpose;
				int vel = this.overriding.val(this.trackDataCurrent, &read8, true);
				int len = this.overriding.val(this.trackDataCurrent, &readvl);
				if (this.state[TS_NOTEWAIT])
					this.wait = len;
				if (this.state[TS_TIEBIT])
					this.NoteOnTie(key, vel);
				else
					this.NoteOn(key, vel, len);
			}
			else
			{
				int value;
				switch (cmd)
				{
					//-----------------------------------------------------------------
					// Main commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_OPENTRACK:
					{
						int tNum = read8(this.trackDataCurrent);
						auto trackPos = this.ply.sseq.data[read24(this.trackDataCurrent) .. $];
						int newTrack = this.ply.TrackAlloc();
						if (newTrack != -1)
						{
							this.ply.tracks[newTrack].Init(cast(ubyte)newTrack, this.ply, trackPos, tNum);
							this.ply.trackIds[this.ply.nTracks++] = cast(ubyte)newTrack;
						}
						break;
					}

					case SseqCommand.SSEQ_CMD_REST:
						this.wait = this.overriding.val(this.trackDataCurrent, &readvl);
						break;

					case SseqCommand.SSEQ_CMD_PATCH:
						this.patch = cast(ushort)this.overriding.val(this.trackDataCurrent, &readvl);
						break;

					case SseqCommand.SSEQ_CMD_GOTO:
						this.trackDataCurrent = this.ply.sseq.data[read24(this.trackDataCurrent) .. $];
						break;

					case SseqCommand.SSEQ_CMD_CALL:
						value = read24(this.trackDataCurrent);
						if (this.stackPos < FSS_TRACKSTACKSIZE)
						{
							const(ubyte)[] dest = this.ply.sseq.data[value .. $];
							this.stack[this.stackPos++] = StackValue(StackType.STACKTYPE_CALL, this.trackDataCurrent);
							this.trackDataCurrent = dest;
						}
						break;

					case SseqCommand.SSEQ_CMD_RET:
						if (this.stackPos && this.stack[this.stackPos - 1].type == StackType.STACKTYPE_CALL)
							this.trackDataCurrent = this.stack[--this.stackPos].dest;
						break;

					case SseqCommand.SSEQ_CMD_PAN:
						this.pan = cast(byte)(this.overriding.val(this.trackDataCurrent, &read8) - 64);
						this.updateFlags[TUF_PAN] = true;
						break;

					case SseqCommand.SSEQ_CMD_VOL:
						this.vol = cast(ubyte)this.overriding.val(this.trackDataCurrent, &read8);
						this.updateFlags[TUF_VOL] = true;
						break;

					case SseqCommand.SSEQ_CMD_MASTERVOL:
						this.ply.masterVol = cast(short)Cnv_Sust(this.overriding.val(this.trackDataCurrent, &read8));
						for (ubyte i = 0; i < this.ply.nTracks; ++i)
							this.ply.tracks[this.ply.trackIds[i]].updateFlags[TUF_VOL] = true;
						break;

					case SseqCommand.SSEQ_CMD_PRIO:
						this.prio = cast(ubyte)(this.ply.prio + read8(this.trackDataCurrent));
						// Update here?
						break;

					case SseqCommand.SSEQ_CMD_NOTEWAIT:
						this.state[TS_NOTEWAIT] = !!read8(this.trackDataCurrent);
						break;

					case SseqCommand.SSEQ_CMD_TIE:
						this.state[TS_TIEBIT] = !!read8(this.trackDataCurrent);
						this.ReleaseAllNotes();
						break;

					case SseqCommand.SSEQ_CMD_EXPR:
						this.expr = cast(ubyte)this.overriding.val(this.trackDataCurrent, &read8);
						this.updateFlags[TUF_VOL] = true;
						break;

					case SseqCommand.SSEQ_CMD_TEMPO:
						this.ply.tempo = cast(ushort)read16(this.trackDataCurrent);
						break;

					case SseqCommand.SSEQ_CMD_END:
						this.state[TS_END] = true;
						return;

					case SseqCommand.SSEQ_CMD_LOOPSTART:
						value = this.overriding.val(this.trackDataCurrent, &read8);
						if (this.stackPos < FSS_TRACKSTACKSIZE)
						{
							this.loopCount[this.stackPos] = cast(ubyte)value;
							this.stack[this.stackPos++] = StackValue(StackType.STACKTYPE_LOOP, this.trackDataCurrent);
						}
						break;

					case SseqCommand.SSEQ_CMD_LOOPEND:
						if (this.stackPos && this.stack[this.stackPos - 1].type == StackType.STACKTYPE_LOOP)
						{
							const(ubyte)[] rPos = this.stack[this.stackPos - 1].dest;
							ubyte* nR = &this.loopCount[this.stackPos - 1];
							ubyte prevR = *nR;
							if (!prevR || --*nR)
								this.trackDataCurrent = rPos;
							else
								--this.stackPos;
						}
						break;

					//-----------------------------------------------------------------
					// Tuning commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_TRANSPOSE:
						this.transpose = cast(byte)this.overriding.val(this.trackDataCurrent, &read8);
						break;

					case SseqCommand.SSEQ_CMD_PITCHBEND:
						this.pitchBend = cast(byte)this.overriding.val(this.trackDataCurrent, &read8);
						this.updateFlags[TUF_TIMER] = true;
						break;

					case SseqCommand.SSEQ_CMD_PITCHBENDRANGE:
						this.pitchBendRange = cast(ubyte)read8(this.trackDataCurrent);
						this.updateFlags[TUF_TIMER] = true;
						break;

					//-----------------------------------------------------------------
					// Envelope-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_ATTACK:
						this.a = cast(ubyte)this.overriding.val(this.trackDataCurrent, &read8);
						break;

					case SseqCommand.SSEQ_CMD_DECAY:
						this.d = cast(ubyte)this.overriding.val(this.trackDataCurrent, &read8);
						break;

					case SseqCommand.SSEQ_CMD_SUSTAIN:
						this.s = cast(ubyte)this.overriding.val(this.trackDataCurrent, &read8);
						break;

					case SseqCommand.SSEQ_CMD_RELEASE:
						this.r = cast(ubyte)this.overriding.val(this.trackDataCurrent, &read8);
						break;

					//-----------------------------------------------------------------
					// Portamento-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_PORTAKEY:
						this.portaKey = cast(ubyte)(read8(this.trackDataCurrent) + this.transpose);
						this.state[TS_PORTABIT] = true;
						// Update here?
						break;

					case SseqCommand.SSEQ_CMD_PORTAFLAG:
						this.state[TS_PORTABIT] = !!read8(this.trackDataCurrent);
						// Update here?
						break;

					case SseqCommand.SSEQ_CMD_PORTATIME:
						this.portaTime = cast(ubyte)this.overriding.val(this.trackDataCurrent, &read8);
						// Update here?
						break;

					case SseqCommand.SSEQ_CMD_SWEEPPITCH:
						this.sweepPitch = cast(short)this.overriding.val(this.trackDataCurrent, &read16);
						// Update here?
						break;

					//-----------------------------------------------------------------
					// Modulation-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_MODDEPTH:
						this.modDepth = cast(ubyte)this.overriding.val(this.trackDataCurrent, &read8);
						this.updateFlags[TUF_MOD] = true;
						break;

					case SseqCommand.SSEQ_CMD_MODSPEED:
						this.modSpeed = cast(ubyte)this.overriding.val(this.trackDataCurrent, &read8);
						this.updateFlags[TUF_MOD] = true;
						break;

					case SseqCommand.SSEQ_CMD_MODTYPE:
						this.modType = cast(ubyte)read8(this.trackDataCurrent);
						this.updateFlags[TUF_MOD] = true;
						break;

					case SseqCommand.SSEQ_CMD_MODRANGE:
						this.modRange = cast(ubyte)read8(this.trackDataCurrent);
						this.updateFlags[TUF_MOD] = true;
						break;

					case SseqCommand.SSEQ_CMD_MODDELAY:
						this.modDelay = cast(ushort)this.overriding.val(this.trackDataCurrent, &read16);
						this.updateFlags[TUF_MOD] = true;
						break;

					//-----------------------------------------------------------------
					// Randomness-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_RANDOM:
					{
						this.overriding.overriding = true;
						this.overriding.cmd = read8(this.trackDataCurrent);
						if ((this.overriding.cmd >= SseqCommand.SSEQ_CMD_SETVAR && this.overriding.cmd <= SseqCommand.SSEQ_CMD_CMP_NE) || this.overriding.cmd < 0x80)
							this.overriding.extraValue = read8(this.trackDataCurrent);
						short minVal = cast(short)read16(this.trackDataCurrent);
						short maxVal = cast(short)read16(this.trackDataCurrent);
						this.overriding.value = uniform(0, maxVal - minVal + 1) + minVal;
						break;
					}

					//-----------------------------------------------------------------
					// Variable-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_FROMVAR:
						this.overriding.overriding = true;
						this.overriding.cmd = read8(this.trackDataCurrent);
						if ((this.overriding.cmd >= SseqCommand.SSEQ_CMD_SETVAR && this.overriding.cmd <= SseqCommand.SSEQ_CMD_CMP_NE) || this.overriding.cmd < 0x80)
							this.overriding.extraValue = read8(this.trackDataCurrent);
						this.overriding.value = this.ply.variables[read8(this.trackDataCurrent)];
						break;

					case SseqCommand.SSEQ_CMD_SETVAR:
					case SseqCommand.SSEQ_CMD_ADDVAR:
					case SseqCommand.SSEQ_CMD_SUBVAR:
					case SseqCommand.SSEQ_CMD_MULVAR:
					case SseqCommand.SSEQ_CMD_DIVVAR:
					case SseqCommand.SSEQ_CMD_SHIFTVAR:
					case SseqCommand.SSEQ_CMD_RANDVAR:
					{
						byte varNo = cast(byte)this.overriding.val(this.trackDataCurrent, &read8, true);
						value = this.overriding.val(this.trackDataCurrent, &read16);
						if (cmd == SseqCommand.SSEQ_CMD_DIVVAR && !value) // Division by 0, skip it to prevent crashing
						break;
						this.ply.variables[varNo] = VarFunc(cmd)(this.ply.variables[varNo], cast(short)value);
						break;
					}

					//-----------------------------------------------------------------
					// Conditional-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_CMP_EQ:
					case SseqCommand.SSEQ_CMD_CMP_GE:
					case SseqCommand.SSEQ_CMD_CMP_GT:
					case SseqCommand.SSEQ_CMD_CMP_LE:
					case SseqCommand.SSEQ_CMD_CMP_LT:
					case SseqCommand.SSEQ_CMD_CMP_NE:
					{
						byte varNo = cast(byte)this.overriding.val(this.trackDataCurrent, &read8, true);
						value = this.overriding.val(this.trackDataCurrent, &read16);
						this.lastComparisonResult = CompareFunc(cmd)(this.ply.variables[varNo], cast(short)value);
						break;
					}

					case SseqCommand.SSEQ_CMD_IF:
						if (!this.lastComparisonResult)
						{
							int nextCmd = read8(this.trackDataCurrent);
							ubyte cmdBytes = SseqCommandByteCount(nextCmd);
							bool variableBytes = !!(cmdBytes & VariableByteCount);
							bool extraByte = !!(cmdBytes & ExtraByteOnNoteOrVarOrCmp);
							cmdBytes &= ~(VariableByteCount | ExtraByteOnNoteOrVarOrCmp);
							if (extraByte)
							{
								int extraCmd = read8(this.trackDataCurrent);
								if ((extraCmd >= SseqCommand.SSEQ_CMD_SETVAR && extraCmd <= SseqCommand.SSEQ_CMD_CMP_NE) || extraCmd < 0x80)
									++cmdBytes;
							}
							this.trackDataCurrent = this.trackDataCurrent[cmdBytes .. $];
							if (variableBytes)
								readvl(this.trackDataCurrent);
						}
						break;

					default:
						this.trackDataCurrent = this.trackDataCurrent[SseqCommandByteCount(cmd) .. $];
				}
			}

			if (cmd != SseqCommand.SSEQ_CMD_RANDOM && cmd != SseqCommand.SSEQ_CMD_FROMVAR)
				this.overriding.overriding = false;
		}
	}
}


enum SseqCommand
{
	SSEQ_CMD_ALLOCTRACK = 0xFE, // Silently ignored
	SSEQ_CMD_OPENTRACK = 0x93,

	SSEQ_CMD_REST = 0x80,
	SSEQ_CMD_PATCH = 0x81,
	SSEQ_CMD_PAN = 0xC0,
	SSEQ_CMD_VOL = 0xC1,
	SSEQ_CMD_MASTERVOL = 0xC2,
	SSEQ_CMD_PRIO = 0xC6,
	SSEQ_CMD_NOTEWAIT = 0xC7,
	SSEQ_CMD_TIE = 0xC8,
	SSEQ_CMD_EXPR = 0xD5,
	SSEQ_CMD_TEMPO = 0xE1,
	SSEQ_CMD_END = 0xFF,

	SSEQ_CMD_GOTO = 0x94,
	SSEQ_CMD_CALL = 0x95,
	SSEQ_CMD_RET = 0xFD,
	SSEQ_CMD_LOOPSTART = 0xD4,
	SSEQ_CMD_LOOPEND = 0xFC,

	SSEQ_CMD_TRANSPOSE = 0xC3,
	SSEQ_CMD_PITCHBEND = 0xC4,
	SSEQ_CMD_PITCHBENDRANGE = 0xC5,

	SSEQ_CMD_ATTACK = 0xD0,
	SSEQ_CMD_DECAY = 0xD1,
	SSEQ_CMD_SUSTAIN = 0xD2,
	SSEQ_CMD_RELEASE = 0xD3,

	SSEQ_CMD_PORTAKEY = 0xC9,
	SSEQ_CMD_PORTAFLAG = 0xCE,
	SSEQ_CMD_PORTATIME = 0xCF,
	SSEQ_CMD_SWEEPPITCH = 0xE3,

	SSEQ_CMD_MODDEPTH = 0xCA,
	SSEQ_CMD_MODSPEED = 0xCB,
	SSEQ_CMD_MODTYPE = 0xCC,
	SSEQ_CMD_MODRANGE = 0xCD,
	SSEQ_CMD_MODDELAY = 0xE0,

	SSEQ_CMD_RANDOM = 0xA0,
	SSEQ_CMD_PRINTVAR = 0xD6,
	SSEQ_CMD_IF = 0xA2,
	SSEQ_CMD_FROMVAR = 0xA1,
	SSEQ_CMD_SETVAR = 0xB0,
	SSEQ_CMD_ADDVAR = 0xB1,
	SSEQ_CMD_SUBVAR = 0xB2,
	SSEQ_CMD_MULVAR = 0xB3,
	SSEQ_CMD_DIVVAR = 0xB4,
	SSEQ_CMD_SHIFTVAR = 0xB5,
	SSEQ_CMD_RANDVAR = 0xB6,
	SSEQ_CMD_CMP_EQ = 0xB8,
	SSEQ_CMD_CMP_GE = 0xB9,
	SSEQ_CMD_CMP_GT = 0xBA,
	SSEQ_CMD_CMP_LE = 0xBB,
	SSEQ_CMD_CMP_LT = 0xBC,
	SSEQ_CMD_CMP_NE = 0xBD,

	SSEQ_CMD_MUTE = 0xD7 // Unsupported
};

static const ubyte VariableByteCount = 1 << 7;
static const ubyte ExtraByteOnNoteOrVarOrCmp = 1 << 6;

static ubyte SseqCommandByteCount(int cmd) @safe
{
	if (cmd < 0x80)
		return 1 | VariableByteCount;
	else
		switch (cmd)
		{
			case SseqCommand.SSEQ_CMD_REST:
			case SseqCommand.SSEQ_CMD_PATCH:
				return VariableByteCount;

			case SseqCommand.SSEQ_CMD_PAN:
			case SseqCommand.SSEQ_CMD_VOL:
			case SseqCommand.SSEQ_CMD_MASTERVOL:
			case SseqCommand.SSEQ_CMD_PRIO:
			case SseqCommand.SSEQ_CMD_NOTEWAIT:
			case SseqCommand.SSEQ_CMD_TIE:
			case SseqCommand.SSEQ_CMD_EXPR:
			case SseqCommand.SSEQ_CMD_LOOPSTART:
			case SseqCommand.SSEQ_CMD_TRANSPOSE:
			case SseqCommand.SSEQ_CMD_PITCHBEND:
			case SseqCommand.SSEQ_CMD_PITCHBENDRANGE:
			case SseqCommand.SSEQ_CMD_ATTACK:
			case SseqCommand.SSEQ_CMD_DECAY:
			case SseqCommand.SSEQ_CMD_SUSTAIN:
			case SseqCommand.SSEQ_CMD_RELEASE:
			case SseqCommand.SSEQ_CMD_PORTAKEY:
			case SseqCommand.SSEQ_CMD_PORTAFLAG:
			case SseqCommand.SSEQ_CMD_PORTATIME:
			case SseqCommand.SSEQ_CMD_MODDEPTH:
			case SseqCommand.SSEQ_CMD_MODSPEED:
			case SseqCommand.SSEQ_CMD_MODTYPE:
			case SseqCommand.SSEQ_CMD_MODRANGE:
			case SseqCommand.SSEQ_CMD_PRINTVAR:
			case SseqCommand.SSEQ_CMD_MUTE:
				return 1;

			case SseqCommand.SSEQ_CMD_ALLOCTRACK:
			case SseqCommand.SSEQ_CMD_TEMPO:
			case SseqCommand.SSEQ_CMD_SWEEPPITCH:
			case SseqCommand.SSEQ_CMD_MODDELAY:
				return 2;

			case SseqCommand.SSEQ_CMD_GOTO:
			case SseqCommand.SSEQ_CMD_CALL:
			case SseqCommand.SSEQ_CMD_SETVAR:
			case SseqCommand.SSEQ_CMD_ADDVAR:
			case SseqCommand.SSEQ_CMD_SUBVAR:
			case SseqCommand.SSEQ_CMD_MULVAR:
			case SseqCommand.SSEQ_CMD_DIVVAR:
			case SseqCommand.SSEQ_CMD_SHIFTVAR:
			case SseqCommand.SSEQ_CMD_RANDVAR:
			case SseqCommand.SSEQ_CMD_CMP_EQ:
			case SseqCommand.SSEQ_CMD_CMP_GE:
			case SseqCommand.SSEQ_CMD_CMP_GT:
			case SseqCommand.SSEQ_CMD_CMP_LE:
			case SseqCommand.SSEQ_CMD_CMP_LT:
			case SseqCommand.SSEQ_CMD_CMP_NE:
				return 3;

			case SseqCommand.SSEQ_CMD_OPENTRACK:
				return 4;

			case SseqCommand.SSEQ_CMD_FROMVAR:
				return 1 | ExtraByteOnNoteOrVarOrCmp; // Technically 2 bytes with an additional 1, leaving 1 off because we will be reading it to determine if the additional byte is needed

			case SseqCommand.SSEQ_CMD_RANDOM:
				return 4 | ExtraByteOnNoteOrVarOrCmp; // Technically 5 bytes with an additional 1, leaving 1 off because we will be reading it to determine if the additional byte is needed

			default:
				return 0;
		}
}

private short varFuncSet(short, short value) @safe { return value; };
private short varFuncAdd(short var, short value) @safe { return cast(short)(var + value); };
private short varFuncSub(short var, short value) @safe { return cast(short)(var - value); };
private short varFuncMul(short var, short value) @safe { return cast(short)(var * value); };
private short varFuncDiv(short var, short value) @safe { return cast(short)(var / value); };
private short varFuncShift(short var, short value) @safe
{
	if (value < 0)
		return var >> -value;
	else
		return cast(short)(var << value);
};
private short varFuncRand(short, short value) @safe {
	if (value < 0)
		return cast(short)(-uniform(0, -value + 1));
	else
		return cast(short)uniform(0, value + 1);
};

private short function(short, short) @safe VarFunc(int cmd) @safe
{
	switch (cmd)
	{
		case SseqCommand.SSEQ_CMD_SETVAR:
			return &varFuncSet;
		case SseqCommand.SSEQ_CMD_ADDVAR:
			return &varFuncAdd;
		case SseqCommand.SSEQ_CMD_SUBVAR:
			return &varFuncSub;
		case SseqCommand.SSEQ_CMD_MULVAR:
			return &varFuncMul;
		case SseqCommand.SSEQ_CMD_DIVVAR:
			return &varFuncDiv;
		case SseqCommand.SSEQ_CMD_SHIFTVAR:
			return &varFuncShift;
		case SseqCommand.SSEQ_CMD_RANDVAR:
			return &varFuncRand;
		default:
			return null;
	}
}

private bool compareFuncEq(short a, short b) @safe { return a == b; }
private bool compareFuncGe(short a, short b) @safe { return a >= b; }
private bool compareFuncGt(short a, short b) @safe { return a > b; }
private bool compareFuncLe(short a, short b) @safe { return a <= b; }
private bool compareFuncLt(short a, short b) @safe { return a < b; }
private bool compareFuncNe(short a, short b) @safe { return a != b; }

private bool function(short, short) @safe CompareFunc(int cmd) @safe
{
	switch (cmd)
	{
		case SseqCommand.SSEQ_CMD_CMP_EQ:
			return &compareFuncEq;
		case SseqCommand.SSEQ_CMD_CMP_GE:
			return &compareFuncGe;
		case SseqCommand.SSEQ_CMD_CMP_GT:
			return &compareFuncGt;
		case SseqCommand.SSEQ_CMD_CMP_LE:
			return &compareFuncLe;
		case SseqCommand.SSEQ_CMD_CMP_LT:
			return &compareFuncLt;
		case SseqCommand.SSEQ_CMD_CMP_NE:
			return &compareFuncNe;
		default:
			return null;
	}
}
