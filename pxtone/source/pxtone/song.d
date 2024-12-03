module pxtone.song;

import pxtone.descriptor;
import pxtone.delay;
import pxtone.evelist;
import pxtone.error;
import pxtone.master;
import pxtone.max;
import pxtone.overdrive;
import pxtone.service;
import pxtone.text;
import pxtone.woice;
import pxtone.unit;

import std.exception;
import std.format;
import std.stdio;

struct PxToneSong {
	PxtnText text;
	PxtnMaster master;
	PxtnEventList evels;


	Delay[] delays;
	pxtnOverDrive*[] overdrives;
	pxtnWoice*[] woices;
	PxtnUnit[] units;

	this(ubyte[] buffer) @safe {
		PxtnDescriptor desc;
		desc.setMemoryReadOnly(buffer);
		read(desc);
	}

	this(File fd) @safe {
		PxtnDescriptor desc;
		desc.setFileReadOnly(fd);
		read(desc);
	}
	static bool detect(ubyte[] buffer) @safe {
		PxToneSong tmpSong;
		PxtnDescriptor desc;
		desc.setMemoryReadOnly(buffer);
		FMTVER fmtVer;
		ushort exeVer;
		try {
			tmpSong.readVersion(desc, fmtVer, exeVer);
		} catch(Exception) {
			return false;
		}
		return true;
	}
	void clear() nothrow @safe {
		text.setNameBuf("");
		text.setCommentBuf("");

		evels.clear();

		delays = delays.init;
		overdrives = overdrives.init;
		woices = woices.init;
		units = units.init;

		master.reset();

		evels.release();
	}
	void read(ref PxtnDescriptor pDoc) @safe {
		ushort exeVer = 0;
		FMTVER fmtVer = FMTVER.unknown;
		int eventNum = 0;

		clear();

		scope(failure) {
			clear();
		}

		preCountEvent(pDoc, eventNum);
		pDoc.seek(PxtnSeek.set, 0);

		evels.allocate(eventNum);

		readVersion(pDoc, fmtVer, exeVer);

		if (fmtVer >= FMTVER.v5) {
			evels.linearStart();
		} else {
			evels.x4xReadStart();
		}

		readTuneItems(pDoc);

		if (fmtVer >= FMTVER.v5) {
			evels.linearEnd(true);
		}

		if (fmtVer <= FMTVER.x3x) {
			if (!x3xTuningKeyEvent()) {
				throw new PxtoneException("x3x key");
			}
			if (!x3xAddTuningEvent()) {
				throw new PxtoneException("x3x add tuning");
			}
			x3xSetVoiceNames();
		}

		{
			int clock1 = evels.getMaxClock();
			int clock2 = master.getLastClock();

			if (clock1 > clock2) {
				master.adjustMeasNum(clock1);
			} else {
				master.adjustMeasNum(clock2);
			}
		}
	}
	////////////////////////////////////////
	// save               //////////////////
	////////////////////////////////////////

