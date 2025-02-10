///
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
import std.range;
import std.string;

///
struct PxToneSong {
	PxtnText text; ///
	PxtnMaster master; ///
	PxtnEventList evels; ///


	Delay[] delays; ///
	pxtnOverDrive*[] overdrives; ///
	pxtnWoice*[] woices; ///
	PxtnUnit[] units; ///

	///
	this(const(ubyte)[] buffer) @safe {
		read(buffer);
	}

	///
	static bool detect(const(ubyte)[] buffer) @safe {
		PxToneSong tmpSong;
		FMTVER fmtVer;
		ushort exeVer;
		try {
			tmpSong.readVersion(buffer, fmtVer, exeVer);
		} catch(Exception) {
			return false;
		}
		return true;
	}
	///
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
	///
	void read(ref const(ubyte)[] buffer) @safe {
		ushort exeVer = 0;
		FMTVER fmtVer = FMTVER.unknown;
		int eventNum = 0;

		clear();

		scope(failure) {
			clear();
		}
		auto tmpBuffer = buffer;
		preCountEvent(tmpBuffer, eventNum);

		evels.allocate(eventNum);

		readVersion(buffer, fmtVer, exeVer);

		if (fmtVer >= FMTVER.v5) {
			evels.linearStart();
		} else {
			evels.x4xReadStart();
		}

		readTuneItems(buffer);

		if (fmtVer >= FMTVER.v5) {
			evels.linearEnd(true);
		}

		if (fmtVer <= FMTVER.x3x) {
			x3xTuningKeyEvent();
			x3xAddTuningEvent();
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

	///
	void write(T)(ref T output, bool bTune, ushort exeVer) @safe if (isOutputRange!(T, ubyte)) {
		bool bRet = false;
		int rough = bTune ? 10 : 1;
		ushort rrr = 0;

		// format version
		if (bTune) {
			output.write(identifierCodeTuneV5);
		} else {
			output.write(identifierCodeProjectV5);
		}

		// exe version
		output.write(exeVer);
		output.write(rrr);

		// master
		output.write(identifierCodeMasterV5);
		master.ioWrite(output, rough);

		// event
		output.write(identifierCodeEventV5);
		evels.ioWrite(output, rough);

		// name
		if (text.isNameBuf()) {
			output.write(identifierCodeTextNAME);
			write4Tag(text.getNameBuf(), output);
		}

		// comment
		if (text.isCommentBuf()) {
			output.write(identifierCodeTextCOMM);
			write4Tag(text.getCommentBuf(), output);
		}

		// delay
		for (int d = 0; d < delays.length; d++) {
			output.write(identifierCodeEffeDELA);

			Delay dela;
			int size;

			dela.unit = cast(ushort) delays[d].unit;
			dela.group = cast(ushort) delays[d].group;
			dela.rate = delays[d].rate;
			dela.freq = delays[d].freq;

			// dela ----------
			size = Delay.sizeof;
			output.write(size);
			output.write(dela);
		}

		// overdrive
		for (int o = 0; o < overdrives.length; o++) {
			output.write(identifierCodeEffeOVER);
			overdrives[o].write(output);
		}

		// woice
		for (int w = 0; w < woices.length; w++) {
			pxtnWoice* woice = woices[w];

			switch (woice.getType()) {
			case PxtnWoiceType.pcm:
				output.write(identifierCodeMatePCM);
				woice.ioMatePCMWrite(output);
				break;
			case PxtnWoiceType.ptv:
				output.write(identifierCodeMatePTV);
				woice.ioMatePTVWrite(output);
				break;
			case PxtnWoiceType.ptn:
				output.write(identifierCodeMatePTN);
				woice.ioMatePTNWrite(output);
				break;
			case PxtnWoiceType.oggVorbis:

				version (WithOggVorbis) {
					output.write(identifierCodeMateOGGV);
					woice.ioMateOGGVWrite(output);
					break;
				} else {
					throw new PxtoneException("Ogg vorbis support is required");
				}
			default:
				throw new PxtoneException("inv data");
			}

			if (!bTune && woice.isNameBuf()) {
				output.write(identifierCodeAssiWOIC);
				ioAssistWoiceWrite(output, w);
			}
		}

		// unit
		output.write(identifierCodeNumUNIT);
		ioUnitNumberWrite(output);

		for (int u = 0; u < units.length; u++) {
			if (!bTune && units[u].isNameBuf()) {
				output.write(identifierCodeAssiUNIT);
				ioAssistUnitWrite(output, u);
			}
		}

		{
			int endSize = 0;
			output.write(identifierCodePxtoneND);
			output.write(endSize);
		}
	}
	////////////////////////////////////////
	// Read Project //////////////
	////////////////////////////////////////

	///
	private void readTuneItems(ref const(ubyte)[] buffer) @safe {
		bool bEnd = false;
		char[identifierCodeSize + 1] code = '\0';

		/// must the unit before the voice.
		while (!bEnd) {
			buffer.pop(code[0 ..identifierCodeSize]);

			Tag tag = checkTagCode(code);
			switch (tag) {
			case Tag.antiOPER:
				throw new PxtoneException("AntiOPER tag detected");

				// new -------
			case Tag.numUnit: {
					int num = 0;
					ioUnitNumberRead(buffer, num);
					units.length = num;
					break;
				}
			case Tag.MasterV5:
				master.ioRead(buffer);
				break;
			case Tag.EventV5:
				evels.ioRead(buffer);
				break;

			case Tag.matePCM:
				ioReadWoice(buffer, PxtnWoiceType.pcm);
				break;
			case Tag.matePTV:
				ioReadWoice(buffer, PxtnWoiceType.ptv);
				break;
			case Tag.matePTN:
				ioReadWoice(buffer, PxtnWoiceType.ptn);
				break;

			case Tag.mateOGGV:

				version (WithOggVorbis) {
					ioReadWoice(buffer, PxtnWoiceType.oggVorbis);
					break;
				} else {
					throw new PxtoneException("Ogg Vorbis support is required");
				}

			case Tag.effeDELA:
				ioReadDelay(buffer);
				break;
			case Tag.effeOVER:
				ioReadOverDrive(buffer);
				break;
			case Tag.textNAME:
				text.setNameBuf(read4Tag(buffer));
				break;
			case Tag.textCOMM:
				text.setCommentBuf(read4Tag(buffer));
				break;
			case Tag.assiWOIC:
				ioAssistWoiceRead(buffer);
				break;
			case Tag.assiUNIT:
				ioAssistUnitRead(buffer);
				break;
			case Tag.pxtoneND:
				bEnd = true;
				break;

				// old -------
			case Tag.x4xEvenMAST:
				master.ioReadOld(buffer);
				break;
			case Tag.x4xEvenUNIT:
				evels.ioUnitReadX4xEvent(buffer, false, true);
				break;
			case Tag.x3xPxtnUNIT:
				ioReadOldUnit(buffer, 3);
				break;
			case Tag.x1xPROJ:
				x1xProjectRead(buffer);
				break;
			case Tag.x1xUNIT:
				ioReadOldUnit(buffer, 1);
				break;
			case Tag.x1xPCM:
				ioReadWoice(buffer, PxtnWoiceType.pcm);
				break;
			case Tag.x1xEVEN:
				evels.ioUnitReadX4xEvent(buffer, true, false);
				break;
			case Tag.x1xEND:
				bEnd = true;
				break;

			default:
				throw new PxtoneException("fmt unknown");
			}
		}
	}

	///
	void readVersion(ref const(ubyte)[] pDoc, out FMTVER pFmtVer, out ushort pExeVer) @safe {
		char[versionSize] gotVersion = '\0';
		ushort dummy;

		pDoc.pop(gotVersion[]);

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
		pDoc.pop(pExeVer);
		pDoc.pop(dummy);
	}

	///
	private void x1xProjectRead(ref const(ubyte)[] buffer) @safe {
		Project prjc;
		int beatNum, beatClock;
		int size;
		float beatTempo;

		buffer.pop(size);
		buffer.pop(prjc);

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

	///
	private void ioReadDelay(ref const(ubyte)[] buffer) @safe {
		enforce!PxtoneException(pxtnMaxTuneDelayStruct >= delays.length, "fmt unknown");

		Delay delay;
		int size = 0;

		buffer.pop(size);
		buffer.pop(delay);
		enforce!PxtoneException(delay.unit < DelayUnit.num, "fmt unknown");

		if (delay.group >= pxtnMaxTuneGroupNumber) {
			delay.group = 0;
		}

		delays ~= delay;
	}

	///
	private void ioReadOverDrive(ref const(ubyte)[] buffer) @safe {
		enforce!PxtoneException(pxtnMaxTuneOverdriveStruct >= overdrives.length, "fmt unknown");

		pxtnOverDrive* ovdrv = new pxtnOverDrive();
		ovdrv.read(buffer);
		overdrives ~= ovdrv;
	}

	///
	private void ioReadWoice(ref const(ubyte)[] buffer, PxtnWoiceType type) @safe {
		enforce!PxtoneException(pxtnMaxTuneWoiceStruct >= woices.length, "Too many woices");

		pxtnWoice* woice = new pxtnWoice();

		switch (type) {
		case PxtnWoiceType.pcm:
			woice.ioMatePCMRead(buffer);
			break;
		case PxtnWoiceType.ptv:
			woice.ioMatePTVRead(buffer);
			break;
		case PxtnWoiceType.ptn:
			woice.ioMatePTNRead(buffer);
			break;
		case PxtnWoiceType.oggVorbis:
			version (WithOggVorbis) {
				woice.ioMateOGGVRead(buffer);
				break;
			} else {
				throw new PxtoneException("Ogg Vorbis support is required");
			}

		default:
			throw new PxtoneException("fmt unknown");
		}
		woices ~= woice;
	}

	///
	private void ioReadOldUnit(ref const(ubyte)[] buffer, int ver) @safe {
		enforce!PxtoneException(pxtnMaxTuneUnitStruct >= units.length, "fmt unknown");

		PxtnUnit* unit = new PxtnUnit();
		int group = 0;
		switch (ver) {
		case 1:
			unit.readOld(buffer, group);
			break;
		case 3:
			unit.read(buffer, group);
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

	///
	const(char)[] read4Tag(ref const(ubyte)[] buffer) @safe {
		char[] result;
		int pBufferSize;
		buffer.pop(pBufferSize);
		enforce(pBufferSize >= 0, "Invalid string size");

		if (pBufferSize) {
			result = new char[](pBufferSize);
			buffer.pop(result[0 .. pBufferSize]);
		}
		return result;
	}
	private void write4Tag(R)(const char[] p, ref R output) @safe {
		output.write(cast(int)p.length);
		output.write(p);
	}

	/////////////
	// assi woice
	/////////////

	///
	private void ioAssistWoiceWrite(R)(ref R output, int idx) const @safe {
		AssistWoice assi;
		int size;
		const char[] pName = woices[idx].getNameBuf();

		enforce!PxtoneException(pName.length <= pxtnMaxTuneWoiceName, "Woice name too long");

		assi.name[0 .. pName.length] = pName;
		assi.woiceIndex = cast(ushort) idx;

		size = AssistWoice.sizeof;
		output.write(size);
		output.write(assi);
	}

	///
	void ioAssistWoiceRead(ref const(ubyte)[] buffer) @safe {
		AssistWoice assi;
		int size = 0;

		buffer.pop(size);
		enforce!PxtoneException(size == assi.sizeof, "fmt unknown");
		buffer.pop(assi);
		enforce!PxtoneException(!assi.rrr, "fmt unknown");
		enforce!PxtoneException(assi.woiceIndex < woices.length, "fmt unknown");

		woices[assi.woiceIndex].setNameBuf(assi.name.dup);
	}
	// -----
	// assi unit.
	// -----

	///
	private void ioAssistUnitWrite(R)(ref R output, int idx) const @safe {
		AssistUnit assi;
		int size;
		const(char)[] pName = units[idx].getNameBuf();

		assi.name[0 .. pName.length] = pName[];
		assi.unitIndex = cast(ushort) idx;

		size = assi.sizeof;
		output.write(size);
		output.write(assi);
	}

	///
	private void ioAssistUnitRead(ref const(ubyte)[] buffer) @safe {
		AssistUnit assi;
		int size;

		buffer.pop(size);
		enforce!PxtoneException(size == assi.sizeof, "fmt unknown");
		buffer.pop(assi);
		enforce!PxtoneException(!assi.rrr, "fmt unknown");
		enforce!PxtoneException(assi.unitIndex < units.length, "fmt unknown");

		units[assi.unitIndex].setNameBuf(assi.name.fromStringz);
	}
	// -----
	// unit num
	// -----

	///
	private void ioUnitNumberWrite(R)(ref R output) const @safe {
		NumUnit data;
		int size;

		data.num = cast(short) units.length;

		size = NumUnit.sizeof;
		output.write(size);
		output.write(data);
	}

	///
	private void ioUnitNumberRead(ref const(ubyte)[] buffer, out int pNum) @safe {
		NumUnit data;
		int size = 0;

		buffer.pop(size);
		enforce!PxtoneException(size == NumUnit.sizeof, "fmt unknown");
		buffer.pop(data);
		enforce!PxtoneException(!data.rrr, "fmt unknown");
		enforce!PxtoneException(data.num <= pxtnMaxTuneUnitStruct, "fmt new");
		enforce!PxtoneException(data.num >= 0, "fmt unknown");
		pNum = data.num;
	}

	// fix old key event
	///
	private void x3xTuningKeyEvent() @safe {
		enforce!PxtoneException(units.length <= woices.length, "Too many units");

		for (int u = 0; u < units.length; u++) {
			enforce!PxtoneException(u < woices.length, "Invalid woice index");

			int changeValue = woices[u].getX3xBasicKey() - EventDefault.basicKey;

			if (!evels.getCount(cast(ubyte) u, cast(ubyte) EventKind.key)) {
				evels.recordAdd(0, cast(ubyte) u, EventKind.key, cast(int) 0x6000);
			}
			evels.recordValueChange(0, -1, cast(ubyte) u, EventKind.key, changeValue);
		}
	}

	// fix old tuning (1.0)
	///
	private void x3xAddTuningEvent() @safe {
		enforce!PxtoneException(units.length <= woices.length, "Too many units");

		for (int u = 0; u < units.length; u++) {
			float tuning = woices[u].getX3xTuning();
			if (tuning) {
				evels.recordAdd(0, cast(ubyte) u, EventKind.tuning, tuning);
			}
		}
	}

	///
	private void x3xSetVoiceNames() @safe {
		for (int i = 0; i < woices.length; i++) {
			char[pxtnMaxTuneWoiceName + 1] name = 0;
			sformat(name[], "voice_%02d", i);
			woices[i].setNameBuf(name.dup);
		}
	}

	///
	private void preCountEvent(ref const(ubyte)[] buffer, out int pCount) @safe {
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

		readVersion(buffer, fmtVer, exeVer);

		if (fmtVer == FMTVER.x1x) {
			pCount = 10000;
			return;
		}

		while (!bEnd) {
			buffer.pop(code[0 .. identifierCodeSize]);
			switch (checkTagCode(code)) {
			case Tag.EventV5:
				count += evels.ioReadEventNum(buffer);
				break;
			case Tag.MasterV5:
				count += master.ioReadEventNumber(buffer);
				break;
			case Tag.x4xEvenMAST:
				count += master.ioReadOldEventNumber(buffer);
				break;
			case Tag.x4xEvenUNIT:
				evels.ioReadX4xEventNum(buffer, c);
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

				buffer.pop(size);
				buffer = buffer[size .. $];
				break;

				// ignore
			case Tag.x1xPROJ:
			case Tag.x1xUNIT:
			case Tag.x1xPCM:
			case Tag.x1xEVEN:
			case Tag.x1xEND:
				throw new PxtoneException("x1x ignore");
			default:
				throw new PxtoneException("Unknown tag: "~ code.idup);
			}
		}

		if (fmtVer <= FMTVER.x3x) {
			count += pxtnMaxTuneUnitStruct * 4; // voice number, group number, key tuning, key event x3x
		}

		pCount = count;
	}
}

@safe unittest {
	ubyte[] trustedRead(string filename) @trusted {
		import std.file : read;
		return cast(ubyte[])read(filename);
	}
	import std.array : Appender;
	import std.algorithm.comparison : equal;
	import std.algorithm.iteration : map;
	auto song = PxToneSong(trustedRead("pxtone/sample data/sample.ptcop"));
	assert(song.text.getCommentBuf() == "boss03\r\n13/03/07\r\n13/06/27 fix tr1 maes9-\r\n");
	assert(song.text.getNameBuf() == "Hard Cording");
	assert(song.units.map!(x => x.getNameBuf().dup).equal(["Brass", "Techno", "Middle", "Bass", "Dr Hi Hat", "u-drum_snare2", "Dr Bass"]));

	Appender!(ubyte[]) outfile;
	song.write(outfile, false, 931);

	const finalData = outfile[];
	const rtSong = PxToneSong(finalData);
	assert(rtSong.text.getNameBuf() == "Hard Cording");
	// TODO: make a more complete comparison
}


///
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
