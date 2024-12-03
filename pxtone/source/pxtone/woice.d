module pxtone.woice;
// '12/03/03 pxtnWoice.

import pxtone.pxtn;

import pxtone.descriptor;
import pxtone.error;
import pxtone.evelist;
import pxtone.pulse.noise;
import pxtone.pulse.noisebuilder;
import pxtone.pulse.oscillator;
import pxtone.pulse.pcm;
import pxtone.pulse.oggv;
import pxtone.util;
import pxtone.woiceptv;

enum pxtnMaxTuneWoiceName = 16; // fixture.

enum pxtnMaxUnitControlVoice = 2; // max-woice per unit

enum pxtnBufferSizeTimePan = 0x40;
enum pxtnBitsPerSample = 16;

enum PTVVoiceFlag {
	waveLoop = 0x00000001,
	smooth = 0x00000002,
	beatFit = 0x00000004,
	uncovered = 0xfffffff8,
}

enum PTVDataFlag {
	wave = 0x00000001,
	envelope = 0x00000002,
	uncovered = 0xfffffffc,
}

immutable identifierCode = "PTVOICE-";

enum PxtnWoiceType {
	none = 0,
	pcm,
	ptv,
	ptn,
	oggVorbis,
}

enum PxtnVoiceType {
	coordinate = 0,
	overtone,
	noise,
	sampling,
	oggVorbis,
}

struct PxtnVoiceInstance {
	int sampleHead;
	int sampleBody;
	int sampleTail;
	ubyte[] sample;

	ubyte[] envelope;
	int envelopeSize;
	int envelopeRelease;
}

struct PxtnVoiceEnvelope {
	int fps;
	int headNumber;
	int bodyNumber;
	int tailNumber;
	PxtnPoint[] points;
}

struct PxtnVoiceWave {
	int num;
	int reso; // COORDINATE RESOLUTION
	PxtnPoint[] points;
}

struct PxtnVoiceUnit {
	int basicKey;
	int volume;
	int pan;
	float tuning;
	uint voiceFlags;
	uint dataFlags;

	PxtnVoiceType type;
	PxtnPulsePCM pcm;
	PxtnPulseNoise ptn;
	version (WithOggVorbis) {
		PxtnPulseOggv oggV;
	}

	PxtnVoiceWave wave;
	PxtnVoiceEnvelope envelope;
}

struct PxtnVoiceTone {
	double samplePosition;
	float offsetFreq;
	int envelopeVolume;
	int lifeCount;
	int onCount;

	int sampleCount;
	int envelopeStart;
	int envelopePosition;
	int envelopeReleaseClock;

	int smoothVolume;
}

private void voiceRelease(PxtnVoiceUnit* voiceUnit, PxtnVoiceInstance* voiceInstance) nothrow @safe {
	if (voiceUnit) {
		voiceUnit.envelope.points = null;
		voiceUnit.envelope = PxtnVoiceEnvelope.init;
		voiceUnit.wave.points = null;
		voiceUnit.wave = PxtnVoiceWave.init;
	}
	if (voiceInstance) {
		voiceInstance.envelope = null;
		voiceInstance.sample = null;
		*voiceInstance = PxtnVoiceInstance.init;
	}
}

