///
module organya.pixtone;

import std.random;
import std.math;
import organya.organya;

struct PixtoneObject {
	int id;
	PixtoneParameter[] params;
}
///
align(1) struct PixtoneParameter2 {
align(1):
	int model; ///
	double num; ///
	int top; ///
	int offset; ///
}

///
align(1) struct PixtoneParameter {
align(1):
	int use; ///
	int size; ///
	PixtoneParameter2 oMain; ///
	PixtoneParameter2 oPitch; ///
	PixtoneParameter2 oVolume; ///
	int initial; ///
	int pointAx; ///
	int pointAy; ///
	int pointBx; ///
	int pointBy; ///
	int pointCx; ///
	int pointCy; ///
}

///
private immutable waveModelTable = makeWaveTables();

///
private byte[0x100][6] makeWaveTables() @safe {
	byte[0x100][6] table;
	int i;

	int a;
	// Sine wave
	foreach (idx, ref sample; table[0]) {
		sample = cast(byte)(sin((idx * 6.283184) / 256.0) * 64.0);
	}

	// Triangle wave
	foreach (idx, ref sample; table[1][0 .. 0x40]) {
		// Upwards
		sample = cast(byte)((idx * 0x40) / 0x40);
	}
	foreach (idx, ref sample; table[1][0x40 .. 0xC0]) {
		// Downwards
		sample = cast(byte)(0x40 - ((idx * 0x40) / 0x40));
	}
	foreach (idx, ref sample; table[1][0xC0 .. $]) {
		// Back up
		sample = cast(byte)(((idx * 0x40) / 0x40) - 0x40);
	}

	// Saw up wave
	foreach (idx, ref sample; table[2]) {
		sample = cast(byte)((idx / 2) - 0x40);
	}

	// Saw down wave
	foreach (idx, ref sample; table[3]) {
		sample = cast(byte)(0x40 - (idx / 2));
	}

	// Square wave
	foreach (ref sample; table[4][0 .. 0x80]) {
		sample = 0x40;
	}
	foreach (ref sample; table[4][0x80 .. $]) {
		sample = -0x40;
	}

	// White noise wave
	Random rng;
	foreach (ref sample; table[5]) {
		sample = cast(byte) uniform(0, 127, rng);
	}
	return table;
}

///
void MakePixelWaveData(const PixtoneParameter ptp, ubyte[] pData) @safe {
	int i;
	int a, b, c, d;

	double dPitch;
	double dMain;
	double dVolume;

	double dEnvelope;
	byte[0x100] envelopeTable;

	double d1, d2, d3;

	envelopeTable = envelopeTable.init;

	i = 0;

	dEnvelope = ptp.initial;
	while (i < ptp.pointAx) {
		envelopeTable[i] = cast(byte) dEnvelope;
		dEnvelope = ((cast(double) ptp.pointAy - ptp.initial) / ptp.pointAx) + dEnvelope;
		++i;
	}

	dEnvelope = ptp.pointAy;
	while (i < ptp.pointBx) {
		envelopeTable[i] = cast(byte) dEnvelope;
		dEnvelope = ((cast(double) ptp.pointBy - ptp.pointAy) / cast(double)(ptp.pointBx - ptp.pointAx)) + dEnvelope;
		++i;
	}

	dEnvelope = ptp.pointBy;
	while (i < ptp.pointCx) {
		envelopeTable[i] = cast(byte) dEnvelope;
		dEnvelope = (cast(double) ptp.pointCy - ptp.pointBy) / cast(double)(ptp.pointCx - ptp.pointBx) + dEnvelope;
		++i;
	}

	dEnvelope = ptp.pointCy;
	while (i < 0x100) {
		envelopeTable[i] = cast(byte) dEnvelope;
		dEnvelope = dEnvelope - (ptp.pointCy / cast(double)(0x100 - ptp.pointCx));
		++i;
	}

	dPitch = ptp.oPitch.offset;
	dMain = ptp.oMain.offset;
	dVolume = ptp.oVolume.offset;

	if (ptp.oMain.num == 0.0) {
		d1 = 0.0;
	} else {
		d1 = 256.0 / (ptp.size / ptp.oMain.num);
	}

	if (ptp.oPitch.num == 0.0) {
		d2 = 0.0;
	} else {
		d2 = 256.0 / (ptp.size / ptp.oPitch.num);
	}

	if (ptp.oVolume.num == 0.0) {
		d3 = 0.0;
	} else {
		d3 = 256.0 / (ptp.size / ptp.oVolume.num);
	}

	foreach (idx, ref sample; pData[0 .. ptp.size]) {
		a = cast(int) dMain % 0x100;
		b = cast(int) dPitch % 0x100;
		c = cast(int) dVolume % 0x100;
		d = cast(int)(cast(double)(idx * 0x100) / ptp.size);
		sample = cast(ubyte)(waveModelTable[ptp.oMain.model][a] * ptp.oMain.top / 64 * (((waveModelTable[ptp.oVolume.model][c] * ptp.oVolume.top) / 64) + 64) / 64 * envelopeTable[d] / 64 + 128);

		if (waveModelTable[ptp.oPitch.model][b] < 0) {
			dMain += d1 - d1 * 0.5 * -cast(int) waveModelTable[ptp.oPitch.model][b] * ptp.oPitch.top / 64.0 / 64.0;
		} else {
			dMain += d1 + d1 * 2.0 * waveModelTable[ptp.oPitch.model][b] * ptp.oPitch.top / 64.0 / 64.0;
		}

		dPitch += d2;
		dVolume += d3;
	}
}
