///
module retroseq.m4a.m4a;

import retroseq.utility;

import retroseq.m4a.cgb_audio;
import retroseq.m4a.internal;
import retroseq.m4a.m4a_tables;
import retroseq.m4a.music_player;
import retroseq.m4a.sound_mixer;

import std.algorithm.comparison;

///
struct Song {
	SongHeader header; ///
	const(RelativePointer!(ubyte, uint))[] parts; ///
}

///
struct M4APlayer {
	const(ubyte)[] musicData; ///
	uint songTableOffset; ///

	SoundMixerState soundInfo; ///
	uint playing = uint.max; ///
	uint activeTracks;
	bool paused;
	ubyte priority; ///
	ubyte cmd; ///
	uint clock; ///
	ubyte[0x10] memAccArea; ///
	ushort tempoRawBPM; ///
	ushort tempoScale = 0x100; ///
	ushort tempoInterval; ///
	ushort tempoCounter; ///
	ushort fadeInterval; ///
	ushort fadeCounter; ///
	bool temporaryFade;
	bool fadeIn;
	int fadeVolume;
	const(ToneData)[] voicegroup; ///
	MusicPlayerTrack[MAX_MUSICPLAYER_TRACKS] tracks; ///
	private float[2][] frameBuffer;
	private float[2][] frame;

	AudioCGB gb; ///
	float playerCounter = 0; ///
	///
	void initialize(uint outputFrequency, const(ubyte)[] _music, uint _songTableAddress, uint _mode) @safe pure {
		const mode = SoundMode(_mode);
		musicData = _music;
		songTableOffset = _songTableAddress;
		int i;

		SoundInit();
		soundInfo.SampleFreqSet(cast(ubyte)(mode.frequency - 1), outputFrequency);
		MPlayExtender();
		m4aSoundMode(&soundInfo, mode);

		MPlayOpen();
		gb.initialize(outputFrequency);
	}

	///
	void fillBuffer(float[2][] audioBuffer) @safe pure {
		while (audioBuffer.length > 0) {
			const lastFrameSamplesUsed = min(audioBuffer.length, frame.length);
			audioBuffer[0 .. lastFrameSamplesUsed] = frame[0 .. lastFrameSamplesUsed];
			audioBuffer = audioBuffer[lastFrameSamplesUsed .. $];
			frame = frame[lastFrameSamplesUsed .. $];
			if (frame.length == 0) {
				if (frameBuffer.length != soundInfo.samplesPerFrame) {
					frameBuffer = new float[2][](soundInfo.samplesPerFrame);
				}
				RunMixerFrame(this, frameBuffer);
				frame = frameBuffer;
			}
		}
	}
	///
	void MPlayExtender() @safe pure {
		soundInfo.reg.panCh1Right = 0;
		soundInfo.reg.panCh2Right = 0;
		soundInfo.reg.panCh3Right = 0;
		soundInfo.reg.panCh4Right = 0;
		soundInfo.reg.panCh1Left = 0;
		soundInfo.reg.panCh2Left = 0;
		soundInfo.reg.panCh3Left = 0;
		soundInfo.reg.panCh4Left = 0;
		soundInfo.reg.enableAPU = true;
		soundInfo.reg.enabledChannels[] = true;
		soundInfo.reg.NR12 = 0x8;
		soundInfo.reg.NR22 = 0x8;
		soundInfo.reg.NR42 = 0x8;
		soundInfo.reg.sound1CntX.restart = true;
		soundInfo.reg.sound2CntH.restart = true;
		soundInfo.reg.NR44 = 0x80;
		soundInfo.reg.channel3DACEnable = false;
		soundInfo.reg.vinLeft = 0;
		soundInfo.reg.leftVolume = 7;
		soundInfo.reg.vinRight = 0;
		soundInfo.reg.rightVolume = 7;


		for (ubyte i = 0; i < 4; i++) {
			gb.set_envelope(i, 8);
			gb.trigger_note(i);
		}

		soundInfo.cgbChans[0].type.cgbType = CGBType.pulse1;
		soundInfo.cgbChans[0].panMask = 0x11;
		soundInfo.cgbChans[1].type.cgbType = CGBType.pulse2;
		soundInfo.cgbChans[1].panMask = 0x22;
		soundInfo.cgbChans[2].type.cgbType = CGBType.gbWave;
		soundInfo.cgbChans[2].panMask = 0x44;
		soundInfo.cgbChans[3].type.cgbType = CGBType.noise;
		soundInfo.cgbChans[3].panMask = 0x88;
	}
	///
	const(SongPointer)[] songTable() inout @safe pure {
		return sliceMax!SongPointer(musicData, songTableOffset);
	}
	///
	Song readSong(const SongPointer ptr) const @safe pure {
		assert(ptr.header.isValid(musicData));
		const ubyte[] data = (cast(const(ubyte)[])ptr.header.toAbsoluteArray(musicData));
		assert(data.length > 0);
		const partData = data[SongHeader.sizeof .. $].sliceMax!(RelativePointer!(ubyte, uint))(0);
		return Song(ptr.header.toAbsoluteArray(musicData)[0], partData);
	}
	///
	void songNumStart(ushort n) @safe pure {
		playing = n;
		MPlayStart(readSong(songTable[n]));
	}

