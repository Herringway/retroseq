module pxtone.pulse.noise;

import pxtone.pxtn;

import pxtone.error;
import pxtone.descriptor;
import pxtone.pulse.frequency;
import pxtone.pulse.oscillator;
import pxtone.pulse.pcm;

enum PxWaveType {
	None = 0,
	Sine,
	Saw,
	Rect,
	Random,
	Saw2,
	Rect2,

	Tri,
	Random2,
	Rect3,
	Rect4,
	Rect8,
	Rect16,
	Saw3,
	Saw4,
	Saw6,
	Saw8,

	num,
}

struct PxNoiseDesignOscillator {
	PxWaveType type;
	float freq = 0.0;
	float volume = 0.0;
	float offset = 0.0;
	bool bRev;
}

struct PxNoiseDesignUnit {
	bool bEnable;
	int enveNum;
	PxtnPoint[] enves;
	int pan;
	PxNoiseDesignOscillator main;
	PxNoiseDesignOscillator freq;
	PxNoiseDesignOscillator volu;
}

private enum noiseDesignLimitSmpnum = (48000 * 10);
private enum noiseDesignLimitEnveX = (1000 * 10);
private enum noiseDesignLimitEnveY = (100);
private enum noiseDesignLimitOscillatorFrequency = 44100.0f;
private enum noiseDesignLimitOscillatorVolume = 200.0f;
private enum noiseDesignLimitOscillatorOffset = 100.0f;

private void fixUnit(PxNoiseDesignOscillator* pOsc) nothrow @safe {
	if (pOsc.type >= PxWaveType.num) {
		pOsc.type = PxWaveType.None;
	}
	if (pOsc.freq > noiseDesignLimitOscillatorFrequency) {
		pOsc.freq = noiseDesignLimitOscillatorFrequency;
	}
	if (pOsc.freq <= 0) {
		pOsc.freq = 0;
	}
	if (pOsc.volume > noiseDesignLimitOscillatorVolume) {
		pOsc.volume = noiseDesignLimitOscillatorVolume;
	}
	if (pOsc.volume <= 0) {
		pOsc.volume = 0;
	}
	if (pOsc.offset > noiseDesignLimitOscillatorOffset) {
		pOsc.offset = noiseDesignLimitOscillatorOffset;
	}
	if (pOsc.offset <= 0) {
		pOsc.offset = 0;
	}
}

private enum maxNoiseEditUnitNum = 4;
private enum maxNoiseEditEnvelopeNum = 3;

private enum noiseEditFlag {
	envelope = 0x0004,
	pan = 0x0008,
	oscillatorMain = 0x0010,
	oscillatorFreq = 0x0020,
	oscillatorVolume = 0x0040,
	//oscillatorPan = 0x0080, // not used
	uncovered = 0xffffff83,
}


private immutable identifierCode = "PTNOISE-";
//currentVersion =  20051028 ; -v.0.9.2.3
private __gshared const uint currentVersion = 20120418; // 16 wave types.

private void writeOscillator(const(PxNoiseDesignOscillator)* pOsc, ref PxtnDescriptor pDoc, ref int pAdd) @safe {
	int work;
	work = cast(int) pOsc.type;
	pDoc.writeVarInt(work, pAdd);
	work = cast(int) pOsc.bRev;
	pDoc.writeVarInt(work, pAdd);
	work = cast(int)(pOsc.freq * 10);
	pDoc.writeVarInt(work, pAdd);
	work = cast(int)(pOsc.volume * 10);
	pDoc.writeVarInt(work, pAdd);
	work = cast(int)(pOsc.offset * 10);
	pDoc.writeVarInt(work, pAdd);
}

private void readOscillator(PxNoiseDesignOscillator* pOsc, ref PxtnDescriptor pDoc) @safe {
	int work;
	pDoc.readVarInt(work);
	pOsc.type = cast(PxWaveType) work;
	if (pOsc.type >= PxWaveType.num) {
		throw new PxtoneException("fmt unknown");
	}
	pDoc.readVarInt(work);
	pOsc.bRev = work ? true : false;
	pDoc.readVarInt(work);
	pOsc.freq = cast(float) work / 10;
	pDoc.readVarInt(work);
	pOsc.volume = cast(float) work / 10;
	pDoc.readVarInt(work);
	pOsc.offset = cast(float) work / 10;
}

private uint makeFlags(const(PxNoiseDesignUnit)* pU) nothrow @safe {
	uint flags = 0;
	flags |= noiseEditFlag.envelope;
	if (pU.pan) {
		flags |= noiseEditFlag.pan;
	}
	if (pU.main.type != PxWaveType.None) {
		flags |= noiseEditFlag.oscillatorMain;
	}
	if (pU.freq.type != PxWaveType.None) {
		flags |= noiseEditFlag.oscillatorFreq;
	}
	if (pU.volu.type != PxWaveType.None) {
		flags |= noiseEditFlag.oscillatorVolume;
	}
	return flags;
}

