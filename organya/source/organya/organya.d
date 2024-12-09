///
module organya.organya;

import core.time;
import std.algorithm.comparison;
import std.exception;
import std.experimental.logger;
import std.math;

import retroseq.interpolation;
import retroseq.mixer;
import organya.params;
import organya.pixtone;

public import retroseq.interpolation : InterpolationMethod;

private enum maxTrack = 16; ///
private enum maxMelody = 8; ///

private enum panDummy = 0xFF; ///
private enum volDummy = 0xFF; ///
private enum keyDummy = 0xFF; ///

private enum allocNote = 4096; ///

// Below are Organya song data structures

///
private struct NoteList {
	NoteList *from; /// Previous address
	NoteList *to; /// Next address

	int x; /// Position
	ubyte length; /// Sound length
	ubyte y = keyDummy; /// Sound height
	ubyte volume = volDummy; /// Volume
	ubyte pan = panDummy; ///
}

/// Track data * 8
private struct TrackData {
	ushort freq;	/// Frequency (1000 is default)
	ubyte waveNumber; ///
	byte pipi; ///

	NoteList[] notePosition; ///
	NoteList *noteList; ///
}

/// Unique information held in songs
public struct MusicInfo {
	ushort wait; ///
	ubyte line; /// Number of lines in one measure
	ubyte dot; /// Number of dots per line
	ushort allocatedNotes; ///
	int repeatX; /// Repeat
	int endX; /// End of song (Return to repeat)
	TrackData[maxTrack] trackData; ///
}

/// Wave playing and loading
private struct OctaveWave {
	short waveSize; ///
	short octavePar; ///
	short octaveSize; ///
}

///
private immutable OctaveWave[8] octaveWaves = [
	{ 256,  1,  4 }, // 0 Oct
	{ 256,  2,  8 }, // 1 Oct
	{ 128,  4, 12 }, // 2 Oct
	{ 128,  8, 16 }, // 3 Oct
	{  64, 16, 20 }, // 4 Oct
	{  32, 32, 24 }, // 5 Oct
	{  16, 64, 28 }, // 6 Oct
	{   8,128, 32 }, // 7 Oct
];


private immutable short[12] frequencyTable = [262, 277, 294, 311, 330, 349, 370, 392, 415, 440, 466, 494]; ///

private immutable short[13] panTable = [0, 43, 86, 129, 172, 215, 256, 297, 340, 383, 426, 469, 512]; ///


/// 波形データをロード (Load waveform data)
private immutable byte[0x100][100] waveData = initWaveData(cast(immutable(ubyte)[])import("Wave.dat"));

///
private byte[0x100][100] initWaveData(const(ubyte)[] data) @safe {
	byte[0x100][100] result;
	foreach (x1, ref x2; result) {
		foreach (idx, ref y; x2) {
			y = cast(byte)data[x1 * 0x100 + idx];
		}
	}
	return result;
}

///
struct OrganyaSong {
	MusicInfo info;
}

///
struct TrackState {
	const(NoteList)* np;
	int volume;
	bool muted;
	ubyte playingSounds = 0xFF; /// 再生中の音 (Sound being played)
	ubyte keyOn; /// キースイッチ (Key switch)
	ubyte keyTwin; /// 今使っているキー(連続時のノイズ防止の為に二つ用意) (Currently used keys (prepared for continuous noise prevention))
}

///
struct Organya {
	private size_t[2][8][8] allocatedSounds; ///
	private size_t[512] secondaryAllocatedSounds; ///
	private const(OrganyaSong)[] song;
	private Mixer mixer; ///
	private const(PixtoneObject)[] pixtoneObjects = defaultPixtoneObjects; /// Pixtone objects to use for instrumentation. Only used during initialization.

	// Play data
	private int playPosition; ///
	private int[maxMelody] nowLength; ///

	private int globalVolume = 100; ///
	private bool fading = false; ///
	TrackState[maxTrack] tracks; ///

	///
	private inout(TrackState)[] melodyTracks() inout @safe nothrow return {
		return tracks[0 .. maxMelody];
	}
	///
	private inout(TrackState)[] drumTracks() inout @safe nothrow return {
		return tracks[maxMelody .. $];
	}
	/// 曲情報を取得 (Get song information)
	public const(MusicInfo) info() const @safe pure nothrow {
		assert(song.length == 1, "No song loaded");
		return song[0].info;
	}
	///
	public void initialize(uint outputFrequency, InterpolationMethod method) @safe {
		mixer = Mixer(method, outputFrequency, &playData);
		foreach (obj; pixtoneObjects) {
			makePixToneObject(obj.params, obj.id);
		}
	}

