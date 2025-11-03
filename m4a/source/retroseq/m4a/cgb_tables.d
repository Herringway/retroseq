///
module retroseq.m4a.cgb_tables;

enum masterClock = 4194304;

enum pulseClock = masterClock / 4.0;
enum noiseClock = masterClock / 16.0;

///
immutable short[32] pulseWave0 = [
	1, 1,-1,-1,-1,-1,-1,-1,
	-1,-1,-1,-1,-1,-1,-1,-1,
	1, 1,-1,-1,-1,-1,-1,-1,
	-1,-1,-1,-1,-1,-1,-1,-1,
];

///
immutable short[32] pulseWave1 = [
	1, 1, 1, 1,-1,-1,-1,-1,
	-1,-1,-1,-1,-1,-1,-1,-1,
	1, 1, 1, 1,-1,-1,-1,-1,
	-1,-1,-1,-1,-1,-1,-1,-1,
];

///
immutable short[32] pulseWave2 = [
	1, 1, 1, 1, 1, 1, 1, 1,
	-1,-1,-1,-1,-1,-1,-1,-1,
	1, 1, 1, 1, 1, 1, 1, 1,
	-1,-1,-1,-1,-1,-1,-1,-1,
];

///
immutable short[32] pulseWave3 = [
	1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1,-1,-1,-1,-1,
	1, 1, 1, 1, 1, 1, 1, 1,
	1, 1, 1, 1,-1,-1,-1,-1,
];
immutable pulseWaveTables = [ pulseWave0, pulseWave1, pulseWave2, pulseWave3 ];

immutable float[2048] freqTable = () {
	float[2048] result;
	foreach (period, ref value; result) {
		// the waveform is 8 samples long, so divide clock by 8 to get the tone frequency
		value = (pulseClock / 8.0) / (2048 - period);
	}
	return result;
} ();

///
immutable float[256] freqTableNoise = () {
	float[256] result;
	foreach (nr43Value, ref value; result) {
		const divider = [0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0][nr43Value & 7];
		const shift = nr43Value >> 4;
		value = noiseClock / (divider * (1 << shift));
	}
	return result;
}();