private int compareOscillator(const(PxNoiseDesignOscillator)* pOsc1, const(PxNoiseDesignOscillator)* pOsc2) nothrow @safe {
	if (pOsc1.type != pOsc2.type) {
		return 1;
	}
	if (pOsc1.freq != pOsc2.freq) {
		return 1;
	}
	if (pOsc1.volume != pOsc2.volume) {
		return 1;
	}
	if (pOsc1.offset != pOsc2.offset) {
		return 1;
	}
	if (pOsc1.bRev != pOsc2.bRev) {
		return 1;
	}
	return 0;
}

struct PxtnPulseNoise {
private:
	int smpNum44k;
	int unitNum;
	PxNoiseDesignUnit[] units;

public:
	 ~this() nothrow @safe {
		release();
	}

	void write(ref PxtnDescriptor pDoc, ref int pAdd) const @safe {
		bool bRet = false;
		int u, e, seek, numSeek, flags;
		char _byte;
		char unitNum = 0;
		const(PxNoiseDesignUnit)* pU;

		//	Fix();

		seek = pAdd;

		pDoc.write(identifierCode);
		pDoc.write(currentVersion);
		seek += 12;
		pDoc.writeVarInt(smpNum44k, seek);

		pDoc.write(unitNum);
		numSeek = seek;
		seek += 1;

		for (u = 0; u < unitNum; u++) {
			pU = &units[u];
			if (pU.bEnable) {
				// フラグ
				flags = makeFlags(pU);
				pDoc.writeVarInt(flags, seek);
				if (flags & noiseEditFlag.envelope) {
					pDoc.writeVarInt(pU.enveNum, seek);
					for (e = 0; e < pU.enveNum; e++) {
						pDoc.writeVarInt(pU.enves[e].x, seek);
						pDoc.writeVarInt(pU.enves[e].y, seek);
					}
				}
				if (flags & noiseEditFlag.pan) {
					_byte = cast(char) pU.pan;
					pDoc.write(_byte);
					seek++;
				}
				if (flags & noiseEditFlag.oscillatorMain) {
					writeOscillator(&pU.main, pDoc, seek);
				}
				if (flags & noiseEditFlag.oscillatorFreq) {
					writeOscillator(&pU.freq, pDoc, seek);
				}
				if (flags & noiseEditFlag.oscillatorVolume) {
					writeOscillator(&pU.volu, pDoc, seek);
				}
				unitNum++;
			}
		}

		// update unitNum.
		pDoc.seek(PxtnSeek.cur, numSeek - seek);
		pDoc.write(unitNum);
		pDoc.seek(PxtnSeek.cur, seek - numSeek - 1);
		pAdd = seek;

		bRet = true;
	end:

		if (!bRet) {
			throw new PxtoneException("");
		}
	}

	void read(ref PxtnDescriptor pDoc) @safe {
		uint flags = 0;
		char unitNum = 0;
		char _byte = 0;
		uint ver = 0;

		PxNoiseDesignUnit* pU = null;

		char[8] code = 0;

		release();

		scope(failure) {
			release();
		}
		pDoc.read(code[]);
		if (code != identifierCode[0 .. 8]) {
			throw new PxtoneException("inv code");
		}
		pDoc.read(ver);
		if (ver > currentVersion) {
			throw new PxtoneException("fmt new");
		}
		pDoc.readVarInt(smpNum44k);
		pDoc.read(unitNum);
		if (unitNum < 0) {
			throw new PxtoneException("inv data");
		}
		if (unitNum > maxNoiseEditUnitNum) {
			throw new PxtoneException("fmt unknown");
		}
		this.unitNum = unitNum;

		units = new PxNoiseDesignUnit[](unitNum);

		for (int u = 0; u < unitNum; u++) {
			pU = &units[u];
			pU.bEnable = true;

			pDoc.readVarInt(flags);
			if (flags & noiseEditFlag.uncovered) {
				throw new PxtoneException("fmt unknown");
			}

			// envelope
			if (flags & noiseEditFlag.envelope) {
				pDoc.readVarInt(pU.enveNum);
				if (pU.enveNum > maxNoiseEditEnvelopeNum) {
					throw new PxtoneException("fmt unknown");
				}
				pU.enves = new PxtnPoint[](pU.enveNum);
				for (int e = 0; e < pU.enveNum; e++) {
					pDoc.readVarInt(pU.enves[e].x);
					pDoc.readVarInt(pU.enves[e].y);
				}
			}
			// pan
			if (flags & noiseEditFlag.pan) {
				pDoc.read(_byte);
				pU.pan = _byte;
			}

			if (flags & noiseEditFlag.oscillatorMain) {
				readOscillator(&pU.main, pDoc);
			}
			if (flags & noiseEditFlag.oscillatorFreq) {
				readOscillator(&pU.freq, pDoc);
			}
			if (flags & noiseEditFlag.oscillatorVolume) {
				readOscillator(&pU.volu, pDoc);
			}
		}
	}