private void updateWavePTV(PxtnVoiceUnit* voiceUnit, PxtnVoiceInstance* voiceInstance, int ch, int sps, int bps) nothrow @safe {
	double work, osc;
	int longTmp;
	int[2] panVolume = [64, 64];
	bool overtone;

	PxtnPulseOscillator osci;

	if (ch == 2) {
		if (voiceUnit.pan > 64) {
			panVolume[0] = (128 - voiceUnit.pan);
		}
		if (voiceUnit.pan < 64) {
			panVolume[1] = (voiceUnit.pan);
		}
	}

	osci.readyGetSample(voiceUnit.wave.points, voiceUnit.wave.num, voiceUnit.volume, voiceInstance.sampleBody, voiceUnit.wave.reso);

	if (voiceUnit.type == PxtnVoiceType.overtone) {
		overtone = true;
	} else {
		overtone = false;
	}

	//  8bit
	if (bps == 8) {
		ubyte[] p = voiceInstance.sample;
		for (int s = 0; s < voiceInstance.sampleBody; s++) {
			if (overtone) {
				osc = osci.getOneSampleOvertone(s);
			} else {
				osc = osci.getOneSampleCoordinate(s);
			}
			for (int c = 0; c < ch; c++) {
				work = osc * panVolume[c] / 64;
				if (work > 1.0) {
					work = 1.0;
				}
				if (work < -1.0) {
					work = -1.0;
				}
				longTmp = cast(int)(work * 127);
				p[s * ch + c] = cast(ubyte)(longTmp + 128);
			}
		}

		// 16bit
	} else {
		short[] p = cast(short[]) voiceInstance.sample;
		for (int s = 0; s < voiceInstance.sampleBody; s++) {
			if (overtone) {
				osc = osci.getOneSampleOvertone(s);
			} else {
				osc = osci.getOneSampleCoordinate(s);
			}
			for (int c = 0; c < ch; c++) {
				work = osc * panVolume[c] / 64;
				if (work > 1.0) {
					work = 1.0;
				}
				if (work < -1.0) {
					work = -1.0;
				}
				longTmp = cast(int)(work * 32767);
				p[s * ch + c] = cast(short) longTmp;
			}
		}
	}
}

// 24byte =================
struct MaterialStructPCM {
	ushort x3xUnitNumber;
	ushort basicKey;
	uint voiceFlags;
	ushort ch;
	ushort bps;
	uint sps;
	float tuning = 0.0;
	uint dataSize;
}

/////////////
// matePTN
/////////////

// 16byte =================
struct MaterialStructPTN {
	ushort x3xUnitNumber;
	ushort basicKey;
	uint voiceFlags;
	float tuning = 0.0;
	int rrr; // 0: -v.0.9.2.3
	// 1:  v.0.9.2.4-
}

/////////////////
// matePTV
/////////////////

// 24byte =================
struct MaterialStructPTV {
	ushort x3xUnitNumber;
	ushort rrr;
	float x3xTuning = 0.0;
	int size;
}

//////////////////////
// mateOGGV
//////////////////////

// 16byte =================
struct MaterialStructOGGV {
	ushort xxx; //ch;
	ushort basicKey;
	uint voiceFlags;
	float tuning = 0.0;
}

////////////////////////
// publics..
////////////////////////

struct pxtnWoice {
package:
	int voiceNum;

	char[pxtnMaxTuneWoiceName + 1] nameBuffer;
	uint nameSize;

	PxtnWoiceType type = PxtnWoiceType.none;
	PxtnVoiceUnit[] voices;
	PxtnVoiceInstance[] voiceInstances;

	float x3xTuning;
	int x3xBasicKey; // tuning old-fmt when key-event

public:

	 ~this() nothrow @safe {
		voiceRelease();
	}

	int getVoiceNum() const nothrow @safe {
		return voiceNum;
	}

	float getX3xTuning() const nothrow @safe {
		return x3xTuning;
	}

	int getX3xBasicKey() const nothrow @safe {
		return x3xBasicKey;
	}

	PxtnWoiceType getType() const nothrow @safe {
		return type;
	}

	inout(PxtnVoiceUnit)* getVoice(int idx) inout nothrow @safe {
		if (idx < 0 || idx >= voiceNum) {
			return null;
		}
		return &voices[idx];
	}

	const(PxtnVoiceInstance)* getInstance(int idx) const nothrow @safe {
		if (idx < 0 || idx >= voiceNum) {
			return null;
		}
		return &voiceInstances[idx];
	}

	bool setNameBuf(const(char)[] name) nothrow @safe {
		if (!name || name.length < 0 || name.length > pxtnMaxTuneWoiceName) {
			return false;
		}
		nameBuffer[] = 0;
		nameSize = cast(uint)name.length;
		if (name.length) {
			nameBuffer[0 .. name.length] = name;
		}
		return true;
	}