	///
	void MPlayContinue() @safe pure {
		paused = false;
	}

	///
	void fadeOut(ushort speed) @safe pure {
		fadeCounter = speed;
		fadeInterval = speed;
		fadeVolume = 64;
	}

	/** Start playing a new song unless it's already playing
	 * Params:
	 * 	newSong = The new song to play
	 */
	void m4aSongNumStartOrChange(ushort newSong) @safe pure {
		if ((playing != newSong) || (activeTracks == 0) || paused) {
			songNumStart(newSong);
		}
	}

	/** Start playing a new song unless it's already playing, or resume currently paused song
	 * Params:
	 * 	newSong = The new song to play
	 */
	void m4aSongNumStartOrContinue(ushort newSong) @safe pure {
		if ((playing != newSong) || (activeTracks == 0)) {
			songNumStart(newSong);
		} else if (paused) {
			MPlayContinue();
		}
	}

	///
	void m4aSongNumStop(ushort n) @safe pure {
		if (playing == n) {
			m4aMPlayStop();
		}
	}

	///
	void m4aSongNumContinue(ushort n) @safe pure {
		if (playing == n) {
			MPlayContinue();
		}
	}

	///
	void m4aMPlayAllContinue() @safe pure {
		MPlayContinue();
	}

	///
	void m4aMPlayFadeOutTemporarily(ushort speed) @safe pure {
		fadeCounter = speed;
		fadeInterval = speed;
		fadeVolume = 64;
		temporaryFade = true;
	}

	///
	void m4aMPlayFadeIn(ushort speed) @safe pure {
		fadeCounter = speed;
		fadeInterval = speed;
		fadeVolume = 0;
		fadeIn = true;
		paused = false;
	}

	///
	void m4aMPlayImmInit() @safe pure {
		foreach (ref track; tracks) {
			if (track.exists) {
				if (track.start) {
					track.start = false;
					track.exists = true;
					track.bendRange = 2;
					track.volPublic = 64;
					track.lfoSpeed = 22;
					track.instrument.type = track.instrument.type.init;
					track.instrument.type.cgbType = CGBType.pulse1;
				}
			}
		}
	}




	///
	void ClearChain(ref SoundChannel x) @safe pure {
		MP2KClearChain(x);
	}

	///
	void SoundInit() @safe pure {
		soundInfo.reg.enableAPU = true;
		soundInfo.reg.enabledChannels[] = true;
		soundInfo.reg.resolution = 1;
	}

	///
	void SoundClear() @safe pure {
		foreach (ref chan; soundInfo.chans) {
			chan.clearStatusFlags();
		}

		foreach (idx, ref chan; soundInfo.cgbChans) {
			cgbNoteOffFunc(cast(CGBType)(idx + 1));
			chan.clearStatusFlags();
		}
	}

	///
	void MPlayOpen() @safe pure {
		if (tracks.length == 0) {
			return;
		}

		activeTracks = 0;
		paused = true;

		foreach (ref track; tracks) {
			track = track.init;
		}
	}

