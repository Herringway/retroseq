module sseq.player;

import sseq.common;
import sseq.sseq;
import sseq.sbnk;
import sseq.track;
import sseq.channel;
import sseq.sdat;
import sseq.consts;

import std.math;
import std.random;

struct Player
{
	ubyte prio, nTracks;
	ushort tempo, tempoCount, tempoRate /* 8.8 fixed point */;
	short masterVol, sseqVol;

	const(Song)* song;

	ubyte[FSS_TRACKCOUNT] trackIds;
	Track[FSS_MAXTRACKS] tracks;
	Channel[16] channels;
	short[32] variables = -1;

	uint sampleRate;
	Interpolation interpolation;

	bool Setup(const Song song) {
		for (size_t i = 0; i < 16; ++i)
		{
			this.channels[i].initialize();
			this.channels[i].chnId = cast(byte)i;
		}
		this.song = &[song][0];

		int firstTrack = this.TrackAlloc();
		if (firstTrack == -1)
			return false;
		this.tracks[firstTrack].Init(cast(ubyte)firstTrack, song.sseq.data, 0);

		this.nTracks = 1;
		this.trackIds[0] = cast(ubyte)firstTrack;

		this.secondsPerSample = 1.0 / this.sampleRate;

		this.ClearState();

		return true;
	}
	void ClearState() {
		this.tempo = 120;
		this.tempoCount = 0;
		this.tempoRate = 0x100;
		this.masterVol = 0; // this is actually the highest level
		this.variables = -1;
		this.secondsIntoPlayback = 0;
		this.secondsUntilNextClock = SecondsPerClockCycle;
	}
	void FreeTracks() {
		for (ubyte i = 0; i < this.nTracks; ++i)
			this.tracks[this.trackIds[i]].Free();
		this.nTracks = 0;
	}
	void Stop(bool bKillSound) {
		this.ClearState();
		for (ubyte i = 0; i < this.nTracks; ++i)
		{
			ubyte trackId = this.trackIds[i];
			this.tracks[trackId].ClearState();
			this.tracks[trackId].prio += this.prio;
			for (int j = 0; j < 16; ++j)
			{
				Channel* chn = &this.channels[j];
				if (chn.state != CS_NONE && chn.trackId == trackId)
				{
					if (bKillSound)
						chn.Kill();
					else
						chn.Release();
				}
			}
		}
		this.FreeTracks();
	}
	int ChannelAlloc(int type, int priority) @safe {

		static immutable ubyte[] pcmChnArray = [ 4, 5, 6, 7, 2, 0, 3, 1, 8, 9, 10, 11, 14, 12, 15, 13 ];
		static immutable ubyte[] psgChnArray = [ 8, 9, 10, 11, 12, 13 ];
		static immutable ubyte[] noiseChnArray = [ 14, 15 ];
		static immutable ubyte[] arraySizes = [ pcmChnArray.sizeof, psgChnArray.sizeof, noiseChnArray.sizeof ];
		static immutable ubyte[][] arrayArray = [ pcmChnArray, psgChnArray, noiseChnArray ];

		auto chnArray = arrayArray[type];
		int arraySize = arraySizes[type];

		int curChnNo = -1;
		for (int i = 0; i < arraySize; ++i)
		{
			int thisChnNo = chnArray[i];
			Channel* thisChn = &this.channels[thisChnNo];
			if (curChnNo != -1) {
				Channel* curChn = &this.channels[curChnNo];
				if (thisChn.prio >= curChn.prio)
				{
					if (thisChn.prio != curChn.prio)
						continue;
					if (curChn.vol <= thisChn.vol)
						continue;
				}
			}
			curChnNo = thisChnNo;
		}

		if (curChnNo == -1 || priority < this.channels[curChnNo].prio)
			return -1;
		this.channels[curChnNo].noteLength = -1;
		this.channels[curChnNo].vol = 0x7FF;
		this.channels[curChnNo].clearHistory();
		return curChnNo;
	}
	int TrackAlloc() @safe {
		for (int i = 0; i < FSS_MAXTRACKS; ++i)
		{
			Track* thisTrk = &this.tracks[i];
			if (!thisTrk.state[TS_ALLOCBIT])
			{
				thisTrk.Zero();
				thisTrk.state[TS_ALLOCBIT] = true;
				thisTrk.updateFlags = false;
				return i;
			}
		}
		return -1;
	}
	void Run() @safe {
		while (this.tempoCount >= 240)
		{
			this.tempoCount -= 240;
			for (ubyte i = 0; i < this.nTracks; ++i)
				runTrack(this.trackIds[i]);
				//this.tracks[this.trackIds[i]].Run();
		}
		this.tempoCount += (cast(int)(this.tempo) * cast(int)(this.tempoRate)) >> 8;
	}
	void runTrack(int trackID) @safe {
		auto track = &this.tracks[trackID];
		// Indicate "heartbeat" for this track
		track.updateFlags[TUF_LEN] = true;

		// Exit if the track has already ended
		if (track.state[TS_END])
			return;

		if (track.wait)
		{
			--track.wait;
			if (track.wait)
				return;
		}

		while (!track.wait)
		{
			int cmd;
			if (track.overriding.overriding)
				cmd = track.overriding.cmd;
			else
				cmd = read8(track.trackDataCurrent);
			if (cmd < 0x80)
			{
				// Note on
				int key = cmd + track.transpose;
				int vel = track.overriding.val(track.trackDataCurrent, &read8, true);
				int len = track.overriding.val(track.trackDataCurrent, &readvl);
				if (track.state[TS_NOTEWAIT])
					track.wait = len;
				if (track.state[TS_TIEBIT])
					NoteOnTie(*track, key, vel);
				else
					NoteOn(*track, key, vel, len);
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
						int tNum = read8(track.trackDataCurrent);
						auto trackPos = this.song.sseq.data[read24(track.trackDataCurrent) .. $];
						int newTrack = this.TrackAlloc();
						if (newTrack != -1)
						{
							this.tracks[newTrack].Init(cast(ubyte)newTrack, trackPos, tNum);
							this.trackIds[this.nTracks++] = cast(ubyte)newTrack;
						}
						break;
					}

					case SseqCommand.SSEQ_CMD_REST:
						track.wait = track.overriding.val(track.trackDataCurrent, &readvl);
						break;

					case SseqCommand.SSEQ_CMD_PATCH:
						track.patch = cast(ushort)track.overriding.val(track.trackDataCurrent, &readvl);
						break;

					case SseqCommand.SSEQ_CMD_GOTO:
						track.trackDataCurrent = this.song.sseq.data[read24(track.trackDataCurrent) .. $];
						break;

					case SseqCommand.SSEQ_CMD_CALL:
						value = read24(track.trackDataCurrent);
						if (track.stackPos < FSS_TRACKSTACKSIZE)
						{
							const(ubyte)[] dest = this.song.sseq.data[value .. $];
							track.stack[track.stackPos++] = StackValue(StackType.STACKTYPE_CALL, track.trackDataCurrent);
							track.trackDataCurrent = dest;
						}
						break;

					case SseqCommand.SSEQ_CMD_RET:
						if (track.stackPos && track.stack[track.stackPos - 1].type == StackType.STACKTYPE_CALL)
							track.trackDataCurrent = track.stack[--track.stackPos].dest;
						break;

					case SseqCommand.SSEQ_CMD_PAN:
						track.pan = cast(byte)(track.overriding.val(track.trackDataCurrent, &read8) - 64);
						track.updateFlags[TUF_PAN] = true;
						break;

					case SseqCommand.SSEQ_CMD_VOL:
						track.vol = cast(ubyte)track.overriding.val(track.trackDataCurrent, &read8);
						track.updateFlags[TUF_VOL] = true;
						break;

					case SseqCommand.SSEQ_CMD_MASTERVOL:
						this.masterVol = cast(short)Cnv_Sust(track.overriding.val(track.trackDataCurrent, &read8));
						for (ubyte i = 0; i < this.nTracks; ++i)
							this.tracks[this.trackIds[i]].updateFlags[TUF_VOL] = true;
						break;

					case SseqCommand.SSEQ_CMD_PRIO:
						track.prio = cast(ubyte)(this.prio + read8(track.trackDataCurrent));
						// Update here?
						break;

					case SseqCommand.SSEQ_CMD_NOTEWAIT:
						track.state[TS_NOTEWAIT] = !!read8(track.trackDataCurrent);
						break;

					case SseqCommand.SSEQ_CMD_TIE:
						track.state[TS_TIEBIT] = !!read8(track.trackDataCurrent);
						ReleaseAllNotes(*track);
						break;

					case SseqCommand.SSEQ_CMD_EXPR:
						track.expr = cast(ubyte)track.overriding.val(track.trackDataCurrent, &read8);
						track.updateFlags[TUF_VOL] = true;
						break;

					case SseqCommand.SSEQ_CMD_TEMPO:
						this.tempo = cast(ushort)read16(track.trackDataCurrent);
						break;

					case SseqCommand.SSEQ_CMD_END:
						track.state[TS_END] = true;
						return;

					case SseqCommand.SSEQ_CMD_LOOPSTART:
						value = track.overriding.val(track.trackDataCurrent, &read8);
						if (track.stackPos < FSS_TRACKSTACKSIZE)
						{
							track.loopCount[track.stackPos] = cast(ubyte)value;
							track.stack[track.stackPos++] = StackValue(StackType.STACKTYPE_LOOP, track.trackDataCurrent);
						}
						break;

					case SseqCommand.SSEQ_CMD_LOOPEND:
						if (track.stackPos && track.stack[track.stackPos - 1].type == StackType.STACKTYPE_LOOP)
						{
							const(ubyte)[] rPos = track.stack[track.stackPos - 1].dest;
							ubyte* nR = &track.loopCount[track.stackPos - 1];
							ubyte prevR = *nR;
							if (!prevR || --*nR)
								track.trackDataCurrent = rPos;
							else
								--track.stackPos;
						}
						break;

					//-----------------------------------------------------------------
					// Tuning commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_TRANSPOSE:
						track.transpose = cast(byte)track.overriding.val(track.trackDataCurrent, &read8);
						break;

					case SseqCommand.SSEQ_CMD_PITCHBEND:
						track.pitchBend = cast(byte)track.overriding.val(track.trackDataCurrent, &read8);
						track.updateFlags[TUF_TIMER] = true;
						break;

					case SseqCommand.SSEQ_CMD_PITCHBENDRANGE:
						track.pitchBendRange = cast(ubyte)read8(track.trackDataCurrent);
						track.updateFlags[TUF_TIMER] = true;
						break;

					//-----------------------------------------------------------------
					// Envelope-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_ATTACK:
						track.a = cast(ubyte)track.overriding.val(track.trackDataCurrent, &read8);
						break;

					case SseqCommand.SSEQ_CMD_DECAY:
						track.d = cast(ubyte)track.overriding.val(track.trackDataCurrent, &read8);
						break;

					case SseqCommand.SSEQ_CMD_SUSTAIN:
						track.s = cast(ubyte)track.overriding.val(track.trackDataCurrent, &read8);
						break;

					case SseqCommand.SSEQ_CMD_RELEASE:
						track.r = cast(ubyte)track.overriding.val(track.trackDataCurrent, &read8);
						break;

					//-----------------------------------------------------------------
					// Portamento-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_PORTAKEY:
						track.portaKey = cast(ubyte)(read8(track.trackDataCurrent) + track.transpose);
						track.state[TS_PORTABIT] = true;
						// Update here?
						break;

					case SseqCommand.SSEQ_CMD_PORTAFLAG:
						track.state[TS_PORTABIT] = !!read8(track.trackDataCurrent);
						// Update here?
						break;

					case SseqCommand.SSEQ_CMD_PORTATIME:
						track.portaTime = cast(ubyte)track.overriding.val(track.trackDataCurrent, &read8);
						// Update here?
						break;

					case SseqCommand.SSEQ_CMD_SWEEPPITCH:
						track.sweepPitch = cast(short)track.overriding.val(track.trackDataCurrent, &read16);
						// Update here?
						break;

					//-----------------------------------------------------------------
					// Modulation-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_MODDEPTH:
						track.modDepth = cast(ubyte)track.overriding.val(track.trackDataCurrent, &read8);
						track.updateFlags[TUF_MOD] = true;
						break;

					case SseqCommand.SSEQ_CMD_MODSPEED:
						track.modSpeed = cast(ubyte)track.overriding.val(track.trackDataCurrent, &read8);
						track.updateFlags[TUF_MOD] = true;
						break;

					case SseqCommand.SSEQ_CMD_MODTYPE:
						track.modType = cast(ubyte)read8(track.trackDataCurrent);
						track.updateFlags[TUF_MOD] = true;
						break;

					case SseqCommand.SSEQ_CMD_MODRANGE:
						track.modRange = cast(ubyte)read8(track.trackDataCurrent);
						track.updateFlags[TUF_MOD] = true;
						break;

					case SseqCommand.SSEQ_CMD_MODDELAY:
						track.modDelay = cast(ushort)track.overriding.val(track.trackDataCurrent, &read16);
						track.updateFlags[TUF_MOD] = true;
						break;

					//-----------------------------------------------------------------
					// Randomness-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_RANDOM:
					{
						track.overriding.overriding = true;
						track.overriding.cmd = read8(track.trackDataCurrent);
						if ((track.overriding.cmd >= SseqCommand.SSEQ_CMD_SETVAR && track.overriding.cmd <= SseqCommand.SSEQ_CMD_CMP_NE) || track.overriding.cmd < 0x80)
							track.overriding.extraValue = read8(track.trackDataCurrent);
						short minVal = cast(short)read16(track.trackDataCurrent);
						short maxVal = cast(short)read16(track.trackDataCurrent);
						track.overriding.value = uniform(0, maxVal - minVal + 1) + minVal;
						break;
					}

					//-----------------------------------------------------------------
					// Variable-related commands
					//-----------------------------------------------------------------

					case SseqCommand.SSEQ_CMD_FROMVAR:
						track.overriding.overriding = true;
						track.overriding.cmd = read8(track.trackDataCurrent);
						if ((track.overriding.cmd >= SseqCommand.SSEQ_CMD_SETVAR && track.overriding.cmd <= SseqCommand.SSEQ_CMD_CMP_NE) || track.overriding.cmd < 0x80)
							track.overriding.extraValue = read8(track.trackDataCurrent);
						track.overriding.value = this.variables[read8(track.trackDataCurrent)];
						break;

					case SseqCommand.SSEQ_CMD_SETVAR:
					case SseqCommand.SSEQ_CMD_ADDVAR:
					case SseqCommand.SSEQ_CMD_SUBVAR:
					case SseqCommand.SSEQ_CMD_MULVAR:
					case SseqCommand.SSEQ_CMD_DIVVAR:
					case SseqCommand.SSEQ_CMD_SHIFTVAR:
					case SseqCommand.SSEQ_CMD_RANDVAR:
					{
						byte varNo = cast(byte)track.overriding.val(track.trackDataCurrent, &read8, true);
						value = track.overriding.val(track.trackDataCurrent, &read16);
						if (cmd == SseqCommand.SSEQ_CMD_DIVVAR && !value) // Division by 0, skip it to prevent crashing
						break;
						this.variables[varNo] = VarFunc(cmd)(this.variables[varNo], cast(short)value);
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
						byte varNo = cast(byte)track.overriding.val(track.trackDataCurrent, &read8, true);
						value = track.overriding.val(track.trackDataCurrent, &read16);
						track.lastComparisonResult = CompareFunc(cmd)(this.variables[varNo], cast(short)value);
						break;
					}

					case SseqCommand.SSEQ_CMD_IF:
						if (!track.lastComparisonResult)
						{
							int nextCmd = read8(track.trackDataCurrent);
							ubyte cmdBytes = SseqCommandByteCount(nextCmd);
							bool variableBytes = !!(cmdBytes & VariableByteCount);
							bool extraByte = !!(cmdBytes & ExtraByteOnNoteOrVarOrCmp);
							cmdBytes &= ~(VariableByteCount | ExtraByteOnNoteOrVarOrCmp);
							if (extraByte)
							{
								int extraCmd = read8(track.trackDataCurrent);
								if ((extraCmd >= SseqCommand.SSEQ_CMD_SETVAR && extraCmd <= SseqCommand.SSEQ_CMD_CMP_NE) || extraCmd < 0x80)
									++cmdBytes;
							}
							track.trackDataCurrent = track.trackDataCurrent[cmdBytes .. $];
							if (variableBytes)
								readvl(track.trackDataCurrent);
						}
						break;

					default:
						track.trackDataCurrent = track.trackDataCurrent[SseqCommandByteCount(cmd) .. $];
				}
			}