	const(char)[] getNameBuf() const return nothrow @safe {
		return nameBuffer[0 .. nameSize];
	}

	bool isNameBuf() const nothrow @safe {
		if (nameSize > 0) {
			return true;
		}
		return false;
	}

	void voiceAllocate(int voiceNum) @safe {
		voiceRelease();

		scope(failure) {
			voiceRelease();
		}
		voices = new PxtnVoiceUnit[](voiceNum);
		voiceInstances = new PxtnVoiceInstance[](voiceNum);
		this.voiceNum = voiceNum;

		for (int i = 0; i < voiceNum; i++) {
			PxtnVoiceUnit* voiceUnit = &voices[i];
			voiceUnit.basicKey = EventDefault.basicKey;
			voiceUnit.volume = 128;
			voiceUnit.pan = 64;
			voiceUnit.tuning = 1.0f;
			voiceUnit.voiceFlags = PTVVoiceFlag.smooth;
			voiceUnit.dataFlags = PTVDataFlag.wave;
			voiceUnit.pcm = PxtnPulsePCM.init;
			voiceUnit.ptn = PxtnPulseNoise.init;
			version (WithOggVorbis) {
				voiceUnit.oggV = PxtnPulseOggv.init;
			}
			voiceUnit.envelope = PxtnVoiceEnvelope.init;
		}
	}

	void voiceRelease() nothrow @safe {
		for (int v = 0; v < voiceNum; v++) {
			.voiceRelease(&voices[v], &voiceInstances[v]);
		}
		voices = null;
		voiceInstances = null;
		voiceNum = 0;
	}

	bool copy(pxtnWoice* pDst) const @safe {
		bool bRet = false;
		int v, num;
		size_t size;
		const(PxtnVoiceUnit)* voiceUnit1 = null;
		PxtnVoiceUnit* voiceUnit2 = null;

		pDst.voiceAllocate(voiceNum);
		scope(failure) {
			pDst.voiceRelease();
		}

		pDst.type = type;

		pDst.nameBuffer = nameBuffer;

		for (v = 0; v < voiceNum; v++) {
			voiceUnit1 = &voices[v];
			voiceUnit2 = &pDst.voices[v];

			voiceUnit2.tuning = voiceUnit1.tuning;
			voiceUnit2.dataFlags = voiceUnit1.dataFlags;
			voiceUnit2.basicKey = voiceUnit1.basicKey;
			voiceUnit2.pan = voiceUnit1.pan;
			voiceUnit2.type = voiceUnit1.type;
			voiceUnit2.voiceFlags = voiceUnit1.voiceFlags;
			voiceUnit2.volume = voiceUnit1.volume;

			// envelope
			voiceUnit2.envelope.bodyNumber = voiceUnit1.envelope.bodyNumber;
			voiceUnit2.envelope.fps = voiceUnit1.envelope.fps;
			voiceUnit2.envelope.headNumber = voiceUnit1.envelope.headNumber;
			voiceUnit2.envelope.tailNumber = voiceUnit1.envelope.tailNumber;
			num = voiceUnit2.envelope.headNumber + voiceUnit2.envelope.bodyNumber + voiceUnit2.envelope.tailNumber;
			size = PxtnPoint.sizeof * num;
			voiceUnit2.envelope.points = new PxtnPoint[](size / PxtnPoint.sizeof);
			if (!voiceUnit2.envelope.points) {
				goto End;
			}
			voiceUnit2.envelope.points[0 .. size] = voiceUnit1.envelope.points[0 .. size];

			// wave
			voiceUnit2.wave.num = voiceUnit1.wave.num;
			voiceUnit2.wave.reso = voiceUnit1.wave.reso;
			size = PxtnPoint.sizeof * voiceUnit2.wave.num;
			voiceUnit2.wave.points = new PxtnPoint[](size / PxtnPoint.sizeof);
			if (!voiceUnit2.wave.points) {
				goto End;
			}
			voiceUnit2.wave.points[0 .. size] = voiceUnit1.wave.points[0 .. size];

			voiceUnit1.pcm.copy(voiceUnit2.pcm);
			if (!voiceUnit1.ptn.copy(voiceUnit2.ptn)) {
				goto End;
			}
			version (WithOggVorbis) {
				if (!voiceUnit1.oggV.copy(voiceUnit2.oggV)) {
					goto End;
				}
			}
		}

		bRet = true;
	End:
		if (!bRet) {
			pDst.voiceRelease();
		}

		return bRet;
	}

