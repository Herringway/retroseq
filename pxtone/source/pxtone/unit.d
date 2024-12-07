///
module pxtone.unit;
// '12/03/03

import pxtone.pxtn;

import pxtone.descriptor;
import pxtone.error;
import pxtone.evelist;
import pxtone.max;
import pxtone.woice;

import std.exception;

// v1x (20byte) =================
///
struct UnitVersion1 {
	char[pxtnMaxTuneUnitName] name; ///
	ushort type; ///
	ushort group; ///
}

///////////////////
// pxtnUNIT x3x
///////////////////

///
struct Unit {
	ushort type; ///
	ushort group; ///
}

///
struct PxtnUnit {
private:
	bool bOperated = true; ///
	bool bPlayed = true; ///
	char[pxtnMaxTuneUnitName + 1] nameBuf = "no name"; ///
	int nameSize = "no name".length; ///

	//	TUNEUNITTONESTRUCT
	int keyNow; ///
	int keyStart; ///
	int keyMargin; ///
	int portamentSamplePos; ///
	int portamentSampleNum; ///
	int[pxtnMaxChannel] panVols; ///
	int[pxtnMaxChannel] panTimes; ///
	int[pxtnBufferSizeTimePan][pxtnMaxChannel] panTimeBufs; ///
	int volume; ///
	int velocity; ///
	int groupNumber; ///
	float tuning = 0.0; ///

	const(pxtnWoice)* woice; ///

	PxtnVoiceTone[pxtnMaxUnitControlVoice] vts; ///

public:
	///
	void toneInit() nothrow @safe {
		groupNumber = EventDefault.groupNumber;
		velocity = EventDefault.velocity;
		volume = EventDefault.volume;
		tuning = EventDefault.tuning;
		portamentSampleNum = 0;
		portamentSamplePos = 0;

		for (int i = 0; i < pxtnMaxChannel; i++) {
			panVols[i] = 64;
			panTimes[i] = 0;
		}
	}

	///
	void toneClear() nothrow @safe {
		for (int i = 0; i < pxtnMaxChannel; i++) {
			panTimeBufs[i][0 .. pxtnBufferSizeTimePan] = 0;
		}
	}

	///
	void toneResetAnd2prm(int voiceIndex, int envRlsClock, float offsetFreq) nothrow @safe {
		PxtnVoiceTone* pTone = &vts[voiceIndex];
		pTone.lifeCount = 0;
		pTone.onCount = 0;
		pTone.samplePosition = 0;
		pTone.smoothVolume = 0;
		pTone.envelopeReleaseClock = envRlsClock;
		pTone.offsetFreq = offsetFreq;
	}

	void toneEnvelope() nothrow @safe {
		if (!woice) {
			return;
		}

		for (int v = 0; v < woice.getVoiceNum(); v++) {
			const PxtnVoiceInstance* pVi = woice.getInstance(v);
			PxtnVoiceTone* pVt = &vts[v];

			if (pVt.lifeCount > 0 && pVi.envelopeSize) {
				if (pVt.onCount > 0) {
					if (pVt.envelopePosition < pVi.envelopeSize) {
						pVt.envelopeVolume = pVi.envelope[pVt.envelopePosition];
						pVt.envelopePosition++;
					}
				}  // release.
				else {
					pVt.envelopeVolume = pVt.envelopeStart + (0 - pVt.envelopeStart) * pVt.envelopePosition / pVi.envelopeRelease;
					pVt.envelopePosition++;
				}
			}
		}
	}

	///
	void toneKeyOn() nothrow @safe {
		keyNow = keyStart + keyMargin;
		keyStart = keyNow;
		keyMargin = 0;
	}

	///
	void toneZeroLives() nothrow @safe {
		for (int i = 0; i < pxtnMaxChannel; i++) {
			vts[i].lifeCount = 0;
		}
	}

	///
	void toneKey(int key) nothrow @safe {
		keyStart = keyNow;
		keyMargin = key - keyStart;
		portamentSamplePos = 0;
	}

	///
	void tonePanVolume(int ch, int pan) nothrow @safe {
		panVols[0] = 64;
		panVols[1] = 64;
		if (ch == 2) {
			if (pan >= 64) {
				panVols[0] = 128 - pan;
			} else {
				panVols[1] = pan;
			}
		}
	}

	///
	void tonePanTime(int ch, int pan, int sps) nothrow @safe {
		panTimes[0] = 0;
		panTimes[1] = 0;

		if (ch == 2) {
			if (pan >= 64) {
				panTimes[0] = pan - 64;
				if (panTimes[0] > 63) {
					panTimes[0] = 63;
				}
				panTimes[0] = (panTimes[0] * 44100) / sps;
			} else {
				panTimes[1] = 64 - pan;
				if (panTimes[1] > 63) {
					panTimes[1] = 63;
				}
				panTimes[1] = (panTimes[1] * 44100) / sps;
			}
		}
	}

	///
	void toneVelocity(int val) nothrow @safe {
		velocity = val;
	}

	///
	void toneVolume(int val) nothrow @safe {
		volume = val;
	}

	///
	void tonePortament(int val) nothrow @safe {
		portamentSampleNum = val;
	}

	///
	void toneGroupNumber(int val) nothrow @safe {
		groupNumber = val;
	}

	///
	void toneTuning(float val) nothrow @safe {
		tuning = val;
	}

