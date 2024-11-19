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

	void Init(ubyte handle, const(ubyte)[] dataPos, int n) @safe {
		this.trackId = handle;
		this.num = cast(ubyte)n;
		this.trackData = dataPos;
		this.ClearState();
	}
	void Zero() @safe {
		this.trackId = -1;

		this.state = false;
		this.num = this.prio = 0;

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
		this.prio = 64;

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
}