	void slim() nothrow @safe {
		for (int i = voiceNum - 1; i >= 0; i--) {
			bool bRemove = false;

			if (!voices[i].volume) {
				bRemove = true;
			}

			if (voices[i].type == PxtnVoiceType.coordinate && voices[i].wave.num <= 1) {
				bRemove = true;
			}

			if (bRemove) {
				.voiceRelease(&voices[i], &voiceInstances[i]);
				voiceNum--;
				for (int j = i; j < voiceNum; j++) {
					voices[j] = voices[j + 1];
				}
				voices[voiceNum] = PxtnVoiceUnit.init;
			}
		}
	}

	void read(ref PxtnDescriptor desc, PxtnWoiceType type) @safe {
		switch (type) {
			// PCM
		case PxtnWoiceType.pcm: {
				PxtnVoiceUnit* voiceUnit;
				voiceAllocate(1);
				voiceUnit = &voices[0];
				voiceUnit.type = PxtnVoiceType.sampling;
				voiceUnit.pcm.read(desc);
				// if under 0.005 sec, set LOOP.
				if (voiceUnit.pcm.getSec() < 0.005f) {
					voiceUnit.voiceFlags |= PTVVoiceFlag.waveLoop;
				} else {
					voiceUnit.voiceFlags &= ~PTVVoiceFlag.waveLoop;
				}
				this.type = PxtnWoiceType.pcm;
			}
			break;

			// PTV
		case PxtnWoiceType.ptv: {
				ptvRead(desc);
			}
			break;

			// PTN
		case PxtnWoiceType.ptn:
			voiceAllocate(1);
			{
				PxtnVoiceUnit* voiceUnit = &voices[0];
				voiceUnit.type = PxtnVoiceType.noise;
				voiceUnit.ptn.read(desc);
				this.type = PxtnWoiceType.ptn;
			}
			break;

			// OGGV
		case PxtnWoiceType.oggVorbis:
			version (WithOggVorbis) {
				voiceAllocate(1);
				{
					PxtnVoiceUnit* voiceUnit;
					voiceUnit = &voices[0];
					voiceUnit.type = PxtnVoiceType.oggVorbis;
					voiceUnit.oggV.oggRead(desc);
					this.type = PxtnWoiceType.oggVorbis;
				}
				break;
			} else {
				throw new PxtoneException("Ogg Vorbis support is required");
			}

		default:
			throw new PxtoneException("Unknown woice type");
		}
	}

	bool ptvWrite(ref PxtnDescriptor pDoc, scope int* pTotal) const @safe {
		bool bRet = false;
		const(PxtnVoiceUnit)* voiceUnit = null;
		uint work = 0;
		int v = 0;
		int total = 0;

		pDoc.write(identifierCode);
		pDoc.write(expectedVersion);
		pDoc.write(total);

		work = 0;

		// pPtv. (5)
		pDoc.writeVarInt(work, total);
		pDoc.writeVarInt(work, total);
		pDoc.writeVarInt(work, total);
		pDoc.writeVarInt(voiceNum, total);

		for (v = 0; v < voiceNum; v++) {
			// pPtvv. (9)
			voiceUnit = &voices[v];
			if (!voiceUnit) {
				goto End;
			}

			pDoc.writeVarInt(voiceUnit.basicKey, total);
			pDoc.writeVarInt(voiceUnit.volume, total);
			pDoc.writeVarInt(voiceUnit.pan, total);
			work = reinterpretFloat(voiceUnit.tuning);
			pDoc.writeVarInt(work, total);
			pDoc.writeVarInt(voiceUnit.voiceFlags, total);
			pDoc.writeVarInt(voiceUnit.dataFlags, total);

			if (voiceUnit.dataFlags & PTVDataFlag.wave) {
				writeWave(pDoc, voiceUnit, total);
			}
			if (voiceUnit.dataFlags & PTVDataFlag.envelope) {
				writeEnvelope(pDoc, voiceUnit, total);
			}
		}

		// total size
		pDoc.seek(PxtnSeek.cur, -(total + 4));
		pDoc.write(total);
		pDoc.seek(PxtnSeek.cur, total);

		if (pTotal) {
			*pTotal = 16 + total;
		}
		bRet = true;
	End:

		return bRet;
	}