	void write(ref PxtnDescriptor pDoc, bool bTune, ushort exeVer) @safe {
		bool bRet = false;
		int rough = bTune ? 10 : 1;
		ushort rrr = 0;

		// format version
		if (bTune) {
			pDoc.write(identifierCodeTuneV5);
		} else {
			pDoc.write(identifierCodeProjectV5);
		}

		// exe version
		pDoc.write(exeVer);
		pDoc.write(rrr);

		// master
		pDoc.write(identifierCodeMasterV5);
		master.ioWrite(pDoc, rough);

		// event
		pDoc.write(identifierCodeEventV5);
		evels.ioWrite(pDoc, rough);

		// name
		if (text.isNameBuf()) {
			pDoc.write(identifierCodeTextNAME);
			write4Tag(text.getNameBuf(), pDoc);
		}

		// comment
		if (text.isCommentBuf()) {
			pDoc.write(identifierCodeTextCOMM);
			write4Tag(text.getCommentBuf(), pDoc);
		}

		// delay
		for (int d = 0; d < delays.length; d++) {
			pDoc.write(identifierCodeEffeDELA);

			Delay dela;
			int size;

			dela.unit = cast(ushort) delays[d].unit;
			dela.group = cast(ushort) delays[d].group;
			dela.rate = delays[d].rate;
			dela.freq = delays[d].freq;

			// dela ----------
			size = Delay.sizeof;
			pDoc.write(size);
			pDoc.write(dela);
		}

		// overdrive
		for (int o = 0; o < overdrives.length; o++) {
			pDoc.write(identifierCodeEffeOVER);
			overdrives[o].write(pDoc);
		}

		// woice
		for (int w = 0; w < woices.length; w++) {
			pxtnWoice* woice = woices[w];

			switch (woice.getType()) {
			case PxtnWoiceType.pcm:
				pDoc.write(identifierCodeMatePCM);
				woice.ioMatePCMWrite(pDoc);
				break;
			case PxtnWoiceType.ptv:
				pDoc.write(identifierCodeMatePTV);
				if (!woice.ioMatePTVWrite(pDoc)) {
					throw new PxtoneException("desc w");
				}
				break;
			case PxtnWoiceType.ptn:
				pDoc.write(identifierCodeMatePTN);
				woice.ioMatePTNWrite(pDoc);
				break;
			case PxtnWoiceType.oggVorbis:

				version (WithOggVorbis) {
					pDoc.write(identifierCodeMateOGGV);
					if (!woice.ioMateOGGVWrite(pDoc)) {
						throw new PxtoneException("desc w");
					}
					break;
				} else {
					throw new PxtoneException("Ogg vorbis support is required");
				}
			default:
				throw new PxtoneException("inv data");
			}

			if (!bTune && woice.isNameBuf()) {
				pDoc.write(identifierCodeAssiWOIC);
				if (!ioAssistWoiceWrite(pDoc, w)) {
					throw new PxtoneException("desc w");
				}
			}
		}

		// unit
		pDoc.write(identifierCodeNumUNIT);
		ioUnitNumberWrite(pDoc);

		for (int u = 0; u < units.length; u++) {
			if (!bTune && units[u].isNameBuf()) {
				pDoc.write(identifierCodeAssiUNIT);
				if (!ioAssistUnitWrite(pDoc, u)) {
					throw new PxtoneException("desc w");
				}
			}
		}

		{
			int endSize = 0;
			pDoc.write(identifierCodePxtoneND);
			pDoc.write(endSize);
		}
	}
	////////////////////////////////////////
	// Read Project //////////////
	////////////////////////////////////////

