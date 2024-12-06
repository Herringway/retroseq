module pxtone.service;

import pxtone.pxtn;

import pxtone.descriptor;
import pxtone.pulse.noisebuilder;

import pxtone.error;
import pxtone.max;
import pxtone.text;
import pxtone.delay;
import pxtone.overdrive;
import pxtone.master;
import pxtone.woice;
import pxtone.song;
import pxtone.pulse.frequency;
import pxtone.unit;
import pxtone.evelist;

import std.algorithm.comparison;
import std.exception;
import std.format;
import std.math;
import std.stdio;
import std.typecons;

enum PxtnFlags {
	loop = 1 << 0,
	unitMute = 1 << 1
}

enum versionSize = 16;
enum identifierCodeSize = 8;

//                                       0123456789012345
immutable identifierCodeTuneX2x = "PTTUNE--20050608";
immutable identifierCodeTuneX3x = "PTTUNE--20060115";
immutable identifierCodeTuneX4x = "PTTUNE--20060930";
immutable identifierCodeTuneV5 = "PTTUNE--20071119";

immutable identifierCodeProjectX1x = "PTCOLLAGE-050227";
immutable identifierCodeProjectX2x = "PTCOLLAGE-050608";
immutable identifierCodeProjectX3x = "PTCOLLAGE-060115";
immutable identifierCodeProjectX4x = "PTCOLLAGE-060930";
immutable identifierCodeProjectV5 = "PTCOLLAGE-071119";

immutable identifierCodeX1xPROJ = "PROJECT=";
immutable identifierCodeX1xEVEN = "EVENT===";
immutable identifierCodeX1xUNIT = "UNIT====";
immutable identifierCodeX1xEND = "END=====";
immutable identifierCodeX1xPCM = "matePCM=";

immutable identifierCodeX3xPxtnUNIT = "pxtnUNIT";
immutable identifierCodeX4xEvenMAST = "evenMAST";
immutable identifierCodeX4xEvenUNIT = "evenUNIT";

immutable identifierCodeAntiOPER = "antiOPER"; // anti operation(edit)

immutable identifierCodeNumUNIT = "num UNIT";
immutable identifierCodeMasterV5 = "MasterV5";
immutable identifierCodeEventV5 = "Event V5";
immutable identifierCodeMatePCM = "matePCM ";
immutable identifierCodeMatePTV = "matePTV ";
immutable identifierCodeMatePTN = "matePTN ";
immutable identifierCodeMateOGGV = "mateOGGV";
immutable identifierCodeEffeDELA = "effeDELA";
immutable identifierCodeEffeOVER = "effeOVER";
immutable identifierCodeTextNAME = "textNAME";
immutable identifierCodeTextCOMM = "textCOMM";
immutable identifierCodeAssiUNIT = "assiUNIT";
immutable identifierCodeAssiWOIC = "assiWOIC";
immutable identifierCodePxtoneND = "pxtoneND";

enum Tag {
	Unknown = 0,
	antiOPER,

	x1xPROJ,
	x1xUNIT,
	x1xPCM,
	x1xEVEN,
	x1xEND,
	x3xPxtnUNIT,
	x4xEvenMAST,
	x4xEvenUNIT,

	numUnit,
	MasterV5,
	EventV5,
	matePCM,
	matePTV,
	matePTN,
	mateOGGV,
	effeDELA,
	effeOVER,
	textNAME,
	textCOMM,
	assiUNIT,
	assiWOIC,
	pxtoneND

}


struct AssistWoice {
	ushort woiceIndex;
	ushort rrr;
	char[pxtnMaxTuneWoiceName] name = 0;
}

struct AssistUnit {
	ushort unitIndex;
	ushort rrr;
	char[pxtnMaxTuneUnitName] name = 0;
}

struct NumUnit {
	short num;
	short rrr;
}

// x1x project..------------------

// project (36byte) ================
struct Project {
	char[16] x1xName = 0;

	float x1xBeatTempo = 0.0;
	ushort x1xBeatClock;
	ushort x1xBeatNum;
	ushort x1xBeatNote;
	ushort x1xMeasNum;
	ushort x1xChannelNum;
	ushort x1xBps;
	uint x1xSps;
}

struct pxtnVOMITPREPARATION {
	int startPosMeas = 0;
	int startPosSample = 0;
	float startPosFloat = 0.0;

	int measEnd = 0;
	int measRepeat = 0;
	float fadeInSec = 0.0;