	///
	void toneSample(bool bMuteByUnit, int channels, int timePanIndex, int smoothSample) nothrow @safe {
		if (!woice) {
			return;
		}

		if (bMuteByUnit && !bPlayed) {
			for (int ch = 0; ch < channels; ch++) {
				panTimeBufs[ch][timePanIndex] = 0;
			}
			return;
		}

		for (int ch = 0; ch < pxtnMaxChannel; ch++) {
			int timePanBuffer = 0;

			for (int v = 0; v < woice.getVoiceNum(); v++) {
				PxtnVoiceTone* pVt = &vts[v];
				const PxtnVoiceInstance* pVi = woice.getInstance(v);

				int work = 0;

				if (pVt.lifeCount > 0) {
					int pos = cast(int) pVt.samplePosition * 2 + ch;
					work += (cast(const(short)[])pVi.sample)[pos];

					if (channels == 1) {
						work += (cast(const(short)[])pVi.sample)[pos + 1];
						work = work / 2;
					}

					work = (work * velocity) / 128;
					work = (work * volume) / 128;
					work = work * panVols[ch] / 64;

					if (pVi.envelopeSize) {
						work = work * pVt.envelopeVolume / 128;
					}

					// smooth tail
					if (woice.getVoice(v).voiceFlags & PTVVoiceFlag.smooth && pVt.lifeCount < smoothSample) {
						work = work * pVt.lifeCount / smoothSample;
					}
				}
				timePanBuffer += work;
			}
			panTimeBufs[ch][timePanIndex] = timePanBuffer;
		}
	}

	///
	void toneSupple(int[] groupSamples, int ch, int timePanIndex) const nothrow @safe {
		int idx = (timePanIndex - panTimes[ch]) & (pxtnBufferSizeTimePan - 1);
		groupSamples[groupNumber] += panTimeBufs[ch][idx];
	}

	///
	int toneIncrementKey() nothrow @safe {
		// prtament..
		if (portamentSampleNum && keyMargin) {
			if (portamentSamplePos < portamentSampleNum) {
				portamentSamplePos++;
				keyNow = cast(int)(keyStart + cast(double) keyMargin * portamentSamplePos / portamentSampleNum);
			} else {
				keyNow = keyStart + keyMargin;
				keyStart = keyNow;
				keyMargin = 0;
			}
		} else {
			keyNow = keyStart + keyMargin;
		}
		return keyNow;
	}

	///
	void toneIncrementSample(float freq) nothrow @safe {
		if (!woice) {
			return;
		}

		for (int v = 0; v < woice.getVoiceNum(); v++) {
			const PxtnVoiceInstance* pVi = woice.getInstance(v);
			PxtnVoiceTone* pVt = &vts[v];

			if (pVt.lifeCount > 0) {
				pVt.lifeCount--;
			}
			if (pVt.lifeCount > 0) {
				pVt.onCount--;

				pVt.samplePosition += pVt.offsetFreq * tuning * freq;

				if (pVt.samplePosition >= pVi.sampleBody) {
					if (woice.getVoice(v).voiceFlags & PTVVoiceFlag.waveLoop) {
						if (pVt.samplePosition >= pVi.sampleBody) {
							pVt.samplePosition -= pVi.sampleBody;
						}
						if (pVt.samplePosition >= pVi.sampleBody) {
							pVt.samplePosition = 0;
						}
					} else {
						pVt.lifeCount = 0;
					}
				}

				// OFF
				if (pVt.onCount == 0 && pVi.envelopeSize) {
					pVt.envelopeStart = pVt.envelopeVolume;
					pVt.envelopePosition = 0;
				}
			}
		}
	}

	///
	bool setWoice(const(pxtnWoice)* woice) nothrow @safe {
		if (!woice) {
			return false;
		}
		this.woice = woice;
		keyNow = EventDefault.key;
		keyMargin = 0;
		keyStart = EventDefault.key;
		return true;
	}

	///
	const(pxtnWoice)* getWoice() const nothrow @safe {
		return woice;
	}

	///
	bool setNameBuf(scope const char[] name) nothrow @safe {
		if (!name || name.length > pxtnMaxTuneUnitName) {
			return false;
		}
		nameBuf[0 .. $] = 0;
		if (name.length) {
			nameBuf[0 .. name.length] = name;
		}
		nameSize = cast(int)name.length;
		return true;
	}

	///
	const(char)[] getNameBuf() const return nothrow @safe {
		return nameBuf[0 .. nameSize];
	}

	///
	bool isNameBuf() const nothrow @safe {
		if (nameSize > 0) {
			return true;
		}
		return false;
	}

	///
	PxtnVoiceTone* getTone(int voiceIndex) return nothrow @safe {
		return &vts[voiceIndex];
	}

	///
	void setOperated(bool b) nothrow @safe {
		bOperated = b;
	}

	///
	void setPlayed(bool b) nothrow @safe {
		bPlayed = b;
	}

	///
	bool getOperated() const nothrow @safe {
		return bOperated;
	}

	///
	bool getPlayed() const nothrow @safe {
		return bPlayed;
	}

	///
	void read(ref PxtnDescriptor pDoc, out int pGroup) @safe {
		Unit unit;
		int size = 0;

		pDoc.read(size);
		pDoc.read(unit);
		if (cast(PxtnWoiceType) unit.type != PxtnWoiceType.pcm && cast(PxtnWoiceType) unit.type != PxtnWoiceType.ptv && cast(PxtnWoiceType) unit.type != PxtnWoiceType.ptn) {
			throw new PxtoneException("fmt unknown");
		}
		pGroup = unit.group;
	}

	///
	void readOld(ref PxtnDescriptor pDoc, out int pGroup) @safe {
		UnitVersion1 unit;
		int size;

		pDoc.read(size);
		pDoc.read(unit);
		enforce(cast(PxtnWoiceType) unit.type == PxtnWoiceType.pcm, new PxtoneException("Expecting a PCM unit"));

		nameBuf[0 .. pxtnMaxTuneUnitName] = unit.name[0 .. pxtnMaxTuneUnitName];
		nameBuf[pxtnMaxTuneUnitName] = '\0';
		pGroup = unit.group;
	}
}