			if (cmd != SseqCommand.SSEQ_CMD_RANDOM && cmd != SseqCommand.SSEQ_CMD_FROMVAR)
				track.overriding.overriding = false;
		}
	}
	void UpdateTracks() @safe {
		for (int i = 0; i < 16; ++i)
			UpdateTrack(this.channels[i]);
		for (int i = 0; i < FSS_MAXTRACKS; ++i)
			this.tracks[i].updateFlags = false;
	}
	void UpdateTrack(ref Channel channel) @safe {
		int trkn = channel.trackId;
		if (trkn == -1)
			return;

		auto trk = &this.tracks[trkn];
		auto trackFlags = trk.updateFlags;
		//if (trackFlags.none())
		//	return;

		if (trackFlags[TUF_LEN])
		{
			int st = channel.state;
			if (st > CS_START)
			{
				if (st < CS_RELEASE && !--channel.noteLength)
					channel.Release();
				if (channel.manualSweep && channel.sweepCnt < channel.sweepLen)
					++channel.sweepCnt;
			}
		}
		if (trackFlags[TUF_VOL])
		{
			this.UpdateVol(*trk, channel);
			channel.flags[CF_UPDVOL] = true;
		}
		if (trackFlags[TUF_PAN])
		{
			this.UpdatePan(*trk, channel);
			channel.flags[CF_UPDPAN] = true;
		}
		if (trackFlags[TUF_TIMER])
		{
			this.UpdateTune(*trk, channel);
			channel.flags[CF_UPDTMR] = true;
		}
		if (trackFlags[TUF_MOD])
		{
			int oldType = channel.modType;
			int newType = trk.modType;
			this.UpdateMod(*trk, channel);
			if (oldType != newType)
			{
				channel.flags[getModFlag(oldType)] = true;
				channel.flags[getModFlag(newType)] = true;
			}
		}
	}
	void ReleaseAllNotes(ref Track track) @safe {
		for (int i = 0; i < 16; ++i)
		{
			Channel* chn = &this.channels[i];
			if (chn.state > CS_NONE && chn.trackId == track.trackId && chn.state != CS_RELEASE)
				chn.Release();
		}
	}
	int NoteOn(ref Track track, int key, int vel, int len) @safe {
		auto sbnk = this.song.sbnk;

		if (track.patch >= sbnk.instruments.length)
			return -1;

		bool bIsPCM = true;
		Channel *chn = null;
		int nCh = -1;

		auto instrument = &sbnk.instruments[track.patch];
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
				nCh = this.ChannelAlloc(TYPE_NOISE, track.prio);
				if (nCh < 0)
					return -1;
				chn = &this.channels[nCh];
				chn.tempReg.CR = SOUND_FORMAT_PSG | SCHANNEL_ENABLE;
			}
			else
			{
				nCh = this.ChannelAlloc(TYPE_PSG, track.prio);
				if (nCh < 0)
					return -1;
				chn = &this.channels[nCh];
				chn.tempReg.CR = SOUND_FORMAT_PSG | SCHANNEL_ENABLE | SOUND_DUTY(noteDef.swav & 0x7);
			}
			chn.tempReg.TIMER = cast(short)-SOUND_FREQ(262 * 8); // key #60 (C4)
			chn.reg.samplePosition = -1;
			chn.reg.psgX = 0x7FFF;
		}

		if (bIsPCM)
		{
			nCh = this.ChannelAlloc(TYPE_PCM, track.prio);
			if (nCh < 0)
				return -1;
			chn = &this.channels[nCh];

			auto swav = &this.song.swar[noteDef.swar].swavs[noteDef.swav];
			chn.tempReg.CR = SOUND_FORMAT(swav.waveType & 3) | SOUND_LOOP(!!swav.loop) | SCHANNEL_ENABLE;
			chn.tempReg.SOURCE = swav;
			chn.tempReg.TIMER = swav.time;
			chn.tempReg.REPEAT_POINT = swav.loopOffset;
			chn.tempReg.LENGTH = swav.nonLoopLength;
			chn.reg.samplePosition = -3;
		}

		chn.state = CS_START;
		chn.trackId = track.trackId;
		chn.flags = false;
		chn.prio = track.prio;
		chn.key = cast(ubyte)key;
		chn.orgKey = noteDef.noteNumber;
		chn.velocity = cast(short)Cnv_Sust(vel);
		chn.pan = cast(byte)(cast(int)(noteDef.pan) - 64);
		chn.modDelayCnt = 0;
		chn.modCounter = 0;
		chn.noteLength = len;
		chn.reg.sampleIncrease = 0;

		chn.attackLvl = cast(ubyte)Cnv_Attack(track.a == 0xFF ? noteDef.attackRate : track.a);
		chn.decayRate = cast(ushort)Cnv_Fall(track.d == 0xFF ? noteDef.decayRate : track.d);
		chn.sustainLvl = track.s == 0xFF ? noteDef.sustainLevel : track.s;
		chn.releaseRate = cast(ushort)Cnv_Fall(track.r == 0xFF ? noteDef.releaseRate : track.r);

		this.UpdateVol(track, *chn);
		this.UpdatePan(track, *chn);
		this.UpdateTune(track, *chn);
		this.UpdateMod(track, *chn);
		this.UpdatePorta(track, *chn);

		track.portaKey = cast(ubyte)key;

		return nCh;
	}
	int NoteOnTie(ref Track track, int key, int vel) @safe {
		// Find an existing note
		int i;
		Channel *chn = null;
		for (i = 0; i < 16; ++i)
		{
			chn = &this.channels[i];
			if (chn.state > CS_NONE && chn.trackId == track.trackId && chn.state != CS_RELEASE)
				break;
		}

		if (i == 16)
			// Can't find note . create an endless one
			return NoteOn(track, key, vel, -1);

		chn.flags = false;
		chn.prio = track.prio;
		chn.key = cast(ubyte)key;
		chn.velocity = cast(short)Cnv_Sust(vel);
		chn.modDelayCnt = 0;
		chn.modCounter = 0;

		this.UpdateVol(track, *chn);
		//this.UpdatePan(track, *chn);
		this.UpdateTune(track, *chn);
		this.UpdateMod(track, *chn);
		this.UpdatePorta(track, *chn);

		track.portaKey = cast(ubyte)key;
		chn.flags[CF_UPDTMR] = true;

		return i;
	}
	void Timer() @safe {
		this.UpdateTracks();

		for (int i = 0; i < 16; ++i)
			UpdateChannel(this.channels[i]);

		this.Run();
	}

	/* Playback helper */
	double secondsPerSample, secondsIntoPlayback, secondsUntilNextClock;
	bool[16] mutes;
	void GenerateSamples(short[2][] buf) @safe {
		uint offset;
		const mute = this.mutes;

		for (uint smpl = 0; smpl < buf.length; ++smpl)
		{
			this.secondsIntoPlayback += this.secondsPerSample;

			int leftChannel = 0, rightChannel = 0;

			// I need to advance the sound channels here
			for (int i = 0; i < 16; ++i)
			{
				Channel* chn = &this.channels[i];

				if (chn.state > CS_NONE)
				{
					int sample = GenerateSample(*chn);
					chn.IncrementSample();

					if (mute[i])
						continue;

					ubyte datashift = chn.reg.volumeDiv;
					if (datashift == 3)
						datashift = 4;
					sample = muldiv7(sample, chn.reg.volumeMul) >> datashift;

					leftChannel += muldiv7(sample, cast(ubyte)(127 - chn.reg.panning));
					rightChannel += muldiv7(sample, chn.reg.panning);
				}
			}

			clamp(leftChannel, -0x8000, 0x7FFF);
			clamp(rightChannel, -0x8000, 0x7FFF);

			buf[offset++] = [cast(short)leftChannel, cast(short)rightChannel];

			if (this.secondsIntoPlayback > this.secondsUntilNextClock)
			{
				this.Timer();
				this.secondsUntilNextClock += SecondsPerClockCycle;
			}
		}
	}
	void UpdateVol(const Track track, ref Channel channel) const @safe {
		int finalVol = masterVol;
		finalVol += sseqVol;
		finalVol += Cnv_Sust(track.vol);
		finalVol += Cnv_Sust(track.expr);
		if (finalVol < -AMPL_K)
			finalVol = -AMPL_K;
		channel.extAmpl = cast(short)finalVol;
	}
	void UpdatePan(const Track trk, ref Channel channel) const @safe {
		channel.extPan = trk.pan;
	}
	void UpdateTune(const Track trk, ref Channel channel) const @safe {
		int tune = (cast(int)(channel.key) - cast(int)(channel.orgKey)) * 64;
		tune += (cast(int)(trk.pitchBend) * cast(int)(trk.pitchBendRange)) >> 1;
		channel.extTune = tune;
	}
	void UpdateMod(const Track trk, ref Channel channel) const @safe {
		channel.modType = trk.modType;
		channel.modSpeed = trk.modSpeed;
		channel.modDepth = trk.modDepth;
		channel.modRange = trk.modRange;
		channel.modDelay = trk.modDelay;
	}
	void UpdatePorta(const Track trk, ref Channel channel) const @safe {
		channel.manualSweep = false;
		channel.sweepPitch = trk.sweepPitch;
		channel.sweepCnt = 0;
		if (!trk.state[TS_PORTABIT])
		{
			channel.sweepLen = 0;
			return;
		}

		int diff = (cast(int)(trk.portaKey) - cast(int)(channel.key)) << 22;
		channel.sweepPitch += diff >> 16;

		if (!trk.portaTime)
		{
			channel.sweepLen = channel.noteLength;
			channel.manualSweep = true;
		}
		else
		{
			int sq_time = cast(uint)(trk.portaTime) * cast(uint)(trk.portaTime);
			int abs_sp = abs(channel.sweepPitch);
			channel.sweepLen = (abs_sp * sq_time) >> 11;
		}
	}

	void UpdateChannel(ref Channel channel) @safe {
		// Kill active channels that aren't physically active
		if (channel.state > CS_START && !channel.reg.enable)
		{
			channel.Kill();
			return;
		}

		bool bNotInSustain = channel.state != CS_SUSTAIN;
		bool bInStart = channel.state == CS_START;
		bool bPitchSweep = channel.sweepPitch && channel.sweepLen && channel.sweepCnt <= channel.sweepLen;
		bool bModulation = !!channel.modDepth;
		bool bVolNeedUpdate = channel.flags[CF_UPDVOL] || bNotInSustain;
		bool bPanNeedUpdate = channel.flags[CF_UPDPAN] || bInStart;
		bool bTmrNeedUpdate = channel.flags[CF_UPDTMR] || bInStart || bPitchSweep;
		int modParam = 0;

		switch (channel.state)
		{
			case CS_NONE:
				return;
			case CS_START:
				channel.reg.ClearControlRegister();
				channel.reg.source = channel.tempReg.SOURCE;
				channel.reg.loopStart = channel.tempReg.REPEAT_POINT;
				channel.reg.length = channel.tempReg.LENGTH;
				channel.reg.totalLength = channel.reg.loopStart + channel.reg.length;
				channel.ampl = AMPL_THRESHOLD;
				channel.state = CS_ATTACK;
				goto case;
			case CS_ATTACK:
			{
				int newAmpl = channel.ampl;
				int oldAmpl = channel.ampl >> 7;
				do
					newAmpl = (newAmpl * cast(int)(channel.attackLvl)) / 256;
				while ((newAmpl >> 7) == oldAmpl);
				channel.ampl = newAmpl;
				if (!channel.ampl)
					channel.state = CS_DECAY;
				break;
			}
			case CS_DECAY:
			{
				channel.ampl -= cast(int)(channel.decayRate);
				int sustLvl = Cnv_Sust(channel.sustainLvl) << 7;
				if (channel.ampl <= sustLvl)
				{
					channel.ampl = sustLvl;
					channel.state = CS_SUSTAIN;
				}
				break;
			}
			case CS_RELEASE:
				channel.ampl -= cast(int)(channel.releaseRate);
				if (channel.ampl <= AMPL_THRESHOLD)
				{
					channel.Kill();
					return;
				}
				break;
			default: break;
		}

		if (bModulation && channel.modDelayCnt < channel.modDelay)
		{
			++channel.modDelayCnt;
			bModulation = false;
		}

		if (bModulation)
		{
			switch (channel.modType)
			{
				case 0:
					bTmrNeedUpdate = true;
					break;
				case 1:
					bVolNeedUpdate = true;
					break;
				case 2:
					bPanNeedUpdate = true;
					break;
				default: break;
			}

			// Get the current modulation parameter
			modParam = Cnv_Sine(channel.modCounter >> 8) * channel.modRange * channel.modDepth; // 7.14

			if (channel.modType == 1)
				modParam = cast(long)(modParam * 60) >> 14; // vol: adjust range to 6dB = 60cB (no fractional bits)
			else
				modParam >>= 8; // tmr/pan: adjust to 7.6

			// Update the modulation variables
			uint counter = channel.modCounter + (channel.modSpeed << 6);
			while (counter >= 0x8000)
				counter -= 0x8000;
			channel.modCounter = cast(ushort)counter;
		}

		if (bTmrNeedUpdate)
		{
			int totalAdj = channel.extTune;
			if (bModulation && !channel.modType)
				totalAdj += modParam;
			if (bPitchSweep)
			{
				int len = channel.sweepLen;
				int cnt = channel.sweepCnt;
				totalAdj += (cast(long)(channel.sweepPitch) * (len - cnt)) / len;
				if (!channel.manualSweep)
					++channel.sweepCnt;
			}
			ushort tmr = channel.tempReg.TIMER;

			if (totalAdj)
				tmr = Timer_Adjust(tmr, totalAdj);
			channel.reg.timer = cast(ushort)-tmr;
			channel.reg.sampleIncrease = (ARM7_CLOCK / cast(double)(this.sampleRate * 2)) / (0x10000 - channel.reg.timer);
			channel.flags[CF_UPDTMR] = false;
		}

		if (bVolNeedUpdate || bPanNeedUpdate)
		{
			uint cr = channel.tempReg.CR;
			if (bVolNeedUpdate)
			{
				int totalVol = channel.ampl >> 7;
				totalVol += channel.extAmpl;
				totalVol += channel.velocity;
				if (bModulation && channel.modType == 1)
					totalVol += modParam;
				totalVol += AMPL_K;
				clamp(totalVol, 0, AMPL_K);

				cr &= ~(SOUND_VOL(0x7F) | SOUND_VOLDIV(3));
				cr |= SOUND_VOL(cast(int)(getvoltbl[totalVol]));

				if (totalVol < AMPL_K - 240)
					cr |= SOUND_VOLDIV(3);
				else if (totalVol < AMPL_K - 120)
					cr |= SOUND_VOLDIV(2);
				else if (totalVol < AMPL_K - 60)
					cr |= SOUND_VOLDIV(1);

				channel.vol = cast(ushort)(((cr & SOUND_VOL(0x7F)) << 4) >> calcVolDivShift((cr & SOUND_VOLDIV(3)) >> 8));

				channel.flags[CF_UPDVOL] = false;
			}

			if (bPanNeedUpdate)
			{
				int realPan = channel.pan;
				realPan += channel.extPan;
				if (bModulation && channel.modType == 2)
					realPan += modParam;
				realPan += 64;
				clamp(realPan, 0, 127);

				cr &= ~SOUND_PAN(0x7F);
				cr |= SOUND_PAN(realPan);
				channel.flags[CF_UPDPAN] = false;
			}

			channel.tempReg.CR = cr;
			channel.reg.SetControlRegister(cr);
		}
	}
	int Interpolate(ref Channel channel) @safe {
		double ratio = channel.reg.samplePosition;
		ratio -= cast(int)(ratio);

		const data = channel.sampleHistory[channel.sampleHistoryPtr + 16 .. $];
		const dataWithPast = channel.sampleHistory[channel.sampleHistoryPtr + 14 .. $];

		if (this.interpolation == Interpolation.INTERPOLATION_SINC)
		{
			double[SINC_WIDTH * 2] kernel = 0.0;
			double kernel_sum = 0.0;
			int i = SINC_WIDTH, shift = cast(int)(floor(ratio * SINC_RESOLUTION));
			int step = channel.reg.sampleIncrease > 1.0 ? cast(int)(SINC_RESOLUTION / channel.reg.sampleIncrease) : SINC_RESOLUTION;
			int shift_adj = shift * step / SINC_RESOLUTION;
			const int window_step = SINC_RESOLUTION;
			for (; i >= -cast(int)(SINC_WIDTH - 1); --i)
			{
				int pos = i * step;
				int window_pos = i * window_step;
				kernel_sum += kernel[i + SINC_WIDTH - 1] = sinc_lut[abs(shift_adj - pos)] * window_lut[abs(shift - window_pos)];
			}
			double sum = 0.0;
			for (i = 0; i < cast(int)(SINC_WIDTH * 2); ++i)
				sum += channel.sampleHistory[channel.sampleHistoryPtr + 16 + i - cast(int)(SINC_WIDTH) + 1] * kernel[i];
			return cast(int)(sum / kernel_sum);
		}
		else if (this.interpolation > Interpolation.INTERPOLATION_LINEAR)
		{
			double c0, c1, c2, c3, c4, c5;

			if (this.interpolation == Interpolation.INTERPOLATION_6POINTLEGRANGE)
			{
				ratio -= 0.5;
				double even1 = dataWithPast[0] + dataWithPast[5], odd1 = dataWithPast[0] - dataWithPast[5];
				double even2 = dataWithPast[1] + dataWithPast[4], odd2 = dataWithPast[1] - dataWithPast[4];
				double even3 = dataWithPast[2] + dataWithPast[3], odd3 = dataWithPast[2] - dataWithPast[3];
				c0 = 0.01171875 * even1 - 0.09765625 * even2 + 0.5859375 * even3;
				c1 = 25 / 384.0 * odd2 - 1.171875 * odd3 - 0.0046875 * odd1;
				c2 = 0.40625 * even2 - 17 / 48.0 * even3 - 5 / 96.0 * even1;
				c3 = 1 / 48.0 * odd1 - 13 / 48.0 * odd2 + 17 / 24.0 * odd3;
				c4 = 1 / 48.0 * even1 - 0.0625 * even2 + 1 / 24.0 * even3;
				c5 = 1 / 24.0 * odd2 - 1 / 12.0 * odd3 - 1 / 120.0 * odd1;
				return cast(int)(((((c5 * ratio + c4) * ratio + c3) * ratio + c2) * ratio + c1) * ratio + c0);
			}
			else // INTERPOLATION_4POINTLEAGRANGE
			{
				c0 = dataWithPast[2];
				c1 = dataWithPast[3] - 1 / 3.0 * dataWithPast[1] - 0.5 * dataWithPast[2] - 1 / 6.0 * dataWithPast[4];
				c2 = 0.5 * (dataWithPast[1] + dataWithPast[3]) - dataWithPast[2];
				c3 = 1 / 6.0 * (dataWithPast[4] - dataWithPast[1]) + 0.5 * (dataWithPast[2] - dataWithPast[3]);
				return cast(int)(((c3 * ratio + c2) * ratio + c1) * ratio + c0);
			}
		}
		else // INTERPOLATION_LINEAR
			return cast(int)(data[0] + ratio * (data[1] - data[0]));
	}
	int GenerateSample(ref Channel channel) @safe {
		if (channel.reg.samplePosition < 0)
			return 0;

		if (channel.reg.format != 3)
		{
			if (this.interpolation == Interpolation.INTERPOLATION_NONE)
				return channel.reg.source.data[cast(uint)(channel.reg.samplePosition)];
			else
				return Interpolate(channel);
		}
		else
		{
			if (channel.chnId < 8)
				return 0;
			else if (channel.chnId < 14)
				return wavedutytbl[channel.reg.waveDuty][cast(uint)(channel.reg.samplePosition) & 0x7];
			else
			{
				if (channel.reg.psgLastCount != cast(uint)(channel.reg.samplePosition))
				{
					uint max = cast(uint)(channel.reg.samplePosition);
					for (uint i = channel.reg.psgLastCount; i < max; ++i)
					{
						if (channel.reg.psgX & 0x1)
						{
							channel.reg.psgX = (channel.reg.psgX >> 1) ^ 0x6000;
							channel.reg.psgLast = -0x7FFF;
						}
						else
						{
							channel.reg.psgX >>= 1;
							channel.reg.psgLast = 0x7FFF;
						}
					}

					channel.reg.psgLastCount = cast(uint)(channel.reg.samplePosition);
				}

				return channel.reg.psgLast;
			}
		}
	}
}