	BitFlags!PxtnFlags flags = PxtnFlags.loop;
	float masterVolume = 1.0;
	invariant {
		import std.math : isNaN;
		assert(!masterVolume.isNaN, "Master volume should never be NaN!");
		assert(!fadeInSec.isNaN, "fadeInSec should never be NaN!");
		assert(!startPosFloat.isNaN, "startPosFloat should never be NaN!");
	}
}

alias pxtnSampledCallback = bool function(void* user, scope const(PxtnService)* pxtn) @safe nothrow;

package enum FMTVER {
	unknown = 0,
	x1x, // has fixed event num of 10000
	x2x, // no version of exe
	x3x, // unit has voice / basic-key for only view
	x4x, // unit has event
	v5,
}
struct PxtnService {
private:

	bool isInitialized;
	bool edit;
	bool fixEventListNumber;

	int outputChannels, outputSamplesPerSecond, outputBytesPerSample;

	PxtnPulseNoiseBuilder pxtnPulseNoiseBuilder;

	PxtnDelay[] delays;
	pxtnOverDrive*[] overdrives;
	pxtnWoice*[] woices;
	PxtnUnit[] units;

	const(PxToneSong)* song;

	//////////////
	// vomit..
	//////////////
	bool songLoaded;
	bool songPlaying = true;
	bool isMooInitialized;

	bool mutedByUnit;
	bool songLooping = true;

	int mooSampleSmooth;
	float mooClockRate; // as the sample
	int mooSampleCount;
	int mooSampleStart;
	int mooSampleEnd;
	int mooSampleRepeat;

	int mooFadeCount;
	int mooFadeMax;
	int mooFadeFade;
	float masterVolume = 1.0f;

	int mooTop;
	float mooSampleStride;
	int mooTimePanIndex;

	float beatTempo;

	// for make now-meas
	int beatClock;
	int beatNum;

	int[] groupSamples;

	const(EveRecord)* currentEventRecords;

	PxtnPulseFrequency* mooFrequency;

	static void loadVorbis() @trusted {
		version (WithOggVorbis) {
			import derelict.vorbis;

			try {
				DerelictVorbis.load();
				DerelictVorbisFile.load();
			} catch (Exception e) {
				throw new PxtoneException("Vorbis library failed to load");
			}
		}
	}

	private void initialize(int fixEvelsNum, bool bEdit) @safe {
		if (isInitialized) {
			throw new PxtoneException("pxtnService not initialized");
		}

		scope(failure) {
			release();
		}

		int byteSize = 0;

		loadVorbis();

		pxtnPulseNoiseBuilder = PxtnPulseNoiseBuilder.init;

		// delay
		delays.reserve(pxtnMaxTuneDelayStruct);

		// over-drive
		overdrives.reserve(pxtnMaxTuneOverdriveStruct);

		// woice
		woices.reserve(pxtnMaxTuneWoiceStruct);

		// unit
		units.reserve(pxtnMaxTuneUnitStruct);

		if (!mooInitialize()) {
			throw new PxtoneException("mooInitialize failed");
		}

		edit = bEdit;
		isInitialized = true;

	}

	private void release() @safe {
		isInitialized = false;

		mooDestructor();

		delays = null;
		overdrives = null;
		woices = null;
		units = null;
	}

	private void mooDestructor() nothrow @safe {
		mooRelease();
	}

	private bool mooInitialize() nothrow @safe {
		bool bRet = false;

		mooFrequency = new PxtnPulseFrequency();
		if (!mooFrequency) {
			goto term;
		}
		groupSamples = new int[](pxtnMaxTuneGroupNumber);
		if (!groupSamples) {
			goto term;
		}

		isMooInitialized = true;
		bRet = true;
	term:
		if (!bRet) {
			mooRelease();
		}

		return bRet;
	}

	private bool mooRelease() nothrow @safe {
		if (!isMooInitialized) {
			return false;
		}
		isMooInitialized = false;
		mooFrequency = null;
		groupSamples = null;
		return true;
	}

	////////////////////////////////////////////////
	// Units   ////////////////////////////////////
	////////////////////////////////////////////////