	void ptvRead(ref PxtnDescriptor pDoc) @safe {
		PxtnVoiceUnit* voiceUnit = null;
		ubyte[8] code = 0;
		int gotVersion = 0;
		int work1 = 0;
		int work2 = 0;
		int total = 0;
		int num = 0;

		pDoc.read(code[]);
		pDoc.read(gotVersion);
		if (code[0 .. 8] != identifierCode) {
			throw new PxtoneException("inv code");
		}
		pDoc.read(total);
		if (gotVersion > expectedVersion) {
			throw new PxtoneException("fmt new");
		}

		// pPtv. (5)
		pDoc.readVarInt(x3xBasicKey);
		pDoc.readVarInt(work1);
		pDoc.readVarInt(work2);
		if (work1 || work2) {
			throw new PxtoneException("fmt unknown");
		}
		pDoc.readVarInt(num);
		voiceAllocate(num);

		for (int v = 0; v < voiceNum; v++) {
			// pPtvv. (8)
			voiceUnit = &voices[v];
			if (!voiceUnit) {
				throw new PxtoneException("FATAL");
			}
			pDoc.readVarInt(voiceUnit.basicKey);
			pDoc.readVarInt(voiceUnit.volume);
			pDoc.readVarInt(voiceUnit.pan);
			pDoc.readVarInt(work1);
			voiceUnit.tuning = reinterpretInt(work1);
			pDoc.readVarInt(*cast(int*)&voiceUnit.voiceFlags);
			pDoc.readVarInt(*cast(int*)&voiceUnit.dataFlags);

			// no support.
			if (voiceUnit.voiceFlags & PTVVoiceFlag.uncovered) {
				throw new PxtoneException("fmt unknown");
			}
			if (voiceUnit.dataFlags & PTVDataFlag.uncovered) {
				throw new PxtoneException("fmt unknown");
			}
			if (voiceUnit.dataFlags & PTVDataFlag.wave) {
				readWave(pDoc, voiceUnit);
			}
			if (voiceUnit.dataFlags & PTVDataFlag.envelope) {
				readEnvelope(pDoc, voiceUnit);
			}
		}
		type = PxtnWoiceType.ptv;
	}

	void ioMatePCMWrite(ref PxtnDescriptor pDoc) const @safe {
		const PxtnPulsePCM* pulsePCM = &voices[0].pcm;
		const(PxtnVoiceUnit)* voiceUnit = &voices[0];
		MaterialStructPCM pcm;

		pcm.sps = cast(uint) pulsePCM.getSPS();
		pcm.bps = cast(ushort) pulsePCM.getBPS();
		pcm.ch = cast(ushort) pulsePCM.getChannels();
		pcm.dataSize = cast(uint) pulsePCM.getBufferSize();
		pcm.x3xUnitNumber = cast(ushort) 0;
		pcm.tuning = voiceUnit.tuning;
		pcm.voiceFlags = voiceUnit.voiceFlags;
		pcm.basicKey = cast(ushort) voiceUnit.basicKey;

		uint size = cast(uint)(MaterialStructPCM.sizeof + pcm.dataSize);
		pDoc.write(size);
		pDoc.write(pcm);
		pDoc.write(pulsePCM.getPCMBuffer());
	}

