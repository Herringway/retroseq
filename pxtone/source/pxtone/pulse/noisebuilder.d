module pxtone.pulse.noisebuilder;

import pxtone.pxtn;

import pxtone.error;
import pxtone.pulse.frequency;
import pxtone.pulse.oscillator;
import pxtone.pulse.pcm;
import pxtone.pulse.noise;

private enum basicSampleRate = 44100.0;
private enum basicFrequency = 100.0; // 100 Hz
private enum samplingTop = 32767; //  16 bit max
private enum keyTop = 0x3200; //  40 key

private enum smpNumRand = 44100;
private enum smpNum = cast(int)(basicSampleRate / basicFrequency);

private enum RandomType {
	none = 0,
	saw,
	rect,
}

private struct Oscillator {
	double increment;
	double offset;
	double volume;
	const(short)[] pSmp;
	bool bReverse;
	RandomType ranType;
	int rdmStart;
	int rdmMargin;
	int rdmIndex;
}

private struct Point {
	int smp;
	double mag;
}

private struct Unit {
	bool bEnable;
	double[2] pan;
	int enveIndex;
	double enveMagStart;
	double enveMagMargin;
	int enveCount;
	Point[] enves;

	Oscillator main;
	Oscillator freq;
	Oscillator volu;
}

private void setOscillator(Oscillator* pTo, PxNoiseDesignOscillator* pFrom, int sps, const(short)[] pTbl, const(short)[] pTblRand) nothrow @safe {
	const(short)[] p;

	switch (pFrom.type) {
	case PxWaveType.Random:
		pTo.ranType = RandomType.saw;
		break;
	case PxWaveType.Random2:
		pTo.ranType = RandomType.rect;
		break;
	default:
		pTo.ranType = RandomType.none;
		break;
	}

	pTo.increment = (basicSampleRate / sps) * (pFrom.freq / basicFrequency);

	// offset
	if (pTo.ranType != RandomType.none) {
		pTo.offset = 0;
	} else {
		pTo.offset = cast(double) smpNum * (pFrom.offset / 100);
	}

	pTo.volume = pFrom.volume / 100;
	pTo.pSmp = pTbl;
	pTo.bReverse = pFrom.bRev;

	pTo.rdmStart = 0;
	pTo.rdmIndex = cast(int)(cast(double)(smpNumRand) * (pFrom.offset / 100));
	p = pTblRand;
	pTo.rdmMargin = p[pTo.rdmIndex];

}

private void increment(Oscillator* pOsc, double increment, const(short)[] pTblRand) nothrow @safe {
	pOsc.offset += increment;
	if (pOsc.offset > smpNum) {
		pOsc.offset -= smpNum;
		if (pOsc.offset >= smpNum) {
			pOsc.offset = 0;
		}

		if (pOsc.ranType != RandomType.none) {
			const(short)[] p = pTblRand;
			pOsc.rdmStart = p[pOsc.rdmIndex];
			pOsc.rdmIndex++;
			if (pOsc.rdmIndex >= smpNumRand) {
				pOsc.rdmIndex = 0;
			}
			pOsc.rdmMargin = p[pOsc.rdmIndex] - pOsc.rdmStart;
		}
	}
}

struct PxtnPulseNoiseBuilder {
private:
	static immutable short[][PxWaveType.num] pTables = genTables();

