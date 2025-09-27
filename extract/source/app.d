import std;

import retroseq.nspc;


int main(string[] args) {
		(cast()sharedLog).logLevel = LogLevel.trace;
	const rom = readROM(args[1]);
	NSPC2Writer writer;
	if (rom.title == "KIRBY SUPER DELUXE   ") {
		extractKSS(writer, rom.data);
	} else if (rom.title == "Kirby's Dream Course ") {
		extractKDC(writer, rom.data);
	} else if (rom.title == "KIRBY'S DREAM LAND 3 ") {
		extractKDL3(writer, rom.data);
	} else if (rom.title == "EARTH BOUND          ") {
		extractEarthbound(writer, rom.data, false, 0x4F947, 0x4F70A);
	} else if (rom.title == "MOTHER-2             ") {
		extractEarthbound(writer, rom.data, true, 0x4CCE2, 0x4CAA5);
	} else if (rom.title == "01 95.03.27          ") {
		extractEarthbound(writer, rom.data, false, 0x4FBD4, 0x4F997);
	} else if (rom.title == "SUPER MARIOWORLD     ") {
		extractSMW(writer, rom.data);
	} else if (rom.title == "PILOTWINGS           ") {
		extractPilotWings(writer, rom.data);
	} else if (rom.title == "F-ZERO               ") {
		extractFZ(writer, rom.data);
	} else if (rom.title == "THE LEGEND OF ZELDA  ") {
		extractZ3(writer, rom.data);
	} else if (rom.title == "SUPER MARIO ALL_STARS") {
		extractSMAS(writer, rom.data);
	} else if (rom.title == "Super Metroid        ") {
		extractSMET(writer, rom.data);
	} else if (rom.title == "YOSHI'S ISLAND       ") {
		extractYI(writer, rom.data);
	} else {
		writefln!"I don't know what '%s' is."(rom.title);
		return 1;
	}
	Appender!(ubyte[]) buffer;
	writer.toBytes(buffer);
	infof("Validating...");
	(cast()sharedLog).logLevel = LogLevel.info;
	const loadedSong = loadNSPC2File(buffer.data);
	infof("Writing %s", args[2]);
	File(args[2], "w").rawWrite(buffer.data);
	return 0;
}

ROMFile readROM(string path) {
	const rom = cast(ubyte[])std.file.read(path);
	immutable headerOffsets = [
		0x7FB0: false, //lorom
		0xFFB0: false, //hirom
		0x81B0: true, //lorom + copier header
		0x101B0: true, //hirom + copier header
	];
	foreach (offset, stripHeader; headerOffsets) {
		const ushort checksum = (cast(const(ushort)[])rom[offset + 44 .. offset + 46])[0];
		const ushort checksumComplement = (cast(const(ushort)[])rom[offset + 46 .. offset + 48])[0];
		if ((checksum ^ checksumComplement) == 0xFFFF) {
			return ROMFile((cast(char[])rom[offset + 16 .. offset + 37]).idup, rom[stripHeader ? 0x200 : 0 .. $]);
		}
	}
	return ROMFile.init;
}