	private bool mooResetVoiceOn(PxtnUnit* unit, int w) const nothrow @safe {
		if (!isMooInitialized) {
			return false;
		}

		const(PxtnVoiceInstance)* voiceInstance;
		const(PxtnVoiceUnit)* voiceUnit;
		const(pxtnWoice)* woice = woiceGet(w);

		if (!woice) {
			return false;
		}

		unit.setWoice(woice);

		for (int v = 0; v < woice.getVoiceNum(); v++) {
			voiceInstance = woice.getInstance(v);
			voiceUnit = woice.getVoice(v);

			float ofsFreq = 0;
			if (voiceUnit.voiceFlags & PTVVoiceFlag.beatFit) {
				ofsFreq = (voiceInstance.sampleBody * beatTempo) / (44100 * 60 * voiceUnit.tuning);
			} else {
				ofsFreq = mooFrequency.get(EventDefault.basicKey - voiceUnit.basicKey) * voiceUnit.tuning;
			}
			unit.toneResetAnd2prm(v, cast(int)(voiceInstance.envelopeRelease / mooClockRate), ofsFreq);
		}
		return true;
	}

	private bool mooInitUnitTone() nothrow @safe {
		if (!isMooInitialized) {
			return false;
		}
		for (int u = 0; u < units.length; u++) {
			PxtnUnit* unit = unitGet(u);
			unit.toneInit();
			mooResetVoiceOn(unit, EventDefault.voiceNumber);
		}
		return true;
	}

	private bool mooPxtoneSample(scope short[] pData) nothrow @safe {
		if (!isMooInitialized) {
			return false;
		}

		// envelope..
		for (int u = 0; u < units.length; u++) {
			units[u].toneEnvelope();
		}

		int clock = cast(int)(mooSampleCount / mooClockRate);

		// events..
		for (; currentEventRecords && currentEventRecords.clock <= clock; currentEventRecords = currentEventRecords.next) {
			int unitNumber = currentEventRecords.unitNumber;
			PxtnUnit* unit = &units[unitNumber];
			PxtnVoiceTone* tone;
			const(pxtnWoice)* woice;
			const(PxtnVoiceInstance)* voiceInstance;

			switch (currentEventRecords.kind) {
			case EventKind.on: {
					int onCount = cast(int)((currentEventRecords.clock + currentEventRecords.value - clock) * mooClockRate);
					if (onCount <= 0) {
						unit.toneZeroLives();
						break;
					}

					unit.toneKeyOn();

					woice = unit.getWoice();
					if (!(woice)) {
						break;
					}
					for (int v = 0; v < woice.getVoiceNum(); v++) {
						tone = unit.getTone(v);
						voiceInstance = woice.getInstance(v);

						// release..
						if (voiceInstance.envelopeRelease) {
							int maxLifeCount1 = cast(int)((currentEventRecords.value - (clock - currentEventRecords.clock)) * mooClockRate) + voiceInstance.envelopeRelease;
							int maxLifeCount2;
							int c = currentEventRecords.clock + currentEventRecords.value + tone.envelopeReleaseClock;
							const(EveRecord)* next = null;
							for (const(EveRecord)* p = currentEventRecords.next; p; p = p.next) {
								if (p.clock > c) {
									break;
								}
								if (p.unitNumber == unitNumber && p.kind == EventKind.on) {
									next = p;
									break;
								}
							}
							if (!next) {
								maxLifeCount2 = mooSampleEnd - cast(int)(clock * mooClockRate);
							} else {
								maxLifeCount2 = cast(int)((next.clock - clock) * mooClockRate);
							}
							if (maxLifeCount1 < maxLifeCount2) {
								tone.lifeCount = maxLifeCount1;
							} else {
								tone.lifeCount = maxLifeCount2;
							}
						}  // no-release..
						else {
							tone.lifeCount = cast(int)((currentEventRecords.value - (clock - currentEventRecords.clock)) * mooClockRate);
						}

						if (tone.lifeCount > 0) {
							tone.onCount = onCount;
							tone.samplePosition = 0;
							tone.envelopePosition = 0;
							if (voiceInstance.envelopeSize) {
								tone.envelopeVolume = tone.envelopeStart = 0; // envelope
							} else {
								tone.envelopeVolume = tone.envelopeStart = 128; // no-envelope
							}
						}
					}
					break;
				}

			case EventKind.key:
				unit.toneKey(currentEventRecords.value);
				break;
			case EventKind.panVolume:
				unit.tonePanVolume(outputChannels, currentEventRecords.value);
				break;
			case EventKind.panTime:
				unit.tonePanTime(outputChannels, currentEventRecords.value, outputSamplesPerSecond);
				break;
			case EventKind.velocity:
				unit.toneVelocity(currentEventRecords.value);
				break;
			case EventKind.volume:
				unit.toneVolume(currentEventRecords.value);
				break;
			case EventKind.portament:
				unit.tonePortament(cast(int)(currentEventRecords.value * mooClockRate));
				break;
			case EventKind.beatClock:
				break;
			case EventKind.beatTempo:
				break;
			case EventKind.beatNumber:
				break;
			case EventKind.repeat:
				break;
			case EventKind.last:
				break;
			case EventKind.voiceNumber:
				mooResetVoiceOn(unit, currentEventRecords.value);
				break;
			case EventKind.groupNumber:
				unit.toneGroupNumber(currentEventRecords.value);
				break;
			case EventKind.tuning:
				unit.toneTuning(*(cast(const(float)*)(&currentEventRecords.value)));
				break;
			default:
				break;
			}
		}

		// sampling..
		for (int u = 0; u < units.length; u++) {
			units[u].toneSample(mutedByUnit, outputChannels, mooTimePanIndex, mooSampleSmooth);
		}

		for (int ch = 0; ch < outputChannels; ch++) {
			for (int g = 0; g < pxtnMaxTuneGroupNumber; g++) {
				groupSamples[g] = 0;
			}
			for (int u = 0; u < units.length; u++) {
				units[u].toneSupple(groupSamples, ch, mooTimePanIndex);
			}
			for (int o = 0; o < overdrives.length; o++) {
				overdrives[o].toneSupple(groupSamples);
			}
			for (int d = 0; d < delays.length; d++) {
				delays[d].toneSupple(ch, groupSamples);
			}

			// collect.
			int work = 0;
			for (int g = 0; g < pxtnMaxTuneGroupNumber; g++) {
				work += groupSamples[g];
			}

			// fade..
			if (mooFadeFade) {
				work = work * (mooFadeCount >> 8) / mooFadeMax;
			}

			// master volume
			work = cast(int)(work * masterVolume);

			// to buffer..
			if (work > mooTop) {
				work = mooTop;
			}
			if (work < -mooTop) {
				work = -mooTop;
			}
			pData[ch] = cast(short)(work);
		}

		// --------------
		// increments..

		mooSampleCount++;
		mooTimePanIndex = (mooTimePanIndex + 1) & (pxtnBufferSizeTimePan - 1);

		for (int u = 0; u < units.length; u++) {
			int keyNow = units[u].toneIncrementKey();
			units[u].toneIncrementSample(mooFrequency.get2(keyNow) * mooSampleStride);
		}

		// delay
		for (int d = 0; d < delays.length; d++) {
			delays[d].toneIncrement();
		}

		// fade out
		if (mooFadeFade < 0) {
			if (mooFadeCount > 0) {
				mooFadeCount--;
			} else {
				return false;
			}
		}  // fade in
		else if (mooFadeFade > 0) {
			if (mooFadeCount < (mooFadeMax << 8)) {
				mooFadeCount++;
			} else {
				mooFadeFade = 0;
			}
		}

		if (mooSampleCount >= mooSampleEnd) {
			if (!songLooping) {
				return false;
			}
			mooSampleCount = mooSampleRepeat;
			currentEventRecords = song.evels.getRecords();
			mooInitUnitTone();
		}
		return true;
	}