	PxtnPulseFrequency freq;

public:
	PxtnPulsePCM buildNoise(ref PxtnPulseNoise pNoise, int ch, int sps, int bps) const @safe {
		int offset = 0;
		double work = 0;
		double vol = 0;
		double fre = 0;
		double store = 0;
		int byte4 = 0;
		int unitNum = 0;
		ubyte[] p = null;
		int sampleIdx = 0;

		Unit[] units = null;
		PxtnPulsePCM pPCM;

		pNoise.fix();

		unitNum = pNoise.getUnitNum();

		units = new Unit[](unitNum);
		scope(exit) {
			units = null;
		}

		for (int u = 0; u < unitNum; u++) {
			Unit* pU = &units[u];

			PxNoiseDesignUnit* pDU = pNoise.getUnit(u);

			pU.bEnable = pDU.bEnable;
			pU.enves.length = pDU.enves.length;
			if (pDU.pan == 0) {
				pU.pan[0] = 1;
				pU.pan[1] = 1;
			} else if (pDU.pan < 0) {
				pU.pan[0] = 1;
				pU.pan[1] = cast(double)(100.0f + pDU.pan) / 100;
			} else {
				pU.pan[1] = 1;
				pU.pan[0] = cast(double)(100.0f - pDU.pan) / 100;
			}

			// envelope
			for (int e = 0; e < pDU.enves.length; e++) {
				pU.enves[e].smp = sps * pDU.enves[e].x / 1000;
				pU.enves[e].mag = cast(double) pDU.enves[e].y / 100;
			}
			pU.enveIndex = 0;
			pU.enveMagStart = 0;
			pU.enveMagMargin = 0;
			pU.enveCount = 0;
			while (pU.enveIndex < pU.enves.length) {
				pU.enveMagMargin = pU.enves[pU.enveIndex].mag - pU.enveMagStart;
				if (pU.enves[pU.enveIndex].smp) {
					break;
				}
				pU.enveMagStart = pU.enves[pU.enveIndex].mag;
				pU.enveIndex++;
			}

			setOscillator(&pU.main, &pDU.main, sps, pTables[pDU.main.type], pTables[PxWaveType.Random]);
			setOscillator(&pU.freq, &pDU.freq, sps, pTables[pDU.freq.type], pTables[PxWaveType.Random]);
			setOscillator(&pU.volu, &pDU.volu, sps, pTables[pDU.volu.type], pTables[PxWaveType.Random]);
		}

		sampleIdx = cast(int)(cast(double) pNoise.getSmpNum44k() / (44100.0 / sps));

		pPCM = PxtnPulsePCM.init;
		pPCM.create(ch, sps, bps, sampleIdx);
		p = pPCM.getPCMBuffer();

		for (int s = 0; s < sampleIdx; s++) {
			for (int c = 0; c < ch; c++) {
				store = 0;
				for (int u = 0; u < unitNum; u++) {
					Unit* pU = &units[u];

					if (pU.bEnable) {
						Oscillator* po;

						// main
						po = &pU.main;
						switch (po.ranType) {
						case RandomType.none:
							offset = cast(int) po.offset;
							if (offset >= 0) {
								work = po.pSmp[offset];
							} else {
								work = 0;
							}
							break;
						case RandomType.saw:
							if (po.offset >= 0) {
								work = po.rdmStart + po.rdmMargin * cast(int) po.offset / smpNum;
							} else {
								work = 0;
							}
							break;
						case RandomType.rect:
							if (po.offset >= 0) {
								work = po.rdmStart;
							} else {
								work = 0;
							}
							break;
						default:
							break;
						}
						if (po.bReverse) {
							work *= -1;
						}
						work *= po.volume;

						// volu
						po = &pU.volu;
						switch (po.ranType) {
						case RandomType.none:
							offset = cast(int) po.offset;
							vol = cast(double) po.pSmp[offset];
							break;
						case RandomType.saw:
							vol = po.rdmStart + po.rdmMargin * cast(int) po.offset / smpNum;
							break;
						case RandomType.rect:
							vol = po.rdmStart;
							break;
						default:
							break;
						}
						if (po.bReverse) {
							vol *= -1;
						}
						vol *= po.volume;

						work = work * (vol + samplingTop) / (samplingTop * 2);
						work = work * pU.pan[c];

						// envelope
						if (pU.enveIndex < pU.enves.length) {
							work *= pU.enveMagStart + (pU.enveMagMargin * pU.enveCount / pU.enves[pU.enveIndex].smp);
						} else {
							work *= pU.enveMagStart;
						}
						store += work;
					}
				}

				byte4 = cast(int) store;
				if (byte4 > samplingTop) {
					byte4 = samplingTop;
				}
				if (byte4 < -samplingTop) {
					byte4 = -samplingTop;
				}
				if (bps == 8) {
					p[0] = cast(ubyte)((byte4 >> 8) + 128);
					p = p[1 .. $];
				}  //  8bit
				else {
					((cast(short[])(p[0 .. 2])))[0] = cast(short) byte4;
					p = p[2 .. $];
				} // 16bit
			}

			// increment
			for (int u = 0; u < unitNum; u++) {
				Unit* pU = &units[u];

				if (pU.bEnable) {
					Oscillator* po = &pU.freq;

					switch (po.ranType) {
					case RandomType.none:
						offset = cast(int) po.offset;
						fre = keyTop * po.pSmp[offset] / samplingTop;
						break;
					case RandomType.saw:
						fre = po.rdmStart + po.rdmMargin * cast(int) po.offset / smpNum;
						break;
					case RandomType.rect:
						fre = po.rdmStart;
						break;
					default:
						break;
					}

					if (po.bReverse) {
						fre *= -1;
					}
					fre *= po.volume;

					increment(&pU.main, pU.main.increment * freq.get(cast(int) fre), pTables[PxWaveType.Random]);
					increment(&pU.freq, pU.freq.increment, pTables[PxWaveType.Random]);
					increment(&pU.volu, pU.volu.increment, pTables[PxWaveType.Random]);

					// envelope
					if (pU.enveIndex < pU.enves.length) {
						pU.enveCount++;
						if (pU.enveCount >= pU.enves[pU.enveIndex].smp) {
							pU.enveCount = 0;
							pU.enveMagStart = pU.enves[pU.enveIndex].mag;
							pU.enveMagMargin = 0;
							pU.enveIndex++;
							while (pU.enveIndex < pU.enves.length) {
								pU.enveMagMargin = pU.enves[pU.enveIndex].mag - pU.enveMagStart;
								if (pU.enves[pU.enveIndex].smp) {
									break;
								}
								pU.enveMagStart = pU.enves[pU.enveIndex].mag;
								pU.enveIndex++;
							}
						}
					}
				}
			}
		}

		return pPCM;
	}
}