	// 以下は再生 (The following is playback)
	///
	private void playData() @safe nothrow {
		// Handle fading out
		if (fading && globalVolume) {
			globalVolume -= 2;
		}
		if (globalVolume < 0) {
			globalVolume = 0;
		}

		// メロディの再生 (Play melody)
		for (int i = 0; i < melodyTracks.length; i++) {
			if (melodyTracks[i].np != null && playPosition == melodyTracks[i].np.x) {
				if (!melodyTracks[i].muted && melodyTracks[i].np.y != keyDummy) {	// 音が来た。 (The sound has come.)
					playOrganObject(melodyTracks[i].np.y, -1, cast(byte)i, info.trackData[i].freq);
					nowLength[i] = melodyTracks[i].np.length;
				}

				if (melodyTracks[i].np.pan != panDummy) {
					changeOrganPan(melodyTracks[i].np.y, melodyTracks[i].np.pan, cast(byte)i);
				}
				if (melodyTracks[i].np.volume != volDummy) {
					melodyTracks[i].volume = melodyTracks[i].np.volume;
				}

				melodyTracks[i].np = melodyTracks[i].np.to;	// 次の音符を指す (Points to the next note)
			}

			if (nowLength[i] == 0) {
				playOrganObject(0, 2, cast(byte)i, info.trackData[i].freq);
			}

			if (nowLength[i] > 0) {
				nowLength[i]--;
			}

			if (melodyTracks[i].np) {
				changeOrganVolume(melodyTracks[i].np.y, melodyTracks[i].volume * globalVolume / 0x7F, cast(byte)i);
			}
		}

		// ドラムの再生 (Drum playback)
		for (int i = 0; i < drumTracks.length; i++) {
			if (drumTracks[i].np != null && playPosition == drumTracks[i].np.x) {	// 音が来た。 (The sound has come.)
				if (drumTracks[i].np.y != keyDummy && !drumTracks[i].muted) {	// ならす (Tame)
					playDrumObject(drumTracks[i].np.y, 1, cast(byte)i);
				}

				if (drumTracks[i].np.pan != panDummy) {
					changeDrumPan(drumTracks[i].np.pan, cast(byte)i);
				}
				if (drumTracks[i].np.volume != volDummy) {
					drumTracks[i].volume = drumTracks[i].np.volume;
				}

				drumTracks[i].np = drumTracks[i].np.to;	// 次の音符を指す (Points to the next note)
			}

			if (drumTracks[i].np)
				changeDrumVolume(drumTracks[i].volume * globalVolume / 0x7F, cast(byte)i);
		}

		// Looping
		playPosition++;
		if (playPosition >= info.endX) {
			playPosition = info.repeatX;
			setPlayPointer(playPosition);
		}
	}

	///
	private void setPlayPointer(int x) @safe nothrow {
		for (int i = 0; i < tracks.length; i++) {
			tracks[i].np = info.trackData[i].noteList;
			while (tracks[i].np != null && tracks[i].np.x < x) {
				tracks[i].np = tracks[i].np.to;	// 見るべき音符を設定 (Set note to watch)
			}
		}

		playPosition = x;
	}
	public void loadSong(const OrganyaSong song) @safe {
		this.song = [song];

		// データを有効に (Enable data)
		for (int j = 0; j < maxMelody; j++) {
			makeOrganyaWave(cast(byte)j, song.info.trackData[j].waveNumber, song.info.trackData[j].pipi);
		}

		setPlayPointer(0);	// 頭出し (Cue)

		globalVolume = 100;
		fading = 0;
	}
	///
	public void setPosition(uint x) @safe {
		setPlayPointer(x);
		globalVolume = 100;
		fading = false;
	}

	///
	public uint getPosition() @safe {
		return playPosition;
	}