	///
	void MPlayStart(const Song song) @safe pure {
		if (!song.header.instrument.isValid) {
			return;
		}

		activeTracks = 0;
		paused = false;
		voicegroup = song.header.instrument.toAbsoluteArray(musicData);
		priority = song.header.priority;
		clock = 0;
		tempoRawBPM = 150;
		tempoInterval = 150;
		tempoCounter = 0;
		fadeInterval = 0;

		foreach (i, ref track; tracks) {
			TrackStop(this, track);
			track = track.init;
			if (i < song.header.trackCount) {
				track.exists = true;
				track.start = true;
				track.chan = null;
				track.cmdPtr = song.parts[i].toAbsoluteArray(musicData);
			}
		}

		if (SoundMode(song.header.reverb).reverbEnabled) {
			m4aSoundMode(&soundInfo, SoundMode(song.header.reverb));
		}
	}

	///
	void m4aMPlayStop() @safe pure {
		paused = true;

		foreach (ref track; tracks) {
			TrackStop(this, track);
		}
	}

	///
	void FadeOutBody(ref MusicPlayerTrack) @safe pure {
		return FadeOutBody();
	}
	///
	void FadeOutBody() @safe pure {
		if (fadeInterval == 0) {
			return;
		}
		if (--fadeCounter != 0) {
			return;
		}

		fadeCounter = fadeInterval;

		if (fadeIn) {
			fadeVolume = fadeVolume + 4;
			if (fadeVolume >= 64) {
				fadeVolume = 64;
				fadeInterval = 0;
			}
		} else {
			fadeVolume = fadeVolume - 4;
			if (fadeVolume <= 0) {
				foreach (ref track; tracks) {
					TrackStop(this, track);

					if (!temporaryFade) {
						track.volumeSet = false;
						track.unknown2 = false;
						track.pitchSet = false;
						track.unknown8 = false;
						track.start = false;
						track.exists = false;
					}
				}

				paused = true;
				if (!temporaryFade) {
					activeTracks = 0;
				}

				fadeInterval = 0;
				return;
			}
		}

		foreach (ref track; tracks) {
			if (track.exists) {
				track.volPublic = cast(ubyte)fadeVolume;
				track.volumeSet = true;
				track.unknown2 = true;
			}
		}
	}
	///
	void cgbNoteOffFunc(CGBType chanNum) @safe pure {
		final switch (chanNum) {
			case CGBType.pulse1:
				soundInfo.reg.NR12 = 8;
				soundInfo.reg.sound1CntX.restart = true;
				break;
			case CGBType.pulse2:
				soundInfo.reg.NR22 = 8;
				soundInfo.reg.sound2CntH.restart = true;
				break;
			case CGBType.gbWave:
				soundInfo.reg.channel3DACEnable = false;
				break;
			case CGBType.noise:
				soundInfo.reg.NR42 = 8;
				soundInfo.reg.NR44 = 0x80;
				break;
			case CGBType.directsound:
				assert(0, "Impossible");
		}

		gb.set_envelope(cast(ubyte)(chanNum - 1), 8);
		gb.trigger_note(cast(ubyte)(chanNum - 1));

	}

	///
	private int CgbPan(ref SoundChannel chan) @safe pure {
		if (chan.rightVolume >= chan.leftVolume) {
			if (chan.rightVolume / 2 >= chan.leftVolume) {
				chan.pan = 0x0F;
				return 1;
			}
		} else {
			if (chan.leftVolume / 2 >= chan.rightVolume) {
				chan.pan = 0xF0;
				return 1;
			}
		}

		return 0;
	}

	///
	void CgbModVol(ref SoundChannel chan) @safe pure {
		chan.envelopeGoal = (chan.rightVolume + chan.leftVolume) >> 4;
		if ((soundInfo.mode & 1) || !CgbPan(chan)) {
			chan.pan = 0xFF;
		} else if (chan.envelopeGoal > 15) {
			chan.envelopeGoal = 15;
		}

		chan.sustainGoal = cast(ubyte)((chan.envelopeGoal * chan.sustain + 15) >> 4);
		chan.pan &= chan.panMask;
	}