	private void readTuneItems(ref PxtnDescriptor pDoc) @safe {
		bool bEnd = false;
		char[identifierCodeSize + 1] code = '\0';

		/// must the unit before the voice.
		while (!bEnd) {
			pDoc.read(code[0 ..identifierCodeSize]);

			Tag tag = checkTagCode(code);
			switch (tag) {
			case Tag.antiOPER:
				throw new PxtoneException("AntiOPER tag detected");

				// new -------
			case Tag.numUnit: {
					int num = 0;
					ioUnitNumberRead(pDoc, num);
					units.length = num;
					break;
				}
			case Tag.MasterV5:
				master.ioRead(pDoc);
				break;
			case Tag.EventV5:
				evels.ioRead(pDoc);
				break;

			case Tag.matePCM:
				ioReadWoice(pDoc, PxtnWoiceType.pcm);
				break;
			case Tag.matePTV:
				ioReadWoice(pDoc, PxtnWoiceType.ptv);
				break;
			case Tag.matePTN:
				ioReadWoice(pDoc, PxtnWoiceType.ptn);
				break;

			case Tag.mateOGGV:

				version (WithOggVorbis) {
					ioReadWoice(pDoc, PxtnWoiceType.oggVorbis);
					break;
				} else {
					throw new PxtoneException("Ogg Vorbis support is required");
				}

			case Tag.effeDELA:
				ioReadDelay(pDoc);
				break;
			case Tag.effeOVER:
				ioReadOverDrive(pDoc);
				break;
			case Tag.textNAME:
				text.setNameBuf(read4Tag(pDoc));
				break;
			case Tag.textCOMM:
				text.setCommentBuf(read4Tag(pDoc));
				break;
			case Tag.assiWOIC:
				ioAssistWoiceRead(pDoc);
				break;
			case Tag.assiUNIT:
				ioAssistUnitRead(pDoc);
				break;
			case Tag.pxtoneND:
				bEnd = true;
				break;

				// old -------
			case Tag.x4xEvenMAST:
				master.ioReadOld(pDoc);
				break;
			case Tag.x4xEvenUNIT:
				evels.ioUnitReadX4xEvent(pDoc, false, true);
				break;
			case Tag.x3xPxtnUNIT:
				ioReadOldUnit(pDoc, 3);
				break;
			case Tag.x1xPROJ:
				x1xProjectRead(pDoc);
				break;
			case Tag.x1xUNIT:
				ioReadOldUnit(pDoc, 1);
				break;
			case Tag.x1xPCM:
				ioReadWoice(pDoc, PxtnWoiceType.pcm);
				break;
			case Tag.x1xEVEN:
				evels.ioUnitReadX4xEvent(pDoc, true, false);
				break;
			case Tag.x1xEND:
				bEnd = true;
				break;

			default:
				throw new PxtoneException("fmt unknown");
			}
		}

	}
	void readVersion(ref PxtnDescriptor pDoc, out FMTVER pFmtVer, out ushort pExeVer) @safe {
		char[versionSize] gotVersion = '\0';
		ushort dummy;

		pDoc.read(gotVersion[]);

		// fmt version
		if (gotVersion[] == identifierCodeProjectX1x) {
			pFmtVer = FMTVER.x1x;
			pExeVer = 0;
			return;
		} else if (gotVersion[] == identifierCodeProjectX2x) {
			pFmtVer = FMTVER.x2x;
			pExeVer = 0;
			return;
		} else if (gotVersion[] == identifierCodeProjectX3x) {
			pFmtVer = FMTVER.x3x;
		} else if (gotVersion[] == identifierCodeProjectX4x) {
			pFmtVer = FMTVER.x4x;
		} else if (gotVersion[] == identifierCodeProjectV5) {
			pFmtVer = FMTVER.v5;
		} else if (gotVersion[] == identifierCodeTuneX2x) {
			pFmtVer = FMTVER.x2x;
			pExeVer = 0;
			return;
		} else if (gotVersion[] == identifierCodeTuneX3x) {
			pFmtVer = FMTVER.x3x;
		} else if (gotVersion[] == identifierCodeTuneX4x) {
			pFmtVer = FMTVER.x4x;
		} else if (gotVersion[] == identifierCodeTuneV5) {
			pFmtVer = FMTVER.v5;
		} else {
			throw new PxtoneException("fmt unknown");
		}

		// exe version
		pDoc.read(pExeVer);
		pDoc.read(dummy);
	}

	private void x1xProjectRead(ref PxtnDescriptor pDoc) @safe {
		Project prjc;
		int beatNum, beatClock;
		int size;
		float beatTempo;

		pDoc.read(size);
		pDoc.read(prjc);

		beatNum = prjc.x1xBeatNum;
		beatTempo = prjc.x1xBeatTempo;
		beatClock = prjc.x1xBeatClock;

		int ns = 0;
		for ( /+ns+/ ; ns < prjc.x1xName.length; ns++) {
			if (!prjc.x1xName[ns]) {
				break;
			}
		}

		text.setNameBuf(prjc.x1xName[0 .. ns].dup);
		master.set(beatNum, beatTempo, beatClock);
	}

	private void ioReadDelay(ref PxtnDescriptor pDoc) @safe {
		if (pxtnMaxTuneDelayStruct < delays.length) {
			throw new PxtoneException("fmt unknown");
		}

		Delay delay;
		int size = 0;

		pDoc.read(size);
		pDoc.read(delay);
		if (delay.unit >= DelayUnit.num) {
			throw new PxtoneException("fmt unknown");
		}

		if (delay.group >= pxtnMaxTuneGroupNumber) {
			delay.group = 0;
		}

		delays ~= delay;
	}