	///
	public void playMusic() @safe {
		setMusicTimer(info.wait);
	}
	///
	private void makeSoundObject8(const byte[] wavep, byte track, byte pipi) @safe {
		uint i,j,k;
		uint waveTable;	// WAVテーブルをさすポインタ (Pointer to WAV table)
		uint waveSize;	// 256;
		uint dataSize;
		ubyte[] wp;
		ubyte[] wpSub;
		int work;

		for (j = 0; j < 8; j++) {
			for (k = 0; k < 2; k++) {
				waveSize = octaveWaves[j].waveSize;

				if (pipi) {
					dataSize = waveSize * octaveWaves[j].octaveSize;
				} else {
					dataSize = waveSize;
				}

				wp = new ubyte[](dataSize);


				// Get wave data
				wpSub = wp;
				waveTable = 0;

				for (i = 0; i < dataSize; i++) {
					work = wavep[waveTable];
					work += 0x80;

					wpSub[0] = cast(ubyte)work;

					waveTable += 0x100 / waveSize;
					if (waveTable > 0xFF) {
						waveTable -= 0x100;
					}

					wpSub = wpSub[1 .. $];
				}

				allocatedSounds[track][j][k] = mixer.createSound(22050, wp[0 .. dataSize]);

				mixer.getSound(allocatedSounds[track][j][k]).seek(0);
			}
		}
	}
	///
	private void changeOrganFrequency(ubyte key, byte track, int a) @safe nothrow {
		for (int j = 0; j < 8; j++) {
			for (int i = 0; i < 2; i++) {
				mixer.getSound(allocatedSounds[track][j][i]).frequency = cast(uint)(((octaveWaves[j].waveSize * frequencyTable[key]) * octaveWaves[j].octavePar) / 8 + (a - 1000));	// 1000を+αのデフォルト値とする (1000 is the default value for + α)
			}
		}
	}
	///
	private void changeOrganPan(ubyte key, ubyte pan, byte track) @safe nothrow {	// 512がMAXで256がﾉｰﾏﾙ (512 is MAX and 256 is normal)
		if (tracks[track].playingSounds != keyDummy) {
			mixer.getSound(allocatedSounds[track][tracks[track].playingSounds / 12][tracks[track].keyTwin]).pan = (panTable[pan] - 0x100) * 10;
		}
	}

	///
	private void changeOrganVolume(int no, int volume, byte track) @safe nothrow {	// 300がMAXで300がﾉｰﾏﾙ (300 is MAX and 300 is normal)
		if (tracks[track].playingSounds != keyDummy) {
			mixer.getSound(allocatedSounds[track][tracks[track].playingSounds / 12][tracks[track].keyTwin]).volume = cast(short)((volume - 0xFF) * 8);
		}
	}

	// サウンドの再生 (Play sound)
	///
	private void playOrganObject(ubyte key, int mode, byte track, int freq) @safe nothrow {
		switch (mode) {
			case 0:	// 停止 (Stop)
				if (tracks[track].playingSounds != 0xFF) {
					mixer.getSound(allocatedSounds[track][tracks[track].playingSounds / 12][tracks[track].keyTwin]).stop();
					mixer.getSound(allocatedSounds[track][tracks[track].playingSounds / 12][tracks[track].keyTwin]).seek(0);
				}
				break;

			case 1: // 再生 (Playback)
				break;

			case 2:	// 歩かせ停止 (Stop playback)
				if (tracks[track].playingSounds != 0xFF) {
					mixer.getSound(allocatedSounds[track][tracks[track].playingSounds / 12][tracks[track].keyTwin]).play(false);
					tracks[track].playingSounds = 0xFF;
				}
				break;

			case -1:
				if (tracks[track].playingSounds == 0xFF) {	// 新規鳴らす (New sound)
					changeOrganFrequency(key % 12, track, freq);	// 周波数を設定して (Set the frequency)
					mixer.getSound(allocatedSounds[track][key / 12][tracks[track].keyTwin]).play(true);
					tracks[track].playingSounds = key;
					tracks[track].keyOn = 1;
				}
				else if (tracks[track].keyOn == 1 && tracks[track].playingSounds == key) {	// 同じ音 (Same sound)
					// 今なっているのを歩かせ停止 (Stop playback now)
					mixer.getSound(allocatedSounds[track][tracks[track].playingSounds / 12][tracks[track].keyTwin]).play(false);
					tracks[track].keyTwin++;
					if (tracks[track].keyTwin > 1) {
						tracks[track].keyTwin = 0;
					}
					mixer.getSound(allocatedSounds[track][key / 12][tracks[track].keyTwin]).play(true);
				}
				else {	// 違う音を鳴らすなら (If you make a different sound)
					mixer.getSound(allocatedSounds[track][tracks[track].playingSounds / 12][tracks[track].keyTwin]).play(false);	// 今なっているのを歩かせ停止 (Stop playback now)
					tracks[track].keyTwin++;
					if (tracks[track].keyTwin > 1) {
						tracks[track].keyTwin = 0;
					}
					changeOrganFrequency(key % 12, track, freq);	// 周波数を設定して (Set the frequency)
					mixer.getSound(allocatedSounds[track][key / 12][tracks[track].keyTwin]).play(true);
					tracks[track].playingSounds = key;
				}

				break;
			default: break;
		}
	}
	///
	private void makeOrganyaWave(byte track, byte waveNumber, byte pipi) @safe {
		enforce(waveNumber <= 100, "Wave number out of range");

		makeSoundObject8(waveData[waveNumber], track, pipi);
	}
	/////////////////////////////////////////////
	//■オルガーニャドラムス■■■■■■■■/////// (Organya drums)
	/////////////////////