	void ioMatePCMRead(ref PxtnDescriptor pDoc) @safe {
		MaterialStructPCM pcm;
		int size = 0;

		pDoc.read(size);
		pDoc.read(pcm);

		if ((cast(int) pcm.voiceFlags) & PTVVoiceFlag.uncovered) {
			throw new PxtoneException("fmt unknown");
		}

		voiceAllocate(1);
		scope(failure) {
			voiceRelease();
		}

		{
			PxtnVoiceUnit* voiceUnit = &voices[0];

			voiceUnit.type = PxtnVoiceType.sampling;

			voiceUnit.pcm.create(pcm.ch, pcm.sps, pcm.bps, pcm.dataSize / (pcm.bps / 8 * pcm.ch));
			pDoc.read(voiceUnit.pcm.getPCMBuffer()[0 .. pcm.dataSize]);
			type = PxtnWoiceType.pcm;

			voiceUnit.voiceFlags = pcm.voiceFlags;
			voiceUnit.basicKey = pcm.basicKey;
			voiceUnit.tuning = pcm.tuning;
			x3xBasicKey = pcm.basicKey;
			x3xTuning = 0;
		}
	}

	void ioMatePTNWrite(ref PxtnDescriptor pDoc) const @safe {
		MaterialStructPTN ptn;
		const(PxtnVoiceUnit)* voiceUnit;
		int size = 0;

		// ptv -------------------------
		ptn.x3xUnitNumber = cast(ushort) 0;

		voiceUnit = &voices[0];
		ptn.tuning = voiceUnit.tuning;
		ptn.voiceFlags = voiceUnit.voiceFlags;
		ptn.basicKey = cast(ushort) voiceUnit.basicKey;
		ptn.rrr = 1;

		// pre
		pDoc.write(size);
		pDoc.write(ptn);
		size += MaterialStructPTN.sizeof;
		voiceUnit.ptn.write(pDoc, size);
		pDoc.seek(PxtnSeek.cur, cast(int)(-size - int.sizeof));
		pDoc.write(size);
		pDoc.seek(PxtnSeek.cur, size);
	}

	void ioMatePTNRead(ref PxtnDescriptor pDoc) @safe {
		MaterialStructPTN ptn;
		int size = 0;

		scope(failure) {
			voiceRelease();
		}
		pDoc.read(size);
		pDoc.read(ptn);

		if (ptn.rrr > 1) {
			throw new PxtoneException("fmt unknown");
		} else if (ptn.rrr < 0) {
			throw new PxtoneException("fmt unknown");
		}

		voiceAllocate(1);

		{
			PxtnVoiceUnit* voiceUnit = &voices[0];

			voiceUnit.type = PxtnVoiceType.noise;
			voiceUnit.ptn.read(pDoc);
			type = PxtnWoiceType.ptn;
			voiceUnit.voiceFlags = ptn.voiceFlags;
			voiceUnit.basicKey = ptn.basicKey;
			voiceUnit.tuning = ptn.tuning;
		}

		x3xBasicKey = ptn.basicKey;
		x3xTuning = 0;
	}

	bool ioMatePTVWrite(ref PxtnDescriptor pDoc) const @safe {
		MaterialStructPTV ptv;
		int headSize = MaterialStructPTV.sizeof + int.sizeof;
		int size = 0;

		// ptv -------------------------
		ptv.x3xUnitNumber = cast(ushort) 0;
		ptv.x3xTuning = 0; //1.0f;//pW.tuning;
		ptv.size = 0;

		// pre write
		pDoc.write(size);
		pDoc.write(ptv);
		if (!ptvWrite(pDoc, &ptv.size)) {
			return false;
		}

		pDoc.seek(PxtnSeek.cur, -(ptv.size + headSize));

		size = cast(int)(ptv.size + MaterialStructPTV.sizeof);
		pDoc.write(size);
		pDoc.write(ptv);

		pDoc.seek(PxtnSeek.cur, ptv.size);

		return true;
	}

