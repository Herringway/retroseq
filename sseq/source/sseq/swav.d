module sseq.swav;

import sseq.common;

struct SWAV
{
	static struct Header {
		align(1):
		ubyte waveType;
		ubyte loop;
		ushort sampleRate;
		ushort time;
		ushort loopOffset;
		uint nonLoopLength;
	}
	Header header;
	const(ubyte)[] origData;
	short[] data;
}
short[] decode(const(ubyte)[] origData, ref SWAV.Header header) @safe {
	uint size = (header.loopOffset + header.nonLoopLength) * 4;
	short[] data;
	import std.logger; debug tracef("%s", header.waveType);
	// Convert data accordingly
	if (!header.waveType)
	{
		// PCM 8-bit . PCM signed 16-bit
		data.length = size;
		for (size_t i = 0; i < size; ++i)
			data[i] = cast(short)(origData[i] << 8);
		header.loopOffset *= 4;
		header.nonLoopLength *= 4;
	}
	else if (header.waveType == 1)
	{
		// PCM signed 16-bit, no conversion
		data.length = size / 2;
		data[] = cast(const(short)[])origData[0 .. size];
		//for (size_t i = 0; i < size / 2; ++i)
		//	data[i] = ReadLE!short(origData[2 * i .. $]);
		header.loopOffset *= 2;
		header.nonLoopLength *= 2;
	}
	else if (header.waveType == 2)
	{
		// IMA ADPCM . PCM signed 16-bit
		data.length = (size - 4) * 2;
		DecodeADPCM(origData, data, size - 4);
		if (header.loopOffset)
			--header.loopOffset;
		header.loopOffset *= 8;
		header.nonLoopLength *= 8;
	}
	return data;
}
void DecodeADPCM(const(ubyte)[] origData, short[] finalData, uint len) @safe {
	int predictedValue = origData[0] | (origData[1] << 8);
	int stepIndex = origData[2] | (origData[3] << 8);

	for (uint i = 0; i < len; ++i)
	{
		int nibble = origData[i + 4] & 0x0F;
		DecodeADPCMNibble(nibble, stepIndex, predictedValue);
		finalData[2 * i] = cast(short)predictedValue;

		nibble = (origData[i + 4] >> 4) & 0x0F;
		DecodeADPCMNibble(nibble, stepIndex, predictedValue);
		finalData[2 * i + 1] = cast(short)predictedValue;
	}
}


private immutable int[] ima_index_table =
[
	-1, -1, -1, -1, 2, 4, 6, 8,
	-1, -1, -1, -1, 2, 4, 6, 8
];

private immutable int[] ima_step_table =
[
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
	19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
	130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
	337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
	876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
	2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
	5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
	15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
];

private void DecodeADPCMNibble(int nibble, ref int stepIndex, ref int predictedValue) @safe
{
	int step = ima_step_table[stepIndex];

	stepIndex += ima_index_table[nibble];

	if (stepIndex < 0)
		stepIndex = 0;
	else if (stepIndex > 88)
		stepIndex = 88;

	int diff = step >> 3;

	if (nibble & 4)
		diff += step;
	if (nibble & 2)
		diff += step >> 1;
	if (nibble & 1)
		diff += step >> 2;
	if (nibble & 8)
		predictedValue -= diff;
	else
		predictedValue += diff;

	if (predictedValue < -0x8000)
		predictedValue = -0x8000;
	else if (predictedValue > 0x7FFF)
		predictedValue = 0x7FFF;
}

