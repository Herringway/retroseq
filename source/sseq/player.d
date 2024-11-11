module sseq.player;

import sseq.common;
import sseq.sseq;
import sseq.track;
import sseq.channel;
import sseq.consts;

struct Player
{
	ubyte prio, nTracks;
	ushort tempo, tempoCount, tempoRate /* 8.8 fixed point */;
	short masterVol, sseqVol;

	const(SSEQ) *sseq;

	ubyte[FSS_TRACKCOUNT] trackIds;
	Track[FSS_MAXTRACKS] tracks;
	Channel[16] channels;
	short[32] variables = -1;

	uint sampleRate;
	Interpolation interpolation;

	bool Setup(const(SSEQ) *sseqToPlay) {
		for (size_t i = 0; i < 16; ++i)
		{
			this.channels[i].initialize();
			this.channels[i].chnId = cast(byte)i;
			this.channels[i].ply = &this;
		}
		this.sseq = sseqToPlay;

		int firstTrack = this.TrackAlloc();
		if (firstTrack == -1)
			return false;
		this.tracks[firstTrack].Init(cast(ubyte)firstTrack, &this, this.sseq.data, 0);

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
				this.tracks[this.trackIds[i]].Run();
		}
		this.tempoCount += (cast(int)(this.tempo) * cast(int)(this.tempoRate)) >> 8;
	}
	void UpdateTracks() @safe {
		for (int i = 0; i < 16; ++i)
			this.channels[i].UpdateTrack();
		for (int i = 0; i < FSS_MAXTRACKS; ++i)
			this.tracks[i].updateFlags = false;
	}
	void Timer() @safe {
		this.UpdateTracks();

		for (int i = 0; i < 16; ++i)
			this.channels[i].Update();

		this.Run();
	}

	/* Playback helper */
	double secondsPerSample, secondsIntoPlayback, secondsUntilNextClock;
	bool[16] mutes;
	void GenerateSamples(short[2][] buf) @system {
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
					int sample = chn.GenerateSample();
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
}

private int muldiv7(int val, ubyte mul) @safe
{
	return mul == 127 ? val : ((val * mul) >> 7);
}