	private void ioReadOverDrive(ref PxtnDescriptor pDoc) @safe {
		if (pxtnMaxTuneOverdriveStruct < overdrives.length) {
			throw new PxtoneException("fmt unknown");
		}

		pxtnOverDrive* ovdrv = new pxtnOverDrive();
		ovdrv.read(pDoc);
		overdrives ~= ovdrv;
	}

	private void ioReadWoice(ref PxtnDescriptor pDoc, PxtnWoiceType type) @safe {
		if (pxtnMaxTuneWoiceStruct < woices.length) {
			throw new PxtoneException("Too many woices");
		}

		pxtnWoice* woice = new pxtnWoice();

		switch (type) {
		case PxtnWoiceType.pcm:
			woice.ioMatePCMRead(pDoc);
			break;
		case PxtnWoiceType.ptv:
			woice.ioMatePTVRead(pDoc);
			break;
		case PxtnWoiceType.ptn:
			woice.ioMatePTNRead(pDoc);
			break;
		case PxtnWoiceType.oggVorbis:
			version (WithOggVorbis) {
				woice.ioMateOGGVRead(pDoc);
				break;
			} else {
				throw new PxtoneException("Ogg Vorbis support is required");
			}

		default:
			throw new PxtoneException("fmt unknown");
		}
		woices ~= woice;
	}

	private void ioReadOldUnit(ref PxtnDescriptor pDoc, int ver) @safe {
		if (pxtnMaxTuneUnitStruct < units.length) {
			throw new PxtoneException("fmt unknown");
		}

		PxtnUnit* unit = new PxtnUnit();
		int group = 0;
		switch (ver) {
		case 1:
			unit.readOld(pDoc, group);
			break;
		case 3:
			unit.read(pDoc, group);
			break;
		default:
			throw new PxtoneException("fmt unknown");
		}

		if (group >= pxtnMaxTuneGroupNumber) {
			group = pxtnMaxTuneGroupNumber - 1;
		}

		evels.x4xReadAdd(0, cast(ubyte) units.length, EventKind.groupNumber, cast(int) group);
		evels.x4xReadNewKind();
		evels.x4xReadAdd(0, cast(ubyte) units.length, EventKind.voiceNumber, cast(int) units.length);
		evels.x4xReadNewKind();

		units ~= *unit;
	}

	/////////////
	// comments
	/////////////

	const(char)[] read4Tag(ref PxtnDescriptor pDoc) @safe {
		char[] result;
		int pBufferSize;
		pDoc.read(pBufferSize);
		enforce(pBufferSize >= 0, "Invalid string size");

		if (pBufferSize) {
			result = new char[](pBufferSize);
			pDoc.read(result[0 .. pBufferSize]);
		}
		return result;
	}
	private void write4Tag(const char[] p, ref PxtnDescriptor pDoc) @safe {
		pDoc.write(cast(int)p.length);
		pDoc.write(p);
	}

	/////////////
	// assi woice
	/////////////

	private bool ioAssistWoiceWrite(ref PxtnDescriptor pDoc, int idx) const @safe {
		AssistWoice assi;
		int size;
		const char[] pName = woices[idx].getNameBuf();

		if (pName.length > pxtnMaxTuneWoiceName) {
			return false;
		}

		assi.name[0 .. pName.length] = pName;
		assi.woiceIndex = cast(ushort) idx;

		size = AssistWoice.sizeof;
		pDoc.write(size);
		pDoc.write(assi);

		return true;
	}

	void ioAssistWoiceRead(ref PxtnDescriptor pDoc) @safe {
		AssistWoice assi;
		int size = 0;

		pDoc.read(size);
		if (size != assi.sizeof) {
			throw new PxtoneException("fmt unknown");
		}
		pDoc.read(assi);
		if (assi.rrr) {
			throw new PxtoneException("fmt unknown");
		}
		if (assi.woiceIndex >= woices.length) {
			throw new PxtoneException("fmt unknown");
		}

		if (!woices[assi.woiceIndex].setNameBuf(assi.name.dup)) {
			throw new PxtoneException("FATAL");
		}
	}
	// -----
	// assi unit.
	// -----