	void ioMatePTVRead(ref PxtnDescriptor pDoc) @safe {
		MaterialStructPTV ptv;
		int size = 0;

		pDoc.read(size);
		pDoc.read(ptv);
		if (ptv.rrr) {
			throw new PxtoneException("fmt unknown");
		}
		ptvRead(pDoc);

		if (ptv.x3xTuning != 1.0) {
			x3xTuning = ptv.x3xTuning;
		} else {
			x3xTuning = 0;
		}
	}

	version (WithOggVorbis) {
		bool ioMateOGGVWrite(ref PxtnDescriptor pDoc) const @safe {
			if (!voices) {
				return false;
			}

			MaterialStructOGGV mate;
			const(PxtnVoiceUnit)* voiceUnit = &voices[0];

			int oggVSize = voiceUnit.oggV.getSize();

			mate.tuning = voiceUnit.tuning;
			mate.voiceFlags = voiceUnit.voiceFlags;
			mate.basicKey = cast(ushort) voiceUnit.basicKey;

			uint size = cast(uint)(MaterialStructOGGV.sizeof + oggVSize);
			pDoc.write(size);
			pDoc.write(mate);
			voiceUnit.oggV.pxtnWrite(pDoc);

			return true;
		}

		void ioMateOGGVRead(ref PxtnDescriptor pDoc) @safe {
			MaterialStructOGGV mate;
			int size = 0;

			pDoc.read(size);
			pDoc.read(mate);

			if ((cast(int) mate.voiceFlags) & PTVVoiceFlag.uncovered) {
				throw new PxtoneException("fmt unknown");
			}

			voiceAllocate(1);
			scope(failure) {
				voiceRelease();
			}

			{
				PxtnVoiceUnit* voiceUnit = &voices[0];
				voiceUnit.type = PxtnVoiceType.oggVorbis;

				voiceUnit.oggV.pxtnRead(pDoc);

				voiceUnit.voiceFlags = mate.voiceFlags;
				voiceUnit.basicKey = mate.basicKey;
				voiceUnit.tuning = mate.tuning;
			}

			x3xBasicKey = mate.basicKey;
			x3xTuning = 0;
			type = PxtnWoiceType.oggVorbis;
		}
	}

	void toneReadySample(PxtnVoiceInstance[] voinsts, PxtnVoiceUnit[] voices, const PxtnPulseNoiseBuilder ptnBuilder) const @safe {
		PxtnVoiceInstance* voiceInstance = null;
		PxtnVoiceUnit* voiceUnit = null;
		PxtnPulsePCM pcmWork;

		int ch = 2;
		int sps = 44100;
		int bps = 16;

		for (int v = 0; v < voiceNum; v++) {
			voiceInstance = &voinsts[v];
			voiceInstance.sample = null;
			voiceInstance.sampleHead = 0;
			voiceInstance.sampleBody = 0;
			voiceInstance.sampleTail = 0;
		}
		scope (failure) {
			for (int v = 0; v < voiceNum; v++) {
				voiceInstance = &voinsts[v];
				voiceInstance.sample = null;
				voiceInstance.sampleHead = 0;
				voiceInstance.sampleBody = 0;
				voiceInstance.sampleTail = 0;
			}
		}

		for (int v = 0; v < voiceNum; v++) {
			voiceInstance = &voinsts[v];
			voiceUnit = &voices[v];

			switch (voiceUnit.type) {
			case PxtnVoiceType.oggVorbis:

				version (WithOggVorbis) {
					voiceUnit.oggV.decode(pcmWork);
					pcmWork.convert(ch, sps, bps);
					voiceInstance.sampleHead = pcmWork.getSampleHead();
					voiceInstance.sampleBody = pcmWork.getSampleBody();
					voiceInstance.sampleTail = pcmWork.getSampleTail();
					voiceInstance.sample = pcmWork.devolveSamplingBuffer();
					break;
				} else {
					throw new PxtoneException("Ogg Vorbis support is required");
				}

			case PxtnVoiceType.sampling:

				voiceUnit.pcm.copy(pcmWork);
				pcmWork.convert(ch, sps, bps);
				voiceInstance.sampleHead = pcmWork.getSampleHead();
				voiceInstance.sampleBody = pcmWork.getSampleBody();
				voiceInstance.sampleTail = pcmWork.getSampleTail();
				voiceInstance.sample = pcmWork.devolveSamplingBuffer();
				break;

			case PxtnVoiceType.overtone:
			case PxtnVoiceType.coordinate: {
					voiceInstance.sampleBody = 400;
					int size = voiceInstance.sampleBody * ch * bps / 8;
					voiceInstance.sample = new ubyte[](size);
					voiceInstance.sample[0 .. size] = 0x00;
					updateWavePTV(voiceUnit, voiceInstance, ch, sps, bps);
					break;
				}

			case PxtnVoiceType.noise: {
					PxtnPulsePCM pulsePCM = ptnBuilder.buildNoise(voiceUnit.ptn, ch, sps, bps);
					voiceInstance.sample = pulsePCM.devolveSamplingBuffer();
					voiceInstance.sampleBody = voiceUnit.ptn.getSmpNum44k();
					break;
				}
			default:
				break;
			}
		}
	}