	pxtnSampledCallback sampledCallback;
	void* sampledCallbackUserData;

public:

	void load(const PxToneSong song) @safe {
		this.song = &[song][0];
		delays = new PxtnDelay[](song.delays.length);
		foreach (idx, ref delay; delays) {
			const dela = song.delays[idx];
			delay.set(cast(DelayUnit)dela.unit, dela.freq, dela.rate, dela.group);
		}
		overdrives = new pxtnOverDrive*[](song.overdrives.length);
		foreach (idx, ref overdrive; overdrives) {
			const songOverdrive = song.overdrives[idx];
			overdrive = new pxtnOverDrive;
			overdrive.played = songOverdrive.played;
			overdrive.group = songOverdrive.group;
			overdrive.cut = songOverdrive.cut;
			overdrive.amp = songOverdrive.amp;
			overdrive.cut16BitTop = songOverdrive.cut16BitTop;
		}
		woices = new pxtnWoice*[](song.woices.length);
		foreach (idx, ref woice; woices) {
			const songWoice = song.woices[idx];
			woice = new pxtnWoice;
			woice.voiceNum = songWoice.voiceNum;
			woice.nameBuffer = songWoice.nameBuffer;
			woice.nameSize = songWoice.nameSize;
			woice.type = songWoice.type;
			woice.x3xTuning = songWoice.x3xTuning;
			woice.x3xBasicKey = songWoice.x3xBasicKey;
			woice.voices.length = songWoice.voices.length;
			foreach (voiceIDX, ref voice; woice.voices) {
				const songVoice = songWoice.voices[voiceIDX];
				voice.basicKey = songVoice.basicKey;
				voice.volume = songVoice.volume;
				voice.pan = songVoice.pan;
				voice.tuning = songVoice.tuning;
				voice.voiceFlags = songVoice.voiceFlags;
				voice.dataFlags = songVoice.dataFlags;
				voice.type = songVoice.type;
				songVoice.pcm.copy(voice.pcm);
				songVoice.ptn.copy(voice.ptn);
				version(WithOggVorbis) {
					songVoice.oggV.copy(voice.oggV);
				}
				voice.wave.num = songVoice.wave.num;
				voice.wave.reso = songVoice.wave.reso;
				voice.wave.points = songVoice.wave.points.dup;
				voice.envelope.fps = songVoice.envelope.fps;
				voice.envelope.headNumber = songVoice.envelope.headNumber;
				voice.envelope.bodyNumber = songVoice.envelope.bodyNumber;
				voice.envelope.tailNumber = songVoice.envelope.tailNumber;
				voice.envelope.points = songVoice.envelope.points.dup;
			}
			woice.voiceInstances.length = songWoice.voiceInstances.length;
		}

		units = song.units.dup;
		tonesReady();
		songLoaded = true;
	}