	///
	void cgbMixerFunc() @safe pure {
		ubyte *nrx0ptr;
		ubyte *nrx1ptr;
		ubyte *nrx2ptr;
		ubyte *nrx3ptr;
		ubyte *nrx4ptr;

		// Most comparision operations that cast to byte perform 'and' by 0xFF.
		int mask = 0xff;

		if (soundInfo.cgbCounter15) {
			soundInfo.cgbCounter15--;
		} else {
			soundInfo.cgbCounter15 = 14;
		}
		static void envelopeSustain(ref SoundChannel channel) {
			channel.envelopeVolume = channel.sustainGoal;
			channel.envelopeCounter = 7;
		}

		foreach (idx, ref channel; soundInfo.cgbChans) {
			int envelopeVolume, sustainGoal;
			if (!channel.isActive) {
				continue;
			}
			scope(exit) {
				channel.cgbVolumeChange = false;
				channel.cgbPitchChange = false;
			}

			/* 1. determine hardware channel registers */
			switch (idx + 1) {
				case 1:
					nrx0ptr = &soundInfo.reg.NR10;
					nrx1ptr = &soundInfo.reg.NR11;
					nrx2ptr = &soundInfo.reg.NR12;
					nrx3ptr = &soundInfo.reg.sound1CntX.low;
					nrx4ptr = &soundInfo.reg.sound1CntX.high;
					break;
				case 2:
					nrx0ptr = &soundInfo.reg.NR20;
					nrx1ptr = &soundInfo.reg.NR21;
					nrx2ptr = &soundInfo.reg.NR22;
					nrx3ptr = &soundInfo.reg.sound2CntH.low;
					nrx4ptr = &soundInfo.reg.sound2CntH.high;
					break;
				case 3:
					nrx0ptr = &soundInfo.reg.NR30;
					nrx1ptr = &soundInfo.reg.NR31;
					nrx2ptr = &soundInfo.reg.NR32;
					nrx3ptr = &soundInfo.reg.sound3CntX.low;
					nrx4ptr = &soundInfo.reg.sound3CntX.high;
					break;
				default:
					nrx0ptr = &soundInfo.reg.NR40;
					nrx1ptr = &soundInfo.reg.NR41;
					nrx2ptr = &soundInfo.reg.NR42;
					nrx3ptr = &soundInfo.reg.NR43;
					nrx4ptr = &soundInfo.reg.NR44;
					break;
			}

			int prevC15 = soundInfo.cgbCounter15;
			int envelopeStepTimeAndDir = *nrx2ptr;

			/* 2. calculate envelope volume */
			if (channel.start) {
				if (!channel.stop) {
					channel.start = false;
					channel.echoEnabled = false;
					channel.loop = false;
					channel.envelopeState = EnvelopeState.attack;
					channel.cgbVolumeChange = true;
					channel.cgbPitchChange = true;
					CgbModVol(channel);
					switch (idx + 1) {
						case 1:
							*nrx0ptr = channel.sweep;
							gb.set_sweep(channel.sweep);

							goto case;
						case 2:
							*nrx1ptr = cast(ubyte)((channel.squareNoiseConfig << 6) + channel.length);
							goto init_env_step_time_dir;
						case 3:
							if (channel.gbWav !is channel.currentPointer) {
								*nrx0ptr = 0x40;
								channel.currentPointer = channel.gbWav;
								gb.set_wavram(cast(ubyte[])channel.gbWav[]);
							}
							*nrx0ptr = 0;
							*nrx1ptr = channel.length;
							if (channel.length) {
								channel.n4 = 0xC0;
							} else {
								channel.n4 = 0x80;
							}
							break;
						default:
							*nrx1ptr = channel.length;
							*nrx3ptr = cast(ubyte)(channel.squareNoiseConfig << 3);
						init_env_step_time_dir:
							envelopeStepTimeAndDir = channel.attack + CGB_NRx2_ENV_DIR_INC;
							if (channel.length) {
								channel.n4 = 0x40;
							} else {
								channel.n4 = 0x00;
							}
							break;
					}
					gb.set_length(cast(ubyte)idx, channel.length);
					channel.envelopeCounter = channel.attack;
					if (cast(byte)(channel.attack & mask)) {
						channel.envelopeVolume = 0;
						goto envelope_step_complete;
					} else {
						// skip attack phase if attack is instantaneous (=0)
						goto envelope_decay_start;
					}
				} else {
					goto oscillator_off;
				}
			} else if (channel.echoEnabled) {
				channel.echoLength--;
				if (cast(byte)(channel.echoLength & mask) <= 0) {
				oscillator_off:
					cgbNoteOffFunc(cast(CGBType)(idx + 1));
					channel.start = false;
					channel.loop = false;
					channel.stop = false;
					channel.echoEnabled = false;
					channel.envelopeState = EnvelopeState.release;
					continue;
				}
				goto envelope_complete;
			} else if (channel.stop && (channel.envelopeState != EnvelopeState.release)) {
				channel.envelopeState = EnvelopeState.release;
				channel.envelopeCounter = channel.release;
				if (cast(byte)(channel.release & mask)) {
					channel.cgbVolumeChange = true;
					if (idx + 1 != CGBType.gbWave) {
						envelopeStepTimeAndDir = channel.release | CGB_NRx2_ENV_DIR_DEC;
					}
					goto envelope_step_complete;
				} else {
					goto envelope_pseudoecho_start;
				}
			} else {
			envelope_step_repeat:
				if (channel.envelopeCounter == 0) {
					if (idx + 1 == 3) {
						channel.cgbVolumeChange = true;
					}

					CgbModVol(channel);
					if (channel.envelopeState == EnvelopeState.release) {
						channel.envelopeVolume--;
						if (cast(byte)(channel.envelopeVolume & mask) <= 0) {
						envelope_pseudoecho_start:
							channel.envelopeVolume = ((channel.envelopeGoal * channel.echoVolume) + 0xFF) >> 8;
							if (channel.envelopeVolume) {
								channel.echoEnabled = true;
								channel.cgbVolumeChange = true;
								if (idx + 1 != 3) {
									envelopeStepTimeAndDir = 0 | CGB_NRx2_ENV_DIR_INC;
								}
								goto envelope_complete;
							} else {
								goto oscillator_off;
							}
						} else {
							channel.envelopeCounter = channel.release;
						}
					} else if (channel.envelopeState == EnvelopeState.sustain) {
						envelopeSustain(channel);
					} else if (channel.envelopeState == EnvelopeState.decay) {

						channel.envelopeVolume--;
						envelopeVolume = cast(byte)(channel.envelopeVolume & mask);
						sustainGoal = (byte)(channel.sustainGoal);
						if (envelopeVolume <= sustainGoal) {
						envelope_sustain_start:
							if (channel.sustain == 0) {
								channel.envelopeState = EnvelopeState.release;
								goto envelope_pseudoecho_start;
							} else {
								channel.envelopeState = cast(EnvelopeState)(channel.envelopeState - 1);
								channel.cgbVolumeChange = true;
								if (idx + 1 != 3) {
									envelopeStepTimeAndDir = 0 | CGB_NRx2_ENV_DIR_INC;
								}
								envelopeSustain(channel);
							}
						} else {
							channel.envelopeCounter = channel.decay;
						}
					} else {
						channel.envelopeVolume++;
						if ((ubyte)(channel.envelopeVolume & mask) >= channel.envelopeGoal) {
						envelope_decay_start:
							channel.envelopeState = cast(EnvelopeState)(channel.envelopeState - 1);
							channel.envelopeCounter = channel.decay;
							if ((ubyte)(channel.envelopeCounter & mask)) {
								channel.cgbVolumeChange = true;
								channel.envelopeVolume = channel.envelopeGoal;
								if (idx + 1 != 3) {
									envelopeStepTimeAndDir = channel.decay | CGB_NRx2_ENV_DIR_DEC;
								}
							} else {
								goto envelope_sustain_start;
							}
						} else {
							channel.envelopeCounter = channel.attack;
						}
					}
				}
			}

		envelope_step_complete:
			// every 15 frames, envelope calculation has to be done twice
			// to keep up with the hardware envelope rate (1/64 s)
			channel.envelopeCounter--;
			if (prevC15 == 0) {
				prevC15--;
				goto envelope_step_repeat;
			}

		envelope_complete:
			/* 3. apply pitch to HW registers */
			if (channel.cgbPitchChange) {
				if ((idx + 1 < 4) && channel.type.fix) {
					enum toAdd = [2, 1, 0, 0];
					enum masks = [0x7FC, 0x7FE, 0x7FF, 0x7FF];
					channel.freq = (channel.freq + toAdd[soundInfo.reg.resolution]) & masks[soundInfo.reg.resolution];
				}

				if (idx + 1 != 4) {
					*nrx3ptr = cast(ubyte)channel.freq;
				} else {
					*nrx3ptr = cast(ubyte)((*nrx3ptr & 0x08) | channel.freq);
				}
				channel.n4 = cast(ubyte)((channel.n4 & 0xC0) + (channel.freq >> 8));
				*nrx4ptr = cast(byte)(channel.n4 & mask);
			}

			/* 4. apply envelope & volume to HW registers */
			if (channel.cgbVolumeChange) {
				soundInfo.reg.NR51 = (soundInfo.reg.NR51 & ~channel.panMask) | channel.pan;
				if (idx + 1 == 3) {
					*nrx2ptr = gCgb3Vol[channel.envelopeVolume];
					if (channel.n4 & 0x80) {
						*nrx0ptr = 0x80;
						*nrx4ptr = channel.n4;
						channel.n4 &= 0x7f;
					}
				} else {
					envelopeStepTimeAndDir &= 0xf;
					*nrx2ptr = cast(ubyte)((channel.envelopeVolume << 4) + envelopeStepTimeAndDir);
					*nrx4ptr = channel.n4 | 0x80;
					if (idx + 1 == 1 && !(*nrx0ptr & 0x08)) {
						*nrx4ptr = channel.n4 | 0x80;
					}
				}
				gb.set_envelope(cast(ubyte)idx, *nrx2ptr);
				gb.toggle_length(cast(ubyte)idx, (*nrx4ptr & 0x40));
				gb.trigger_note(cast(ubyte)idx);
			}
		}
	}
	///
	void m4aMPlayTempoControl(ushort tempo) @safe pure {
		tempoScale = tempo;
		tempoInterval = cast(ushort)((tempoRawBPM * tempoScale) >> 8);
	}
	///
	void m4aMPlayVolumeControl(ushort trackBits, ushort volume) @safe pure {
		uint bit = 1;

		foreach (ref track; tracks) {
			if (trackBits & bit) {
				if (track.exists) {
					track.volPublic = cast(ubyte)(volume / 4);
					track.volumeSet = true;
					track.unknown2 = true;
				}
			}

			bit <<= 1;
		}
	}