private int muldiv7(int val, ubyte mul) @safe
{
	return mul == 127 ? val : ((val * mul) >> 7);
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

private int getModFlag(int type) @safe
{
	switch (type)
	{
		case 0:
			return CF_UPDTMR;
		case 1:
			return CF_UPDVOL;
		case 2:
			return CF_UPDPAN;
		default:
			return 0;
	}
}

private ushort Timer_Adjust(ushort basetmr, int pitch) @safe
{
	int shift = 0;
	pitch = -pitch;

	while (pitch < 0)
	{
		--shift;
		pitch += 0x300;
	}

	while (pitch >= 0x300)
	{
		++shift;
		pitch -= 0x300;
	}

	ulong tmr = cast(ulong)(basetmr) * (cast(uint)(getpitchtbl[pitch]) + 0x10000);
	shift -= 16;
	if (shift <= 0)
		tmr >>= -shift;
	else if (shift < 32)
	{
		if (tmr & ((~ulong(0)) << (32 - shift)))
			return 0xFFFF;
		tmr <<= shift;
	}
	else
		return 0xFFFF;

	if (tmr < 0x10)
		return 0x10;
	if (tmr > 0xFFFF)
		return 0xFFFF;
	return cast(ushort)(tmr);
}

private int calcVolDivShift(int x) @safe
{
	// VOLDIV(0) /1  >>0
	// VOLDIV(1) /2  >>1
	// VOLDIV(2) /4  >>2
	// VOLDIV(3) /16 >>4
	if (x < 3)
		return x;
	return 4;
}

/*
 * Lookup tables for the Sinc interpolation, to
 * avoid the need to call the sin/cos functions all the time.
 * These are static as they will not change between channels or runs
 * of the program.
 */
private immutable uint SINC_RESOLUTION = 8192;
private immutable uint SINC_WIDTH = 8;
private immutable uint SINC_SAMPLES = SINC_RESOLUTION * SINC_WIDTH;
private immutable double[SINC_SAMPLES + 1] sinc_lut = prepareSincLUT!(SINC_SAMPLES, SINC_WIDTH)();
private immutable double[SINC_SAMPLES + 1] window_lut = prepareWindowLUT!(SINC_SAMPLES, SINC_WIDTH)();

double sinc(double x) @safe
{
	return fEqual(x, 0.0) ? 1.0 : sin(x * M_PI) / (x * M_PI);
}

private double[SINC_SAMPLES + 1] prepareSincLUT(size_t SINC_SAMPLES, size_t SINC_WIDTH)() {
	double[SINC_SAMPLES + 1] result;
	double dx = cast(double)(SINC_WIDTH) / SINC_SAMPLES, x = 0.0;
	for (uint i = 0; i <= SINC_SAMPLES; ++i, x += dx)
	{
		double y = x / SINC_WIDTH;
		result[i] = abs(x) < SINC_WIDTH ? sinc(x) : 0.0;
	}
	return result;
}

private double[SINC_SAMPLES + 1] prepareWindowLUT(size_t SINC_SAMPLES, size_t SINC_WIDTH)() {
	double[SINC_SAMPLES + 1] result;
	double dx = cast(double)(SINC_WIDTH) / SINC_SAMPLES, x = 0.0;
	for (uint i = 0; i <= SINC_SAMPLES; ++i, x += dx)
	{
		double y = x / SINC_WIDTH;
		result[i] = (0.40897 + 0.5 * cos(M_PI * y) + 0.09103 * cos(2 * M_PI * y));
	}
	return result;
}

private immutable double M_PI = 3.14159265358979323846;