	void release() nothrow @safe {
		if (units) {
			units = null;
			unitNum = 0;
		}
	}

	bool allocate(int unitNum, int envelopeNum) nothrow @safe {
		bool bRet = false;

		release();

		this.unitNum = unitNum;
		units = new PxNoiseDesignUnit[](unitNum);
		if (!units) {
			goto end;
		}

		for (int u = 0; u < unitNum; u++) {
			PxNoiseDesignUnit* pUnit = &units[u];
			pUnit.enveNum = envelopeNum;
			pUnit.enves = new PxtnPoint[](pUnit.enveNum);
			if (!pUnit.enves) {
				goto end;
			}
		}

		bRet = true;
	end:
		if (!bRet) {
			release();
		}

		return bRet;
	}

	bool copy(ref PxtnPulseNoise pDst) const nothrow @safe {
		bool bRet = false;

		pDst.release();
		pDst.smpNum44k = smpNum44k;

		if (unitNum) {
			int enveNum = units[0].enveNum;
			if (!pDst.allocate(unitNum, enveNum)) {
				goto end;
			}
			for (int u = 0; u < unitNum; u++) {
				pDst.units[u].bEnable = units[u].bEnable;
				pDst.units[u].enveNum = units[u].enveNum;
				pDst.units[u].freq = units[u].freq;
				pDst.units[u].main = units[u].main;
				pDst.units[u].pan = units[u].pan;
				pDst.units[u].volu = units[u].volu;
				pDst.units[u].enves = new PxtnPoint[](enveNum);
				if (!pDst.units[u].enves) {
					goto end;
				}
				for (int e = 0; e < enveNum; e++) {
					pDst.units[u].enves[e] = units[u].enves[e];
				}
			}
		}

		bRet = true;
	end:
		if (!bRet) {
			pDst.release();
		}

		return bRet;
	}

	int compare(const(PxtnPulseNoise)* pSrc) const nothrow @safe {
		if (!pSrc) {
			return -1;
		}

		if (pSrc.smpNum44k != smpNum44k) {
			return 1;
		}
		if (pSrc.unitNum != unitNum) {
			return 1;
		}

		for (int u = 0; u < unitNum; u++) {
			if (pSrc.units[u].bEnable != units[u].bEnable) {
				return 1;
			}
			if (pSrc.units[u].enveNum != units[u].enveNum) {
				return 1;
			}
			if (pSrc.units[u].pan != units[u].pan) {
				return 1;
			}
			if (compareOscillator(&pSrc.units[u].main, &units[u].main)) {
				return 1;
			}
			if (compareOscillator(&pSrc.units[u].freq, &units[u].freq)) {
				return 1;
			}
			if (compareOscillator(&pSrc.units[u].volu, &units[u].volu)) {
				return 1;
			}

			for (int e = 0; e < units[u].enveNum; e++) {
				if (units[u].enves[e].x != units[u].enves[e].x) {
					return 1;
				}
				if (units[u].enves[e].y != units[u].enves[e].y) {
					return 1;
				}
			}
		}
		return 0;
	}

	void fix() nothrow @safe {
		PxNoiseDesignUnit* pUnit;
		int i, e;

		if (smpNum44k > noiseDesignLimitSmpnum) {
			smpNum44k = noiseDesignLimitSmpnum;
		}

		for (i = 0; i < unitNum; i++) {
			pUnit = &units[i];
			if (pUnit.bEnable) {
				for (e = 0; e < pUnit.enveNum; e++) {
					if (pUnit.enves[e].x > noiseDesignLimitEnveX) {
						pUnit.enves[e].x = noiseDesignLimitEnveX;
					}
					if (pUnit.enves[e].x < 0) {
						pUnit.enves[e].x = 0;
					}
					if (pUnit.enves[e].y > noiseDesignLimitEnveY) {
						pUnit.enves[e].y = noiseDesignLimitEnveY;
					}
					if (pUnit.enves[e].y < 0) {
						pUnit.enves[e].y = 0;
					}
				}
				if (pUnit.pan < -100) {
					pUnit.pan = -100;
				}
				if (pUnit.pan > 100) {
					pUnit.pan = 100;
				}
				fixUnit(&pUnit.main);
				fixUnit(&pUnit.freq);
				fixUnit(&pUnit.volu);
			}
		}
	}

	void setSmpNum44k(int num) nothrow @safe {
		smpNum44k = num;
	}

	int getUnitNum() const nothrow @safe {
		return unitNum;
	}

	int getSmpNum44k() const nothrow @safe {
		return smpNum44k;
	}

	float getSec() const nothrow @safe {
		return cast(float) smpNum44k / 44100;
	}

	PxNoiseDesignUnit* getUnit(int u) nothrow @safe {
		if (!units || u < 0 || u >= unitNum) {
			return null;
		}
		return &units[u];
	}
}