	///
	void m4aMPlayPitchControl(ushort trackBits, short pitch) @safe pure {
		uint bit = 1;

		foreach (ref track; tracks) {
			if (trackBits & bit) {
				if (track.exists) {
					track.keyShiftPublic = pitch >> 8;
					track.pitchPublic = cast(ubyte)pitch;
					track.pitchSet = true;
					track.unknown8 = true;
				}
			}

			bit <<= 1;
		}
	}

	///
	void m4aMPlayPanpotControl(ushort trackBits, byte pan) @safe pure {
		uint bit = 1;

		foreach (ref track; tracks) {
			if (trackBits & bit) {
				if (track.exists) {
					track.panPublic = pan;
					track.volumeSet = true;
					track.unknown2 = true;
				}
			}

			bit <<= 1;
		}
	}
	///
	void m4aMPlayModDepthSet(ushort trackBits, ubyte modDepth) @safe pure {
		uint bit = 1;

		foreach (ref track; tracks) {
			if (trackBits & bit) {
				if (track.exists) {
					track.modDepth = modDepth;

					if (!track.modDepth) {
						ClearModM(track);
					}
				}
			}

			bit <<= 1;
		}
	}

	///
	void m4aMPlayLFOSpeedSet(ushort trackBits, ubyte lfoSpeed) @safe pure {
		uint bit = 1;

		foreach (ref track; tracks) {
			if (trackBits & bit) {
				if (track.exists) {
					track.lfoSpeed = lfoSpeed;

					if (!track.lfoSpeed) {
						ClearModM(track);
					}
				}
			}

			bit <<= 1;
		}
	}

}