	void initialize() @safe {
		initialize(0, false);
	}

	void tonesReady() @safe {
		if (!isInitialized) {
			throw new PxtoneException("pxtnService not initialized");
		}

		int beatNum = song.master.getBeatNum();
		float beatTempo = song.master.getBeatTempo();

		for (int i = 0; i < delays.length; i++) {
			delays[i].toneReady(beatNum, beatTempo, outputSamplesPerSecond);
		}
		for (int i = 0; i < overdrives.length; i++) {
			overdrives[i].toneReady();
		}
		for (int i = 0; i < song.woices.length; i++) {
			song.woices[i].toneReady(woices[i], pxtnPulseNoiseBuilder, outputSamplesPerSecond);
		}
	}

	bool tonesClear() nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		for (int i = 0; i < delays.length; i++) {
			delays[i].toneClear();
		}
		for (int i = 0; i < units.length; i++) {
			units[i].toneClear();
		}
		return true;
	}

	int groupNum() const nothrow @safe {
		return isInitialized ? pxtnMaxTuneGroupNumber : 0;
	}

	// ---------------------------
	// Delay..
	// ---------------------------

	int delayNum() const nothrow @safe {
		return isInitialized ? cast(int)delays.length : 0;
	}

	int delayMax() const nothrow @safe {
		return isInitialized ? cast(int)delays.length : 0;
	}

	bool delaySet(int idx, DelayUnit unit, float freq, float rate, int group) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		if (idx >= delays.length) {
			return false;
		}
		delays[idx].set(unit, freq, rate, group);
		return true;
	}

	bool delayAdd(DelayUnit unit, float freq, float rate, int group) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		if (delays.length >= pxtnMaxTuneDelayStruct) {
			return false;
		}
		delays.length++;
		delays[$ - 1] = PxtnDelay.init;
		delays[$ - 1].set(unit, freq, rate, group);
		return true;
	}

	bool delayRemove(int idx) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		if (idx >= delays.length) {
			return false;
		}

		for (int i = idx; i < delays.length; i++) {
			delays[i] = delays[i + 1];
		}
		delays.length--;
		return true;
	}

	void delayReadyTone(int idx) @safe {
		if (!isInitialized) {
			throw new PxtoneException("pxtnService not initialized");
		}
		if (idx < 0 || idx >= delays.length) {
			throw new PxtoneException("param");
		}
		delays[idx].toneReady(song.master.getBeatNum(), song.master.getBeatTempo(), outputSamplesPerSecond);
	}

	PxtnDelay* delayGet(int idx) nothrow @safe {
		if (!isInitialized) {
			return null;
		}
		if (idx < 0 || idx >= delays.length) {
			return null;
		}
		return &delays[idx];
	}

	// ---------------------------
	// Over Drive..
	// ---------------------------

	int overDriveNum() const nothrow @safe {
		return isInitialized ? cast(int)overdrives.length : 0;
	}

	int overDriveMax() const nothrow @safe {
		return isInitialized ? cast(int)overdrives.length : 0;
	}

	bool overDriveSet(int idx, float cut, float amp, int group) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		if (idx >= overdrives.length) {
			return false;
		}
		overdrives[idx].set(cut, amp, group);
		return true;
	}

	bool overDriveAdd(float cut, float amp, int group) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		if (overdrives.length >= overdrives.length) {
			return false;
		}
		overdrives ~= new pxtnOverDrive();
		overdrives[$ - 1].set(cut, amp, group);
		return true;
	}

	bool overDriveRemove(int idx) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		if (idx >= overdrives.length) {
			return false;
		}

		overdrives[idx] = null;
		for (int i = idx; i < overdrives.length; i++) {
			overdrives[i] = overdrives[i + 1];
		}
		overdrives.length--;
		return true;
	}

	bool overDriveReadyTone(int idx) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		if (idx < 0 || idx >= overdrives.length) {
			return false;
		}
		overdrives[idx].toneReady();
		return true;
	}

	pxtnOverDrive* overDriveGet(int idx) nothrow @safe {
		if (!isInitialized) {
			return null;
		}
		if (idx < 0 || idx >= overdrives.length) {
			return null;
		}
		return overdrives[idx];
	}

	// ---------------------------
	// Woice..
	// ---------------------------

	int woiceNum() const nothrow @safe {
		return isInitialized ? cast(int)woices.length : 0;
	}
	alias woiceMax = woiceNum;

	inout(pxtnWoice)* woiceGet(int idx) inout nothrow @safe {
		if (!isInitialized) {
			return null;
		}
		if (idx < 0 || idx >= woices.length) {
			return null;
		}
		return woices[idx];
	}

	void woiceRead(int idx, ref PxtnDescriptor desc, PxtnWoiceType type) @safe {
		if (!isInitialized) {
			throw new PxtoneException("pxtnService not initialized");
		}
		if (idx < 0 || idx >= woices.length) {
			throw new PxtoneException("param");
		}
		if (idx > woices.length) {
			throw new PxtoneException("param");
		}
		if (idx == woices.length) {
			woices ~= new pxtnWoice();
		}

		scope(failure) {
			woiceRemove(idx);
		}
		woices[idx].read(desc, type);
	}

	void woiceReadyTone(int idx) @safe {
		if (!isInitialized) {
			throw new PxtoneException("pxtnService not initialized");
		}
		if (idx < 0 || idx >= woices.length) {
			throw new PxtoneException("param");
		}
		song.woices[idx].toneReady(woices[idx], pxtnPulseNoiseBuilder, outputSamplesPerSecond);
	}

	bool woiceRemove(int idx) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		if (idx < 0 || idx >= woices.length) {
			return false;
		}
		woices[idx] = null;
		for (int i = idx; i < woices.length - 1; i++) {
			woices[i] = woices[i + 1];
		}
		woices.length--;
		return true;
	}

	bool woiceReplace(int oldPlace, int newPlace) nothrow @safe {
		if (!isInitialized) {
			return false;
		}

		pxtnWoice* woice = woices[oldPlace];
		int maxPlace = cast(int)woices.length - 1;

		if (newPlace > maxPlace) {
			newPlace = maxPlace;
		}
		if (newPlace == oldPlace) {
			return true;
		}

		if (oldPlace < newPlace) {
			for (int w = oldPlace; w < newPlace; w++) {
				if (woices[w]) {
					woices[w] = woices[w + 1];
				}
			}
		} else {
			for (int w = oldPlace; w > newPlace; w--) {
				if (woices[w]) {
					woices[w] = woices[w - 1];
				}
			}
		}

		woices[newPlace] = woice;
		return true;
	}

	// ---------------------------
	// Unit..
	// ---------------------------

	int unitNum() const nothrow @safe {
		return isInitialized ? cast(int)units.length : 0;
	}

	int unitMax() const nothrow @safe {
		return isInitialized ? cast(int)units.length : 0;
	}

	private inout(PxtnUnit)* unitGet(int idx) inout nothrow @safe {
		if (!isInitialized) {
			return null;
		}
		if (idx < 0 || idx >= units.length) {
			return null;
		}
		return &units[idx];
	}

	bool unitRemove(int idx) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		if (idx < 0 || idx >= units.length) {
			return false;
		}
		for (int i = idx; i < units.length; i++) {
			units[i] = units[i + 1];
		}
		units.length--;
		return true;
	}

	bool unitReplace(int oldPlace, int newPlace) nothrow @safe {
		if (!isInitialized) {
			return false;
		}

		PxtnUnit woice = units[oldPlace];
		int maxPlace = cast(int)units.length - 1;

		if (newPlace > maxPlace) {
			newPlace = maxPlace;
		}
		if (newPlace == oldPlace) {
			return true;
		}

		if (oldPlace < newPlace) {
			for (int w = oldPlace; w < newPlace; w++) {
				units[w] = units[w + 1];
			}
		} else {
			for (int w = oldPlace; w > newPlace; w--) {
				units[w] = units[w - 1];
			}
		}
		units[newPlace] = woice;
		return true;
	}

	bool unitAddNew() nothrow @safe {
		if (pxtnMaxTuneUnitStruct < units.length) {
			return false;
		}
		units.length++;
		units[$ - 1] = PxtnUnit.init;
		return true;
	}

	bool unitSetOperatedAll(bool b) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		for (int u = 0; u < units.length; u++) {
			units[u].setOperated(b);
			if (b) {
				units[u].setPlayed(true);
			}
		}
		return true;
	}

	bool unitSolo(int idx) nothrow @safe {
		if (!isInitialized) {
			return false;
		}
		for (int u = 0; u < units.length; u++) {
			if (u == idx) {
				units[u].setPlayed(true);
			} else {
				units[u].setPlayed(false);
			}
		}
		return false;
	}

	// ---------------------------
	// Quality..
	// ---------------------------

	void setDestinationQuality(int channels, int sps) @safe {
		enforce(isInitialized, new PxtoneException("pxtnService not initialized"));
		switch (channels) {
		case 1:
			break;
		case 2:
			break;
		default:
			throw new PxtoneException("Unsupported sample rate");
		}

		outputChannels = channels;
		outputSamplesPerSecond = sps;
	}

	void getDestinationQuality(int* channels, int* samplesPerSecond) const @safe {
		enforce(isInitialized, new PxtoneException("pxtnService not initialized"));
		if (channels) {
			*channels = outputChannels;
		}
		if (samplesPerSecond) {
			*samplesPerSecond = outputSamplesPerSecond;
		}
	}

	void setSampledCallback(pxtnSampledCallback proc, void* user) @safe {
		enforce(isInitialized, new PxtoneException("pxtnService not initialized"));
		sampledCallback = proc;
		sampledCallbackUserData = user;
	}

	//////////////
	// Moo..
	//////////////

	///////////////////////
	// get / set
	///////////////////////

	bool mooIsValidData() const @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		return songLoaded;
	}

	bool mooIsEndVomit() const @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		return songPlaying;
	}

	void mooSetMuteByUnit(bool b) @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		mutedByUnit = b;
	}

	void mooSetLoop(bool b) @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		songLooping = b;
	}

	void mooSetFade(int fade, float sec) @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		mooFadeMax = cast(int)(cast(float) outputSamplesPerSecond * sec) >> 8;
		if (fade < 0) {
			mooFadeFade = -1;
			mooFadeCount = mooFadeMax << 8;
		}  // out
		else if (fade > 0) {
			mooFadeFade = 1;
			mooFadeCount = 0;
		}  // in
		else {
			mooFadeFade = 0;
			mooFadeCount = 0;
		} // off
	}

	void mooSetMasterVolume(float v) @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		if (v < 0) {
			v = 0;
		}
		if (v > 1) {
			v = 1;
		}
		masterVolume = v;
	}

	int mooGetTotalSample() const @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		enforce(songLoaded, new PxtoneException("no valid data loaded"));

		int measNum;
		int beatNum;
		int _;
		float beatTempo;
		song.master.get(beatNum, beatTempo, _, measNum);
		return mooCalcSampleNum(measNum, beatNum, outputSamplesPerSecond, song.master.getBeatTempo());
	}

	int mooGetNowClock() const @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		enforce(mooClockRate, new PxtoneException("No clock rate set"));
		return cast(int)(mooSampleCount / mooClockRate);
	}

	int mooGetEndClock() const @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		enforce(mooClockRate, new PxtoneException("No clock rate set"));
		return cast(int)(mooSampleEnd / mooClockRate);
	}

	int mooGetSamplingOffset() const @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		enforce(!songPlaying, new PxtoneException("playback has ended"));
		return mooSampleCount;
	}

	int mooGetSamplingEnd() const @safe {
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		enforce(!songPlaying, new PxtoneException("playback has ended"));
		return mooSampleEnd;
	}

	// preparation
	void mooPreparation() @safe {
		return mooPreparation(pxtnVOMITPREPARATION.init);
	}
	void mooPreparation(in pxtnVOMITPREPARATION prep) @safe {
		scope(failure) {
			songPlaying = true;
		}
		enforce(isMooInitialized, new PxtoneException("pxtnService not initialized"));
		enforce(songLoaded, new PxtoneException("no valid data loaded"));
		enforce(outputChannels, new PxtoneException("invalid channel number specified"));
		enforce(outputSamplesPerSecond, new PxtoneException("invalid sample rate specified"));

		int measEnd = song.master.getPlayMeas();
		int measRepeat = song.master.getRepeatMeas();

		if (prep.measEnd) {
			measEnd = prep.measEnd;
		}
		if (prep.measRepeat) {
			measRepeat = prep.measRepeat;
		}

		mutedByUnit = prep.flags.unitMute;
		songLooping = prep.flags.loop;

		setVolume(prep.masterVolume);

		beatClock = song.master.getBeatClock();
		beatNum = song.master.getBeatNum();
		beatTempo = song.master.getBeatTempo();
		mooClockRate = cast(float)(60.0f * cast(double) outputSamplesPerSecond / (cast(double) beatTempo * cast(double) beatClock));
		mooSampleStride = (44100.0f / outputSamplesPerSecond);
		mooTop = 0x7fff;

		mooTimePanIndex = 0;

		mooSampleEnd = cast(int)(cast(double) measEnd * cast(double) beatNum * cast(double) beatClock * mooClockRate);
		mooSampleRepeat = cast(int)(cast(double) measRepeat * cast(double) beatNum * cast(double) beatClock * mooClockRate);

		if (prep.startPosFloat) {
			mooSampleStart = cast(int)(cast(float) mooGetTotalSample() * prep.startPosFloat);
		} else if (prep.startPosSample) {
			mooSampleStart = prep.startPosSample;
		} else {
			mooSampleStart = cast(int)(cast(double) prep.startPosMeas * cast(double) beatNum * cast(double) beatClock * mooClockRate);
		}

		mooSampleCount = mooSampleStart;
		mooSampleSmooth = outputSamplesPerSecond / 250; // (0.004sec) // (0.010sec)

		if (prep.fadeInSec > 0) {
			mooSetFade(1, prep.fadeInSec);
		} else {
			mooSetFade(0, 0);
		}
		start();
	}

	void setVolume(float volume) @safe {
		enforce(!volume.isNaN, "Volume must be a number");
		masterVolume = clamp(volume, 0.0, 1.0);
	}

	void start() @safe {
		tonesClear();

		currentEventRecords = song.evels.getRecords();

		mooInitUnitTone();

		songPlaying = false;
	}

	////////////////////
	//
	////////////////////

	bool moo(short[] buffer) nothrow @safe {
		if (!isMooInitialized) {
			return false;
		}
		if (!songLoaded) {
			return false;
		}
		if (songPlaying) {
			return false;
		}

		bool bRe = false;

		int samplesWritten = 0;

		if (buffer.length % outputChannels) {
			return false;
		}

		int sampleCount = cast(int)(buffer.length / outputChannels);

		{
			short[2] sample;

			for (samplesWritten = 0; samplesWritten < sampleCount; samplesWritten++) {
				if (!mooPxtoneSample(sample[])) {
					songPlaying = true;
					break;
				}
				for (int ch = 0; ch < outputChannels; ch++, buffer = buffer[1 .. $]) {
					buffer[0] = sample[ch];
				}
			}
			for (; samplesWritten < sampleCount; samplesWritten++) {
				for (int ch = 0; ch < outputChannels; ch++, buffer = buffer[1 .. $]) {
					buffer[0] = 0;
				}
			}
		}

		if (sampledCallback) {
			int clock = cast(int)(mooSampleCount / mooClockRate);
			if (!sampledCallback(sampledCallbackUserData, &this)) {
				songPlaying = true;
				goto term;
			}
		}

		bRe = true;
	term:
		return bRe;
	}
}

private int mooCalcSampleNum(int measNumber, int beatNumber, int sps, float beatTempo) nothrow @safe {
	uint totalBeatNum;
	uint sampleNum;
	if (!beatTempo) {
		return 0;
	}
	totalBeatNum = measNumber * beatNumber;
	sampleNum = cast(uint)(cast(double) sps * 60 * cast(double) totalBeatNum / cast(double) beatTempo);
	return sampleNum;
}
