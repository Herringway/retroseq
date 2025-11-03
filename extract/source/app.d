import std;

import retroseq.nspc;


int main(string[] args) {
	(cast()sharedLog).logLevel = LogLevel.trace;
	auto buffer = extractROM(cast(ubyte[])std.file.read(args[1]));
	infof("Validating...");
	(cast()sharedLog).logLevel = LogLevel.info;
	const loadedSong = loadNSPC2File(buffer);
	infof("Writing %s", args[2]);
	File(args[2], "w").rawWrite(buffer);
	return 0;
}