	private bool ioAssistUnitWrite(ref PxtnDescriptor pDoc, int idx) const @safe {
		AssistUnit assi;
		int size;
		const(char)[] pName = units[idx].getNameBuf();

		assi.name[0 .. pName.length] = pName[];
		assi.unitIndex = cast(ushort) idx;

		size = assi.sizeof;
		pDoc.write(size);
		pDoc.write(assi);

		return true;
	}

	private void ioAssistUnitRead(ref PxtnDescriptor pDoc) @safe {
		AssistUnit assi;
		int size;

		pDoc.read(size);
		if (size != assi.sizeof) {
			throw new PxtoneException("fmt unknown");
		}
		pDoc.read(assi);
		if (assi.rrr) {
			throw new PxtoneException("fmt unknown");
		}
		if (assi.unitIndex >= units.length) {
			throw new PxtoneException("fmt unknown");
		}

		if (!units[assi.unitIndex].setNameBuf(assi.name[])) {
			throw new PxtoneException("FATAL");
		}
	}
	// -----
	// unit num
	// -----

	private void ioUnitNumberWrite(ref PxtnDescriptor pDoc) const @safe {
		NumUnit data;
		int size;

		data.num = cast(short) units.length;

		size = NumUnit.sizeof;
		pDoc.write(size);
		pDoc.write(data);
	}

	private void ioUnitNumberRead(ref PxtnDescriptor pDoc, out int pNum) @safe {
		NumUnit data;
		int size = 0;

		pDoc.read(size);
		if (size != NumUnit.sizeof) {
			throw new PxtoneException("fmt unknown");
		}
		pDoc.read(data);
		if (data.rrr) {
			throw new PxtoneException("fmt unknown");
		}
		if (data.num > pxtnMaxTuneUnitStruct) {
			throw new PxtoneException("fmt new");
		}
		if (data.num < 0) {
			throw new PxtoneException("fmt unknown");
		}
		pNum = data.num;
	}

	// fix old key event
	private bool x3xTuningKeyEvent() nothrow @safe {
		if (units.length > woices.length) {
			return false;
		}

		for (int u = 0; u < units.length; u++) {
			if (u >= woices.length) {
				return false;
			}

			int changeValue = woices[u].getX3xBasicKey() - EventDefault.basicKey;

			if (!evels.getCount(cast(ubyte) u, cast(ubyte) EventKind.key)) {
				evels.recordAdd(0, cast(ubyte) u, EventKind.key, cast(int) 0x6000);
			}
			evels.recordValueChange(0, -1, cast(ubyte) u, EventKind.key, changeValue);
		}
		return true;
	}

	// fix old tuning (1.0)
	private bool x3xAddTuningEvent() nothrow @safe {
		if (units.length > woices.length) {
			return false;
		}

		for (int u = 0; u < units.length; u++) {
			float tuning = woices[u].getX3xTuning();
			if (tuning) {
				evels.recordAdd(0, cast(ubyte) u, EventKind.tuning, tuning);
			}
		}

		return true;
	}

