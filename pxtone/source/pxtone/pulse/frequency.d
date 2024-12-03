module pxtone.pulse.frequency;

private enum octaveNum = 16; // octave num.
private enum keyPerOctave = 12; // key per octave
private enum frequencyPerKey = 0x10; // sample per key

private enum basicFrequencyIndex = ((octaveNum / 2) * keyPerOctave * frequencyPerKey);
private enum tableSize = (octaveNum * keyPerOctave * frequencyPerKey);

struct PxtnPulseFrequency {
	static immutable float[] freqTable = genTables();

	float get(int key) const nothrow @safe {
		int i;

		i = (key + 0x6000) * frequencyPerKey / 0x100;
		if (i < 0) {
			i = 0;
		} else if (i >= tableSize) {
			i = tableSize - 1;
		}
		return freqTable[i];
	}

	float get2(int key) nothrow @safe {
		int i = key >> 4;
		if (i < 0) {
			i = 0;
		} else if (i >= tableSize) {
			i = tableSize - 1;
		}
		return freqTable[i];
	}

	const(float)[] getDirect(int* pSize) nothrow @safe {
		*pSize = tableSize;
		return freqTable;
	}
}

private double getDivideOctaveRate(int divi) nothrow @safe {
	double parameter = 1.0;
	double work;
	double result;
	double add;
	int i, j, k;

	// double is 17keta.
	for (i = 0; i < 17; i++) {
		// make add.
		add = 1;
		for (j = 0; j < i; j++) {
			add = add * 0.1;
		}

		// check 0 .. 9
		for (j = 0; j < 10; j++) {
			work = parameter + add * j;

			// divide
			result = 1.0;
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
private float[] genTables() @safe {
	float[] freqTable;
	static immutable double[octaveNum] octTable = [0.00390625, //0  -8
		0.0078125, //1  -7
		0.015625, //2  -6
		0.03125, //3  -5
		0.0625, //4  -4
		0.125, //5  -3
		0.25, //6  -2
		0.5, //7  -1
		1, //8
		2, //9   1
		4, //a   2
		8, //b   3
		16, //c   4
		32, //d   5
		64, //e   6
		128, //f   7
	];

	int key;
	int f;
	double octX24;
	double work;

	freqTable = new float[tableSize];
	//if (!(freqTable)) {
	//	goto End;
	//}

	octX24 = getDivideOctaveRate(keyPerOctave * frequencyPerKey);

	for (f = 0; f < octaveNum * (keyPerOctave * frequencyPerKey); f++) {
		work = octTable[f / (keyPerOctave * frequencyPerKey)];
		for (key = 0; key < f % (keyPerOctave * frequencyPerKey); key++) {
			work *= octX24;
		}
		freqTable[f] = cast(float)work;
	}
	return freqTable;
}
