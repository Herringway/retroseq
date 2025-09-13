///
module organya.organya;

import core.time;
import std.algorithm.comparison;
import std.exception;
import std.experimental.logger;
import std.math;

import retroseq.interpolation;
import retroseq.mixer;
import retroseq.utility;
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
	ushort freq = 1000;	/// Frequency (1000 is default)
	ubyte waveNumber = 0; ///
	byte pipi = 0; ///

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
	int nowLength; ///
}

deprecated("Use OrganyaNoMixer") alias Organya = OrganyaNoMixer;
alias OrganyaMixer = OrganyaBase!true;
alias OrganyaNoMixer = OrganyaBase!false;

///
private struct OrganyaBase(bool refMixer) {
	private size_t[2][8][8] allocatedSounds; ///
	size_t[512] secondaryAllocatedSounds; ///
	private const(OrganyaSong)[] song;
	static if (refMixer) {
		private Mixer* mixer; ///
	} else {
		private Mixer mixer; ///
	}
	private const(PixtoneObject)[] pixtoneObjects = defaultPixtoneObjects; /// Pixtone objects to use for instrumentation. Only used during initialization.

	// Play data
	private int playPosition; ///

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
	static if (refMixer) {
		public void initialize(Mixer* mixer) @safe {
			this.mixer = mixer;
			initializeCommon();
		}
	} else {
		///
		public void initialize(uint outputFrequency, InterpolationMethod method) @safe {
			mixer = Mixer(method, outputFrequency, &playData);
			initializeCommon();
		}
	}
	public void initializeCommon() @safe {
		foreach (obj; pixtoneObjects) {
			makePixToneObject(obj.params, obj.id);
		}
	}