///
ushort getOrigSampleRate(ubyte rate) @safe pure {
	return gPcmSamplesPerVBlankTable[rate];
}

///
uint MidiKeyToFreq(ref Wave wav, ubyte key, ubyte fineAdjust) @safe pure {
	uint val1;
	uint val2;
	uint fineAdjustShifted = fineAdjust << 24;

	if (key > 178) {
		key = 178;
		fineAdjustShifted = 255 << 24;
	}

	val1 = gScaleTable[key];
	val1 = gFreqTable[val1 & 0xF] >> (val1 >> 4);

	val2 = gScaleTable[key + 1];
	val2 = gFreqTable[val2 & 0xF] >> (val2 >> 4);

	return umul3232H32(wav.header.freq, val1 + umul3232H32(val2 - val1, fineAdjustShifted));
}

///
void MP2K_event_nothing(ref M4APlayer, ref MusicPlayerTrack) @safe pure {
	assert(0);
}

///
void m4aSoundMode(SoundMixerState* soundInfo, SoundMode mode) @safe pure {
	if (mode.reverbVolume || mode.reverbEnabled) {
		soundInfo.reverb = mode.reverbVolume;
	}

	if (mode.maxChannels) {
		soundInfo.numChans = mode.maxChannels;

		foreach (i; 0 .. soundInfo.numChans) {
			soundInfo.chans[i].clearStatusFlags();
		}
	}

	if (mode.masterVolume) {
		soundInfo.masterVol = mode.masterVolume;
	}

	if (mode.biasEnable || mode.bias) {
		soundInfo.reg.resolution = mode.bias;
	}

	//if (mode.frequency) {
	//	SampleFreqSet(mode.frequency);
	//}
}