	///
	private void changeDrumFrequency(ubyte key, byte track) @safe nothrow {
		mixer.getSound(secondaryAllocatedSounds[150 + track]).frequency = key * 800 + 100;
	}

	///
	private void changeDrumPan(ubyte pan, byte track) @safe nothrow {
		mixer.getSound(secondaryAllocatedSounds[150 + track]).pan = (panTable[pan] - 0x100) * 10;
	}

	///
	private void changeDrumVolume(int volume, byte track) @safe nothrow
	{
		mixer.getSound(secondaryAllocatedSounds[150 + track]).volume = cast(short)((volume - 0xFF) * 8);
	}

	/// サウンドの再生 (Play sound)
	private void playDrumObject(ubyte key, int mode, byte track) @safe nothrow {
		switch (mode) {
			case 0:	// 停止 (Stop)
				mixer.getSound(secondaryAllocatedSounds[150 + track]).stop();
				mixer.getSound(secondaryAllocatedSounds[150 + track]).seek(0);
				break;

			case 1:	// 再生 (Playback)
				mixer.getSound(secondaryAllocatedSounds[150 + track]).stop();
				mixer.getSound(secondaryAllocatedSounds[150 + track]).seek(0);
				changeDrumFrequency(key, track);	// 周波数を設定して (Set the frequency)
				mixer.getSound(secondaryAllocatedSounds[150 + track]).play(false);
				break;

			case 2:	// 歩かせ停止 (Stop playback)
				break;

			case -1:
				break;
			default: break;
		}
	}
	///
	public void changeVolume(int volume) @safe {
		enforce((volume >= 0) && (volume <= 100), "Volume out of range");

		globalVolume = volume;
	}

	///
	public void stopMusic() @safe {
		setMusicTimer(0);

		// Stop notes
		for (int i = 0; i < maxMelody; i++) {
			playOrganObject(0, 2, cast(byte)i, 0);
		}

		tracks[] = TrackState.init;
	}

	///
	public void setFadeout() @safe {
		fading = true;
	}

	///
	public void fillBuffer(scope short[2][] finalBuffer) nothrow @safe {
		mixer.mixSounds(finalBuffer);
	}
	/// Overrides the instrumentation with custom pixtone objects. Be sure to call this BEFORE initialization!
	public void loadData(const(PixtoneObject)[] data) @safe {
		pixtoneObjects = data;
	}
	///
	void setMusicTimer(uint milliseconds) @safe {
		mixer.setCallbackFrequency(milliseconds.msecs);
	}

	///
	private int makePixToneObject(const(PixtoneParameter)[] ptp, int no) @safe {
		int sampleCount;
		int i, j;
		ubyte[] pcmBuffer;
		ubyte[] mixedPCMBuffer;

		sampleCount = 0;

		for (i = 0; i < ptp.length; i++) {
			if (ptp[i].size > sampleCount) {
				sampleCount = ptp[i].size;
			}
		}

		pcmBuffer = mixedPCMBuffer = null;

		pcmBuffer = new ubyte[](sampleCount);
		mixedPCMBuffer = new ubyte[](sampleCount);

		pcmBuffer[0 .. sampleCount] = 0x80;
		mixedPCMBuffer[0 .. sampleCount] = 0x80;

		for (i = 0; i < ptp.length; i++) {
			MakePixelWaveData(ptp[i], pcmBuffer);

			for (j = 0; j < ptp[i].size; j++) {
				if (pcmBuffer[j] + mixedPCMBuffer[j] - 0x100 < -0x7F) {
					mixedPCMBuffer[j] = 0;
				} else if (pcmBuffer[j] + mixedPCMBuffer[j] - 0x100 > 0x7F) {
					mixedPCMBuffer[j] = 0xFF;
				} else {
					mixedPCMBuffer[j] = cast(ubyte)(mixedPCMBuffer[j] + pcmBuffer[j] - 0x80);
				}
			}
		}

		secondaryAllocatedSounds[no] = mixer.createSound(22050, mixedPCMBuffer[0 .. sampleCount]);

		return sampleCount;
	}
}