	// 以下は再生 (The following is playback)
	///
	void playData() @safe nothrow {
		// Handle fading out
		if (fading && globalVolume) {
			globalVolume -= 2;
		}
		if (globalVolume < 0) {
			globalVolume = 0;
		}

		// メロディの再生 (Play melody)
		foreach (trackIdx, ref track; melodyTracks) {
			if (track.np != null && playPosition == track.np.x) {
				if (!track.muted && track.np.y != keyDummy) {	// 音が来た。 (The sound has come.)
					playOrganObject(track.np.y, -1, cast(byte)trackIdx, info.trackData[trackIdx].freq);
					track.nowLength = track.np.length;
				}

				if (track.np.pan != panDummy) {
					changeOrganPan(track.np.y, track.np.pan, cast(byte)trackIdx);
				}
				if (track.np.volume != volDummy) {
					track.volume = track.np.volume;
				}

				track.np = track.np.to;	// 次の音符を指す (Points to the next note)
			}

			if (track.nowLength == 0) {
				playOrganObject(0, 2, cast(byte)trackIdx, info.trackData[trackIdx].freq);
			}

			if (track.nowLength > 0) {
				track.nowLength--;
			}

			if (track.np) {
				changeOrganVolume(track.np.y, track.volume * globalVolume / 0x7F, cast(byte)trackIdx);
			}
		}

		// ドラムの再生 (Drum playback)
		foreach (trackIdx, ref track; drumTracks) {
			if (track.np != null && playPosition == track.np.x) {	// 音が来た。 (The sound has come.)
				if (track.np.y != keyDummy && !track.muted) {	// ならす (Tame)
					playDrumObject(track.np.y, 1, cast(byte)trackIdx);
				}

				if (track.np.pan != panDummy) {
					changeDrumPan(track.np.pan, cast(byte)trackIdx);
				}
				if (track.np.volume != volDummy) {
					track.volume = track.np.volume;
				}

				track.np = track.np.to;	// 次の音符を指す (Points to the next note)
			}

			if (track.np)
				changeDrumVolume(track.volume * globalVolume / 0x7F, cast(byte)trackIdx);
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
		foreach (idx, ref track; tracks) {
			track.np = info.trackData[idx].noteList;
			while (track.np != null && track.np.x < x) {
				track.np = track.np.to; // 見るべき音符を設定 (Set note to watch)
			}
		}

		playPosition = x;
	}
	public void loadSong(const OrganyaSong song) @safe {
		this.song = [song];

		// データを有効に (Enable data)
		foreach (trackIdx, const track; song.info.trackData[0 .. maxMelody]) {
			makeOrganyaWave(cast(byte)trackIdx, track.waveNumber, track.pipi);
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
	private void makeSoundObject8(const byte[] wavep, byte track, byte pipi) @safe pure {
		foreach (octave, ref octaveData; allocatedSounds[track]) {
			foreach (ref allocatedSound; octaveData) {
				uint waveSize = octaveWaves[octave].waveSize;
				uint dataSize = waveSize;

				if (pipi) {
					dataSize *= octaveWaves[octave].octaveSize;
				}

				auto wp = new ubyte[](dataSize);

				// WAVテーブルをさすポインタ (Pointer to WAV table)
				uint waveTable = 0;

				foreach (ref sample; wp) {
					sample = cast(ubyte)(wavep[waveTable] + 0x80);

					waveTable += 0x100 / waveSize;
					if (waveTable > 0xFF) {
						waveTable -= 0x100;
					}
				}

				allocatedSound = mixer.createSound(22050, wp);

				mixer.getSound(allocatedSound).seek(0);
			}
		}
	}
	///
	private void changeOrganFrequency(ubyte key, byte track, int a) @safe nothrow {
		foreach (octaveIdx, const octaveData; allocatedSounds[track]) {
			foreach (const allocatedSound; octaveData) {
				mixer.getSound(allocatedSound).frequency = cast(uint)(((octaveWaves[octaveIdx].waveSize * frequencyTable[key]) * octaveWaves[octaveIdx].octavePar) / 8 + (a - 1000));	// 1000を+αのデフォルト値とする (1000 is the default value for + α)
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
		foreach (byte track; 0 .. maxMelody) {
			playOrganObject(0, 2, track, 0);
		}

		tracks[] = TrackState.init;
	}

	///
	public void setFadeout() @safe {
		fading = true;
	}

	///
	public void fillBuffer(scope short[2][] finalBuffer) nothrow @safe {
		static if (refMixer) {
			mixSounds(*mixer, finalBuffer);
		} else {
			mixer.mixSounds(finalBuffer);
		}
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
	private int makePixToneObject(const(PixtoneParameter)[] parameters, int no) @safe {
		int sampleCount = 0;

		foreach (param; parameters) {
			sampleCount = max(param.size, sampleCount);
		}

		ubyte[] pcmBuffer = new ubyte[](sampleCount);
		ubyte[] mixedPCMBuffer = new ubyte[](sampleCount);

		pcmBuffer[0 .. sampleCount] = 0x80;
		mixedPCMBuffer[0 .. sampleCount] = 0x80;

		foreach (param; parameters) {
			MakePixelWaveData(param, pcmBuffer);

			foreach (offset, ref sample; mixedPCMBuffer[0 .. param.size]) {
				sample = cast(ubyte)clamp(sample + pcmBuffer[offset] - 0x80, 0, ubyte.max);
			}
		}

		secondaryAllocatedSounds[no] = mixer.createSound(22050, mixedPCMBuffer);

		return sampleCount;
	}
}


///
public static OrganyaSong createSong(const(ubyte)[] p) @safe pure
	in(p, "No organya data")
{
	OrganyaSong song;

	song.info.allocatedNotes = allocNote;
	song.info.dot = 4;
	song.info.line = 4;
	song.info.wait = 128;
	song.info.repeatX = song.info.dot * song.info.line * 0;
	song.info.endX = song.info.dot * song.info.line * 255;

	foreach (ref track; song.info.trackData) {
		track.notePosition = new NoteList[](song.info.allocatedNotes);
	}

	NoteList[] np;
	char ver = 0;
	ushort[maxTrack] noteCounts;

	enforce(p != null, "No data to load");

	switch (p.pop!(char[6])) {
		case pass: ver = 1; break;
		case pass2: ver = 2; break;
		default: throw new Exception("Invalid version");
	}

	// 曲の情報を設定 (Set song information)
	song.info.wait = p.pop!(LittleEndian!ushort).native;
	song.info.line = p.pop!ubyte;
	song.info.dot = p.pop!ubyte;
	song.info.repeatX = p.pop!(LittleEndian!uint).native;
	song.info.endX = p.pop!(LittleEndian!uint).native;

	foreach (trackIdx, ref track; song.info.trackData) {
		track.freq = p.pop!(LittleEndian!ushort).native;

		track.waveNumber = p.pop!ubyte;

		if (ver == 1) {
			track.pipi = 0;
		} else {
			track.pipi = p.peek!ubyte;
		}

		p.pop!ubyte();

		noteCounts[trackIdx] = p.pop!(LittleEndian!ushort).native;
	}

	// 音符のロード (Loading notes)
	foreach (trackIdx, ref track; song.info.trackData) {
		// 最初の音符はfromがNULLとなる (The first note has from as NULL)
		if (noteCounts[trackIdx] == 0) {
			track.noteList = null;
			continue;
		}

		// リストを作る (Make a list)
		np = track.notePosition;
		track.noteList = &track.notePosition[0];
		assert(np);
		np[0].from = null;
		np[0].to = &np[1];

		for (int i = 1; i < noteCounts[trackIdx] - 1; i++) {
			np[i].from = &np[i - 1];
			np[i].to = &np[i + 1];
		}

		// 最後の音符のtoはNULL (The last note to is NULL)
		np[$ - 1].to = null;

		// 内容を代入 (Assign content)
		np = track.notePosition;	// Ｘ座標 (X coordinate)
		for (int i = 0; i < noteCounts[trackIdx]; i++) {
			np[i].x = p.pop!(LittleEndian!uint).native;
		}

		np = track.notePosition;	// Ｙ座標 (Y coordinate)
		for (int i = 0; i < noteCounts[trackIdx]; i++) {
			np[i].y = p[0];
			p = p[1 .. $];
		}

		np = track.notePosition;	// 長さ (Length)
		for (int i = 0; i < noteCounts[trackIdx]; i++) {
			np[i].length = p[0];
			p = p[1 .. $];
		}

		np = track.notePosition;	// ボリューム (Volume)
		for (int i = 0; i < noteCounts[trackIdx]; i++) {
			np[i].volume = p[0];
			p = p[1 .. $];
		}

		np = track.notePosition;	// パン (Pan)
		for (int i = 0; i < noteCounts[trackIdx]; i++) {
			np[i].pan = p[0];
			p = p[1 .. $];
		}
	}
	return song;
}

private immutable pass = "Org-01"; ///
private immutable pass2 = "Org-02"; /// Pipi