///
void TrkVolPitSet(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	if (track.volumeSet) {
		int x = (track.vol * track.volPublic) >> 5;

		if (track.modType == 1) {
			x = (x * (track.modCalculated + 128)) >> 7;
		}

		int y = 2 * track.pan + track.panPublic;

		if (track.modType == 2) {
			y += track.modCalculated;
		}

		y = clamp(y, -128, 127);

		track.volRightCalculated = cast(ubyte)(((y + 128) * x) >> 8);
		track.volLeftCalculated = cast(ubyte)(((127 - y) * x) >> 8);
	}

	if (track.pitchSet) {
		int bend = track.bend * track.bendRange;
		int x = (track.tune + bend)
			 * 4
			 + (track.keyShift << 8)
			 + (track.keyShiftPublic << 8)
			 + track.pitchPublic;

		if (track.modType == 0) {
			x += 16 * track.modCalculated;
		}

		track.keyShiftCalculated = cast(ubyte)(x >> 8);
		track.pitchCalculated = cast(ubyte)(x);
	}
	track.pitchSet = false;
	track.volumeSet = false;
}

///
uint cgbCalcFreqFunc(CGBType chanNum, ubyte key, ubyte fineAdjust) @safe pure {
	if (chanNum == CGBType.noise) {
		if (key <= 20) {
			key = 0;
		} else {
			key -= 21;
			if (key > 59) {
				key = 59;
			}
		}

		return gNoiseTable[key];
	} else {
		int val1;
		int val2;

		if (key <= 35) {
			fineAdjust = 0;
			key = 0;
		} else {
			key -= 36;
			if (key > 130) {
				key = 130;
				fineAdjust = 255;
			}
		}

		val1 = gCgbScaleTable[key];
		val1 = gCgbFreqTable[val1 & 0xF] >> (val1 >> 4);

		val2 = gCgbScaleTable[key + 1];
		val2 = gCgbFreqTable[val2 & 0xF] >> (val2 >> 4);

		return val1 + ((fineAdjust * (val2 - val1)) >> 8) + 2048;
	}
}

///
void ClearModM(ref MusicPlayerTrack track) @safe pure {
	track.lfoSpeedCounter = 0;
	track.modCalculated = 0;

	if (track.modType == 0) {
		track.pitchSet = true;
		track.unknown8 = true;
	} else {
		track.volumeSet = true;
		track.unknown2 = true;
	}
}

