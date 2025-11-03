///
module retroseq.pxtone.pulse.frequency;

import std.algorithm.comparison;

private enum octaveNum = 16; /// octave num.
private enum keyPerOctave = 12; /// key per octave
private enum frequencyPerKey = 16; /// sample per key

///
struct PxtnPulseFrequency {
	///
	static immutable float[] freqTable = genTables(octaveNum, keyPerOctave, frequencyPerKey);

	///
	float get(int key) const nothrow @safe pure {
		return freqTable[clamp((key + 0x6000) * frequencyPerKey / 0x100, 0, cast(int)($ - 1))];
	}

	///
	float get2(int key) nothrow @safe pure {
		return freqTable[clamp(key >> 4, 0, cast(int)($ - 1))];
	}
}

@safe pure unittest {
	import std.math : isClose;
	PxtnPulseFrequency p;
	assert(p.get(0) == 1.0);
	assert(p.get(-0x6000).isClose(0.00390625));
	assert(p.get(int.min / 1024).isClose(0.00390625));
	assert(p.get(int.max / 1024).isClose(255.077));
}

///
private double getDivideOctaveRate(int divi) nothrow @safe pure {
	double parameter = 1.0;

	// double is 17keta.
	for (int i = 0; i < 17; i++) {
		// make add.
		double add = 1;
		for (int j = 0; j < i; j++) {
			add = add * 0.1;
		}

		// check 0 .. 9
		int j;
		for (j = 0; j < 10; j++) {
			double work = parameter + add * j;

			// divide
			double result = 1.0;
			int k;
			for (k = 0; k < divi; k++) {
				result *= work;
				if (result >= 2.0) {
					break;
				}
			}

			// under '2'
			if (k != divi) {
				break;
			}
		}
		// before '2'
		parameter += add * (j - 1);
	}

	return parameter;
}
///
private float[] genTables(ulong octaveNum, ulong keyPerOctave, ulong frequencyPerKey) @safe pure {
	float[] freqTable = new float[](octaveNum * keyPerOctave * frequencyPerKey);

	const octX24Count = cast(int)(keyPerOctave * frequencyPerKey);
	const octX24 = getDivideOctaveRate(cast(int)octX24Count);

	foreach (idx, ref freq; freqTable) {
		freq = 2.0 ^^ (cast(int)idx / octX24Count - 8) * octX24 ^^ (idx % octX24Count);
	}
	return freqTable;
}