	void toneReadyEnvelope(PxtnVoiceInstance[] voinsts, PxtnVoiceUnit[] voices, int sps) const @safe {
		int e = 0;
		PxtnPoint[] pPoint = null;

		scope(failure) {
			for (int v = 0; v < voiceNum; v++) {
				voinsts[v].envelope = null;
			}
		}
		for (int v = 0; v < voiceNum; v++) {
			PxtnVoiceInstance* voiceInstance = &voinsts[v];
			PxtnVoiceUnit* voiceUnit = &voices[v];
			PxtnVoiceEnvelope* pEnve = &voiceUnit.envelope;
			int size = 0;

			voiceInstance.envelope = null;

			if (pEnve.headNumber) {
				for (e = 0; e < pEnve.headNumber; e++) {
					size += pEnve.points[e].x;
				}
				voiceInstance.envelopeSize = cast(int)(cast(double) size * sps / pEnve.fps);
				if (!voiceInstance.envelopeSize) {
					voiceInstance.envelopeSize = 1;
				}

				voiceInstance.envelope = new ubyte[](voiceInstance.envelopeSize);
				pPoint = new PxtnPoint[](pEnve.headNumber);

				// convert points.
				int offset = 0;
				int headNumber = 0;
				for (e = 0; e < pEnve.headNumber; e++) {
					if (!e || pEnve.points[e].x || pEnve.points[e].y) {
						offset += cast(int)(cast(double) pEnve.points[e].x * sps / pEnve.fps);
						pPoint[e].x = offset;
						pPoint[e].y = pEnve.points[e].y;
						headNumber++;
					}
				}

				PxtnPoint start;
				e = start.x = start.y = 0;
				for (int s = 0; s < voiceInstance.envelopeSize; s++) {
					while (e < headNumber && s >= pPoint[e].x) {
						start.x = pPoint[e].x;
						start.y = pPoint[e].y;
						e++;
					}

					if (e < headNumber) {
						voiceInstance.envelope[s] = cast(ubyte)(start.y + (pPoint[e].y - start.y) * (s - start.x) / (pPoint[e].x - start.x));
					} else {
						voiceInstance.envelope[s] = cast(ubyte) start.y;
					}
				}

				pPoint = null;
			}

			if (pEnve.tailNumber) {
				voiceInstance.envelopeRelease = cast(int)(cast(double) pEnve.points[pEnve.headNumber].x * sps / pEnve.fps);
			} else {
				voiceInstance.envelopeRelease = 0;
			}
		}
		pPoint = null;
	}

	void toneReady(pxtnWoice* woice, const PxtnPulseNoiseBuilder ptnBuilder, int sps) const @safe {
		toneReadySample(woice.voiceInstances, woice.voices, ptnBuilder);
		toneReadyEnvelope(woice.voiceInstances, woice.voices, sps);
	}
}