short[][PxWaveType.num] genTables() @safe {
	PxtnPoint[1] overtonesSine = [{1, 128}];
	PxtnPoint[16] overtonesSaw2 = [{1, 128}, {2, 128}, {3, 128}, {4, 128}, {5, 128}, {6, 128}, {7, 128}, {8, 128}, {9, 128}, {10, 128}, {11, 128}, {12, 128}, {13, 128}, {14, 128}, {15, 128}, {16, 128},];
	PxtnPoint[8] overtonesRect2 = [{1, 128}, {3, 128}, {5, 128}, {7, 128}, {9, 128}, {11, 128}, {13, 128}, {15, 128},];

	PxtnPoint[4] coodiTri = [{0, 0}, {smpNum / 4, 128}, {smpNum * 3 / 4, -128}, {smpNum, 0}];
	int s;
	short[] p;
	double work;

	int a;
	short v;
	scope PxtnPulseOscillator osci;
	int[2] randBuf;

	void randomReset() nothrow @safe {
		randBuf[0] = 0x4444;
		randBuf[1] = 0x8888;
	}

	short randomGet() nothrow @safe {
		ubyte[2] w1, w2;

        short tmp = cast(short)(randBuf[0] + randBuf[1]);
		w2[1] = (tmp & 0xFF);
		w2[0] = (tmp & 0xFF00) >> 8;
		randBuf[1] = cast(short) randBuf[0];
		randBuf[0] = cast(short) (w2[0] + (w2[1] << 8));

		return cast(short) (w2[0] + (w2[1] << 8));
	}

	short[][PxWaveType.num] pTables;
	pTables[PxWaveType.None] = new short[smpNum];
	pTables[PxWaveType.Sine] = new short[smpNum];
	pTables[PxWaveType.Saw] = new short[smpNum];
	pTables[PxWaveType.Rect] = new short[smpNum];
	pTables[PxWaveType.Random] = new short[smpNumRand];
	pTables[PxWaveType.Saw2] = new short[smpNum];
	pTables[PxWaveType.Rect2] = new short[smpNum];
	pTables[PxWaveType.Tri] = new short[smpNum];
	//pTables[PxWaveType.Random2] = new short[smpNumRand];
	pTables[PxWaveType.Rect3] = new short[smpNum];
	pTables[PxWaveType.Rect4] = new short[smpNum];
	pTables[PxWaveType.Rect8] = new short[smpNum];
	pTables[PxWaveType.Rect16] = new short[smpNum];
	pTables[PxWaveType.Saw3] = new short[smpNum];
	pTables[PxWaveType.Saw4] = new short[smpNum];
	pTables[PxWaveType.Saw6] = new short[smpNum];
	pTables[PxWaveType.Saw8] = new short[smpNum];

	// none --

	// sine --
	osci.readyGetSample(overtonesSine[], 1, 128, smpNum, 0);
	p = pTables[PxWaveType.Sine];
	for (s = 0; s < smpNum; s++) {
		work = osci.getOneSampleOvertone(s);
		if (work > 1.0) {
			work = 1.0;
		}
		if (work < -1.0) {
			work = -1.0;
		}
		p[0] = cast(short)(work * samplingTop);
		p = p[1 .. $];
	}

	// saw down --
	p = pTables[PxWaveType.Saw];
	work = samplingTop + samplingTop;
	for (s = 0; s < smpNum; s++) {
		p[0] = cast(short)(samplingTop - work * s / smpNum);
		p = p[1 .. $];
	}

	// rect --
	p = pTables[PxWaveType.Rect];
	for (s = 0; s < smpNum / 2; s++) {
		p[0] = cast(short)(samplingTop);
		p = p[1 ..$];
	}
	for ( /+s+/ ; s < smpNum; s++) {
		p[0] = cast(short)(-samplingTop);
		p = p[1 .. $];
	}

	// random --
	p = pTables[PxWaveType.Random];
	randomReset();
	for (s = 0; s < smpNumRand; s++) {
		p[0] = randomGet();
		p = p[1 .. $];
	}

	// saw2 --
	osci.readyGetSample(overtonesSaw2[], 16, 128, smpNum, 0);
	p = pTables[PxWaveType.Saw2];
	for (s = 0; s < smpNum; s++) {
		work = osci.getOneSampleOvertone(s);
		if (work > 1.0) {
			work = 1.0;
		}
		if (work < -1.0) {
			work = -1.0;
		}
		p[0] = cast(short)(work * samplingTop);
		p = p[1 .. $];
	}

	// rect2 --
	osci.readyGetSample(overtonesRect2[], 8, 128, smpNum, 0);
	p = pTables[PxWaveType.Rect2];
	for (s = 0; s < smpNum; s++) {
		work = osci.getOneSampleOvertone(s);
		if (work > 1.0) {
			work = 1.0;
		}
		if (work < -1.0) {
			work = -1.0;
		}
		p[0] = cast(short)(work * samplingTop);
		p = p[1 .. $];
	}

	// Triangle --
	osci.readyGetSample(coodiTri[], 4, 128, smpNum, smpNum);
	p = pTables[PxWaveType.Tri];
	for (s = 0; s < smpNum; s++) {
		work = osci.getOneSampleCoordinate(s);
		if (work > 1.0) {
			work = 1.0;
		}
		if (work < -1.0) {
			work = -1.0;
		}
		p[0] = cast(short)(work * samplingTop);
		p = p[1 .. $];
	}

	// Random2  -- x

	// Rect-3  --
	p = pTables[PxWaveType.Rect3];
	for (s = 0; s < smpNum / 3; s++) {
		p[0] = cast(short)(samplingTop);
		p = p[1 .. $];
	}
	for ( /+s+/ ; s < smpNum; s++) {
		p[0] = cast(short)(-samplingTop);
		p = p[1 .. $];
	}
	// Rect-4   --
	p = pTables[PxWaveType.Rect4];
	for (s = 0; s < smpNum / 4; s++) {
		p[0] = cast(short)(samplingTop);
		p = p[1 .. $];
	}
	for ( /+s+/ ; s < smpNum; s++) {
		p[0] = cast(short)(-samplingTop);
		p = p[1 .. $];
	}
	// Rect-8   --
	p = pTables[PxWaveType.Rect8];
	for (s = 0; s < smpNum / 8; s++) {
		p[0] = cast(short)(samplingTop);
		p = p[1 .. $];
	}
	for ( /+s+/ ; s < smpNum; s++) {
		p[0] = cast(short)(-samplingTop);
		p = p[1 .. $];
	}
	// Rect-16  --
	p = pTables[PxWaveType.Rect16];
	for (s = 0; s < smpNum / 16; s++) {
		p[0] = cast(short)(samplingTop);
		p = p[1 .. $];
	}
	for ( /+s+/ ; s < smpNum; s++) {
		p[0] = cast(short)(-samplingTop);
		p = p[1 .. $];
	}

	// Saw-3    --
	p = pTables[PxWaveType.Saw3];
	for (s = 0; s < smpNum / 3; s++) {
		p[0] = cast(short)(samplingTop);
		p = p[1 .. $];
	}
	for ( /+s+/ ; s < smpNum * 2 / 3; s++) {
		p[0] = cast(short)(0);
		p = p[1 .. $];
	}
	for ( /+s+/ ; s < smpNum; s++) {
		p[0] = cast(short)(-samplingTop);
		p = p[1 .. $];
	}

	// Saw-4    --
	p = pTables[PxWaveType.Saw4];
	for (s = 0; s < smpNum / 4; s++) {
		p[0] = cast(short)(samplingTop);
		p = p[1 .. $];
	}
	for ( /+s+/ ; s < smpNum * 2 / 4; s++) {
		p[0] = cast(short)(samplingTop / 3);
		p = p[1 .. $];
	}
	for ( /+s+/ ; s < smpNum * 3 / 4; s++) {
		p[0] = cast(short)(-samplingTop / 3);
		p = p[1 .. $];
	}
	for ( /+s+/ ; s < smpNum; s++) {
		p[0] = cast(short)(-samplingTop);
		p = p[1 .. $];
	}

	// Saw-6    --
	p = pTables[PxWaveType.Saw6];
	a = smpNum * 1 / 6;
	v = samplingTop;
	for (s = 0; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 2 / 6;
	v = samplingTop - samplingTop * 2 / 5;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 3 / 6;
	v = samplingTop / 5;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 4 / 6;
	v = -samplingTop / 5;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 5 / 6;
	v = -samplingTop + samplingTop * 2 / 5;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum;
	v = -samplingTop;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}

	// Saw-8    --
	p = pTables[PxWaveType.Saw8];
	a = smpNum * 1 / 8;
	v = samplingTop;
	for (s = 0; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 2 / 8;
	v = samplingTop - samplingTop * 2 / 7;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 3 / 8;
	v = samplingTop - samplingTop * 4 / 7;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 4 / 8;
	v = samplingTop / 7;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 5 / 8;
	v = -samplingTop / 7;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 6 / 8;
	v = -samplingTop + samplingTop * 4 / 7;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum * 7 / 8;
	v = -samplingTop + samplingTop * 2 / 7;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	a = smpNum;
	v = -samplingTop;
	for ( /+s+/ ; s < a; s++) {
		p[0] = v;
		p = p[1 .. $];
	}
	return pTables;
}