///
void ply_memacc(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure {
	ubyte op = track.cmdPtr[0];
	auto addr = &player.memAccArea[track.cmdPtr[1]];
	ubyte data = track.cmdPtr[2];
	track.cmdPtr = track.cmdPtr[3 .. $];

	static immutable void function(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure[] gotoConditional = [
		(player, track) { gMPlayJumpTable[1](player, track); },
		(player, track) { track.cmdPtr = track.cmdPtr[4 .. $]; },
	];

	switch (op) {
		case 0: *addr = data; break;
		case 1: *addr += data; break;
		case 2: *addr -= data; break;
		case 3: *addr = player.memAccArea[data]; break;
		case 4: *addr += player.memAccArea[data]; break;
		case 5: *addr -= player.memAccArea[data]; break;
		case 6: gotoConditional[*addr == data](player, track); break;
		case 7: gotoConditional[*addr != data](player, track); break;
		case 8: gotoConditional[*addr > data](player, track); break;
		case 9: gotoConditional[*addr >= data](player, track); break;
		case 10: gotoConditional[*addr <= data](player, track); break;
		case 11: gotoConditional[*addr < data](player, track); break;
		case 12: gotoConditional[*addr == player.memAccArea[data]](player, track); break;
		case 13: gotoConditional[*addr != player.memAccArea[data]](player, track); break;
		case 14: gotoConditional[*addr > player.memAccArea[data]](player, track); break;
		case 15: gotoConditional[*addr >= player.memAccArea[data]](player, track); break;
		case 16: gotoConditional[*addr <= player.memAccArea[data]](player, track); break;
		case 17: gotoConditional[*addr < player.memAccArea[data]](player, track); break;
		default: break;
	}
}

///
void ply_xcmd(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure {
	uint n = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];

	gXcmdTable[n](player, track);
}

///
void ply_xxx(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure {
	gMPlayJumpTable[0](player, track);
}

///
void READ_XCMD_BYTE(ref MusicPlayerTrack track, ref uint var, size_t n) @safe pure {
	uint b = track.cmdPtr[(n)];
	b <<= n * 8;
	var &= ~(0xFF << (n * 8));
	var |= b;
}

///
void ply_xwave(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	uint wav;

	READ_XCMD_BYTE(track, wav, 0); // UB: uninitialized variable
	READ_XCMD_BYTE(track, wav, 1);
	READ_XCMD_BYTE(track, wav, 2);
	READ_XCMD_BYTE(track, wav, 3);

	track.instrument.wav = wav;
	track.cmdPtr = track.cmdPtr[4 .. $];
}

///
void ply_xtype(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.instrument.type = ToneType(track.cmdPtr[0]);
	track.cmdPtr = track.cmdPtr[1 .. $];
}

///
void ply_xatta(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.instrument.attack = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

///
void ply_xdeca(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.instrument.decay = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

///
void ply_xsust(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.instrument.sustain = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

///
void ply_xrele(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.instrument.release = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

///
void ply_xiecv(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.echoVolume = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

///
void ply_xiecl(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.echoLength = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

///
void ply_xleng(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.instrument.length = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

///
void ply_xswee(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.instrument.panSweep = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

///
void ply_xcmd_0C(ref M4APlayer, ref MusicPlayerTrack track) @trusted pure {
	uint unk;

	READ_XCMD_BYTE(track, unk, 0); // UB: uninitialized variable
	READ_XCMD_BYTE(track, unk, 1);

	if (track.unk_3A < cast(ushort)unk) {
		track.unk_3A++;
		track.cmdPtr = (track.cmdPtr.ptr - 2)[0 .. track.cmdPtr.length + 2];
		track.wait = 1;
	} else {
		track.unk_3A = 0;
		track.cmdPtr = track.cmdPtr[2 .. $];
	}
}

///
void ply_xcmd_0D(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	uint unk;

	READ_XCMD_BYTE(track, unk, 0); // UB: uninitialized variable
	READ_XCMD_BYTE(track, unk, 1);
	READ_XCMD_BYTE(track, unk, 2);
	READ_XCMD_BYTE(track, unk, 3);

	track.count = unk;
	track.cmdPtr = track.cmdPtr[4 .. $];
}