	private bool x3xSetVoiceNames() nothrow @safe {
		for (int i = 0; i < woices.length; i++) {
			char[pxtnMaxTuneWoiceName + 1] name = 0;
			try {
				sformat(name[], "voice_%02d", i);
			} catch (Exception) { //This will never actually happen...
				return false;
			}
			woices[i].setNameBuf(name.dup);
		}
		return true;
	}
	private void preCountEvent(ref PxtnDescriptor pDoc, out int pCount) @safe {
		bool bEnd = false;

		int count = 0;
		int c = 0;
		int size = 0;
		char[identifierCodeSize + 1] code = '\0';

		ushort exeVer = 0;
		FMTVER fmtVer = FMTVER.unknown;

		scope(failure) {
			pCount = 0;
		}

		readVersion(pDoc, fmtVer, exeVer);

		if (fmtVer == FMTVER.x1x) {
			count = 10000;
			goto term;
		}

		while (!bEnd) {
			pDoc.read(code[0 .. identifierCodeSize]);

			switch (checkTagCode(code)) {
			case Tag.EventV5:
				count += evels.ioReadEventNum(pDoc);
				break;
			case Tag.MasterV5:
				count += master.ioReadEventNumber(pDoc);
				break;
			case Tag.x4xEvenMAST:
				count += master.ioReadOldEventNumber(pDoc);
				break;
			case Tag.x4xEvenUNIT:
				evels.ioReadX4xEventNum(pDoc, c);
				count += c;
				break;
			case Tag.pxtoneND:
				bEnd = true;
				break;

				// skip
			case Tag.antiOPER:
			case Tag.numUnit:
			case Tag.x3xPxtnUNIT:
			case Tag.matePCM:
			case Tag.matePTV:
			case Tag.matePTN:
			case Tag.mateOGGV:
			case Tag.effeDELA:
			case Tag.effeOVER:
			case Tag.textNAME:
			case Tag.textCOMM:
			case Tag.assiUNIT:
			case Tag.assiWOIC:

				pDoc.read(size);
				pDoc.seek(PxtnSeek.cur, size);
				break;

				// ignore
			case Tag.x1xPROJ:
			case Tag.x1xUNIT:
			case Tag.x1xPCM:
			case Tag.x1xEVEN:
			case Tag.x1xEND:
				throw new PxtoneException("x1x ignore");
			default:
				throw new PxtoneException("FATAL");
			}
		}

		if (fmtVer <= FMTVER.x3x) {
			count += pxtnMaxTuneUnitStruct * 4; // voice number, group number, key tuning, key event x3x
		}

	term:

		pCount = count;
	}
}

unittest {
	import std.file : read;
	auto song = PxToneSong(cast(ubyte[])read("pxtone/sample data/sample.ptcop"));
	assert(song.text.getCommentBuf() == "boss03\r\n13/03/07\r\n13/06/27 fix tr1 maes9-\r\n");
	assert(song.text.getNameBuf() == "Hard Cording");
}


private Tag checkTagCode(scope const char[] pCode) nothrow @safe {
	switch(pCode[0 .. identifierCodeSize]) {
		case identifierCodeAntiOPER: return Tag.antiOPER;
		case identifierCodeX1xPROJ: return Tag.x1xPROJ;
		case identifierCodeX1xUNIT: return Tag.x1xUNIT;
		case identifierCodeX1xPCM: return Tag.x1xPCM;
		case identifierCodeX1xEVEN: return Tag.x1xEVEN;
		case identifierCodeX1xEND: return Tag.x1xEND;
		case identifierCodeX3xPxtnUNIT: return Tag.x3xPxtnUNIT;
		case identifierCodeX4xEvenMAST: return Tag.x4xEvenMAST;
		case identifierCodeX4xEvenUNIT: return Tag.x4xEvenUNIT;
		case identifierCodeNumUNIT: return Tag.numUnit;
		case identifierCodeEventV5: return Tag.EventV5;
		case identifierCodeMasterV5: return Tag.MasterV5;
		case identifierCodeMatePCM: return Tag.matePCM;
		case identifierCodeMatePTV: return Tag.matePTV;
		case identifierCodeMatePTN: return Tag.matePTN;
		case identifierCodeMateOGGV: return Tag.mateOGGV;
		case identifierCodeEffeDELA: return Tag.effeDELA;
		case identifierCodeEffeOVER: return Tag.effeOVER;
		case identifierCodeTextNAME: return Tag.textNAME;
		case identifierCodeTextCOMM: return Tag.textCOMM;
		case identifierCodeAssiUNIT: return Tag.assiUNIT;
		case identifierCodeAssiWOIC: return Tag.assiWOIC;
		case identifierCodePxtoneND: return Tag.pxtoneND;
		default: return Tag.Unknown;
	}
}