///
public static OrganyaSong createSong(const(ubyte)[] p) @safe pure
	in(p, "No organya data")
{
	OrganyaSong song;
	static ushort readLE16(ref const(ubyte)[] p) { scope(exit) p = p[2 .. $]; return ((p[1] << 8) | p[0]); }
	static uint readLE32(ref const(ubyte)[] p) { scope(exit) p = p[4 .. $]; return ((p[3] << 24) | (p[2] << 16) | (p[1] << 8) | p[0]); }

	song.info.allocatedNotes = allocNote;
	song.info.dot = 4;
	song.info.line = 4;
	song.info.wait = 128;
	song.info.repeatX = song.info.dot * song.info.line * 0;
	song.info.endX = song.info.dot * song.info.line * 255;

	for (int i = 0; i < maxTrack; i++) {
		song.info.trackData[i].freq = 1000;
		song.info.trackData[i].waveNumber = 0;
		song.info.trackData[i].pipi = 0;
	}

	for (int j = 0; j < maxTrack; j++) {
		song.info.trackData[j].waveNumber = 0;
		song.info.trackData[j].noteList = null;
		song.info.trackData[j].notePosition = new NoteList[](song.info.allocatedNotes);

		for (int i = 0; i < song.info.allocatedNotes; i++) {
			song.info.trackData[j].notePosition[i] = NoteList.init;
		}
	}

	NoteList[] np;
	char ver = 0;
	ushort[maxTrack] noteCounts;

	enforce(p != null, "No data to load");

	if(p[0 .. 6] == pass) {
		ver = 1;
	}
	if(p[0 .. 6] == pass2) {
		ver = 2;
	}
	p = p[6 .. $];

	enforce(ver != 0, "Invalid version");

	// 曲の情報を設定 (Set song information)
	song.info.wait = readLE16(p);
	song.info.line = p[0];
	p = p[1 .. $];
	song.info.dot = p[0];
	p = p[1 .. $];
	song.info.repeatX = readLE32(p);
	song.info.endX = readLE32(p);

	for (int i = 0; i < maxTrack; i++) {
		song.info.trackData[i].freq = readLE16(p);

		song.info.trackData[i].waveNumber = p[0];
		p = p[1 .. $];

		if (ver == 1) {
			song.info.trackData[i].pipi = 0;
		} else {
			song.info.trackData[i].pipi = p[0];
		}

		p = p[1 .. $];

		noteCounts[i] = readLE16(p);
	}

	// 音符のロード (Loading notes)
	for (int j = 0; j < maxTrack; j++) {
		// 最初の音符はfromがNULLとなる (The first note has from as NULL)
		if (noteCounts[j] == 0) {
			song.info.trackData[j].noteList = null;
			continue;
		}

		// リストを作る (Make a list)
		np = song.info.trackData[j].notePosition;
		song.info.trackData[j].noteList = &song.info.trackData[j].notePosition[0];
		assert(np);
		np[0].from = null;
		np[0].to = &np[1];

		for (int i = 1; i < noteCounts[j] - 1; i++) {
			np[i].from = &np[i - 1];
			np[i].to = &np[i + 1];
		}

		// 最後の音符のtoはNULL (The last note to is NULL)
		np[$ - 1].to = null;

		// 内容を代入 (Assign content)
		np = song.info.trackData[j].notePosition;	// Ｘ座標 (X coordinate)
		for (int i = 0; i < noteCounts[j]; i++) {
			np[i].x = readLE32(p);
		}

		np = song.info.trackData[j].notePosition;	// Ｙ座標 (Y coordinate)
		for (int i = 0; i < noteCounts[j]; i++) {
			np[i].y = p[0];
			p = p[1 .. $];
		}

		np = song.info.trackData[j].notePosition;	// 長さ (Length)
		for (int i = 0; i < noteCounts[j]; i++) {
			np[i].length = p[0];
			p = p[1 .. $];
		}

		np = song.info.trackData[j].notePosition;	// ボリューム (Volume)
		for (int i = 0; i < noteCounts[j]; i++) {
			np[i].volume = p[0];
			p = p[1 .. $];
		}

		np = song.info.trackData[j].notePosition;	// パン (Pan)
		for (int i = 0; i < noteCounts[j]; i++) {
			np[i].pan = p[0];
			p = p[1 .. $];
		}
	}
	return song;
}

private immutable pass = "Org-01"; ///
private immutable pass2 = "Org-02"; /// Pipi
