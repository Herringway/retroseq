module m4a.m4a;

import m4a.cgb_audio;
import m4a.internal;
import m4a.m4a_tables;
import m4a.music_player;
import m4a.sound_mixer;


struct M4APlayer {
	const(ubyte)[] musicData;
	uint songTableOffset;

	SoundMixerState soundInfo;
	MPlayFunc[36] gMPlayJumpTable;
	SoundChannel[4] cgbChans;
	MusicPlayerInfo gMPlayInfo_BGM;
	MusicPlayerInfo gMPlayInfo_SE1;
	MusicPlayerInfo gMPlayInfo_SE2;
	MusicPlayerInfo gMPlayInfo_SE3;
	MusicPlayerTrack[MAX_MUSICPLAYER_TRACKS] gMPlayTrack_BGM;
	MusicPlayerTrack[3] gMPlayTrack_SE1;
	MusicPlayerTrack[9] gMPlayTrack_SE2;
	MusicPlayerTrack[1] gMPlayTrack_SE3;
	ubyte[0x10] gMPlayMemAccArea;

	AudioCGB gb;
	float playerCounter = 0;
	void initialize(uint freq, const(ubyte)[] _music, uint _songTableAddress, uint _mode) @safe pure {
		musicData = _music;
		songTableOffset = _songTableAddress;
		int i;

		SoundInit();
		soundInfo.freq = cast(ubyte)(((_mode >> 16) & 0xF) - 1);
		SampleFreqSet(&soundInfo, freq);
		MPlayExtender();
		m4aSoundMode(&soundInfo, _mode);

		MusicPlayerInfo *mplayInfo = &gMPlayInfo_BGM;
		MPlayOpen(mplayInfo, gMPlayTrack_BGM[], MAX_MUSICPLAYER_TRACKS);
		mplayInfo.checkSongPriority = 0;
		mplayInfo.memAccArea = gMPlayMemAccArea[];
		gb.initialize(freq);
	}
	void MPlayExtender() @safe pure {
		soundInfo.reg.NR50 = 0; // set master volume to zero
		soundInfo.reg.NR51 = 0; // set master volume to zero
		soundInfo.reg.NR52 = SOUND_MASTER_ENABLE | SOUND_4_ON | SOUND_3_ON | SOUND_2_ON | SOUND_1_ON;
		soundInfo.reg.NR12 = 0x8;
		soundInfo.reg.NR22 = 0x8;
		soundInfo.reg.NR42 = 0x8;
		soundInfo.reg.NR14 = 0x80;
		soundInfo.reg.NR24 = 0x80;
		soundInfo.reg.NR44 = 0x80;
		soundInfo.reg.NR30 = 0;
		soundInfo.reg.NR50 = 0x77;


		for (ubyte i = 0; i < 4; i++) {
			gb.set_envelope(i, 8);
			gb.trigger_note(i);
		}

		gMPlayJumpTable[8] = &ply_memacc;
		gMPlayJumpTable[17] = &MP2K_event_lfos;
		gMPlayJumpTable[19] = &MP2K_event_mod;
		gMPlayJumpTable[28] = &ply_xcmd;
		gMPlayJumpTable[29] = &MP2K_event_endtie;
		gMPlayJumpTable[30] = &MP2K_event_nothing;
		gMPlayJumpTable[31] = &TrackStop;
		gMPlayJumpTable[32] = &Funcify!FadeOutBody;
		gMPlayJumpTable[33] = &TrkVolPitSet;

		soundInfo.cgbChans = cgbChans[];
		soundInfo.cgbMixerFunc = &Funcify!cgbMixerFunc;
		soundInfo.cgbNoteOffFunc = &Funcify!cgbNoteOffFunc;
		soundInfo.cgbCalcFreqFunc = &cgbCalcFreqFunc;
		soundInfo.maxScanlines = MAX_LINES;

		//CpuFill32(0, cgbChans, SoundChannel.sizeof * 4);

		cgbChans[0].type = 1;
		cgbChans[0].panMask = 0x11;
		cgbChans[1].type = 2;
		cgbChans[1].panMask = 0x22;
		cgbChans[2].type = 3;
		cgbChans[2].panMask = 0x44;
		cgbChans[3].type = 4;
		cgbChans[3].panMask = 0x88;
	}
	const(Song)[] songTable() @safe pure {
		return sliceMax!Song(musicData, songTableOffset);
	}
	void songNumStart(ushort n) @system {
		gMPlayInfo_BGM.playing = n;
		MPlayStart(gMPlayInfo_BGM, songTable[n].header.toAbsoluteArray(musicData)[0]);
	}

	void MPlayContinue(ref MusicPlayerInfo mplayInfo) @safe pure {
		mplayInfo.status &= ~MUSICPLAYER_STATUS_PAUSE;
	}

	void MPlayFadeOut(MusicPlayerInfo *mplayInfo, ushort speed) @safe pure {
		mplayInfo.fadeCounter = speed;
		mplayInfo.fadeInterval = speed;
		mplayInfo.fadeVolume = (64 << FADE_VOL_SHIFT);
	}



	void m4aSongNumStartOrChange(ushort n) @system {
		const(Song) *song = &songTable[n];

		if (gMPlayInfo_BGM.playing != n) {
			gMPlayInfo_BGM.playing = n;
			MPlayStart(gMPlayInfo_BGM, song.header.toAbsoluteArray(musicData)[0]);
		} else {
			if ((gMPlayInfo_BGM.status & MUSICPLAYER_STATUS_TRACK) == 0
			 || (gMPlayInfo_BGM.status & MUSICPLAYER_STATUS_PAUSE)) {
				MPlayStart(gMPlayInfo_BGM, song.header.toAbsoluteArray(musicData)[0]);
			}
		}
	}

	void m4aSongNumStartOrContinue(ushort n) {
		const(Song) *song = &songTable[n];

		if (gMPlayInfo_BGM.playing != n) {
			gMPlayInfo_BGM.playing = n;
			MPlayStart(gMPlayInfo_BGM, song.header.toAbsoluteArray(musicData)[0]);
		} else if ((gMPlayInfo_BGM.status & MUSICPLAYER_STATUS_TRACK) == 0) {
			gMPlayInfo_BGM.playing = n;
			MPlayStart(gMPlayInfo_BGM, song.header.toAbsoluteArray(musicData)[0]);
		} else if (gMPlayInfo_BGM.status & MUSICPLAYER_STATUS_PAUSE) {
			MPlayContinue(gMPlayInfo_BGM);
		}
	}

	void m4aSongNumStop(ushort n) {
		const(Song) *song = &songTable[n];

		if (gMPlayInfo_BGM.playing == n) {
			m4aMPlayStop(gMPlayInfo_BGM);
		}
	}

	void m4aSongNumContinue(ushort n) {
		const(Song)* song = &songTable[n];

		if (gMPlayInfo_BGM.playing == n) {
			MPlayContinue(gMPlayInfo_BGM);
		}
	}

	void m4aMPlayAllStop() {
		int i;

		m4aMPlayStop(gMPlayInfo_BGM);
	}

	void m4aMPlayContinue(MusicPlayerInfo *mplayInfo) {
		MPlayContinue(*mplayInfo);
	}

	void m4aMPlayAllContinue() {
		int i;

		MPlayContinue(gMPlayInfo_BGM);
	}

	void m4aMPlayFadeOut(MusicPlayerInfo *mplayInfo, ushort speed) {
		MPlayFadeOut(mplayInfo, speed);
	}

	void m4aMPlayFadeOutTemporarily(MusicPlayerInfo *mplayInfo, ushort speed) {
		mplayInfo.fadeCounter = speed;
		mplayInfo.fadeInterval = speed;
		mplayInfo.fadeVolume = (64 << FADE_VOL_SHIFT) | TEMPORARY_FADE;
	}

	void m4aMPlayFadeIn(MusicPlayerInfo *mplayInfo, ushort speed) {
		mplayInfo.fadeCounter = speed;
		mplayInfo.fadeInterval = speed;
		mplayInfo.fadeVolume = (0 << FADE_VOL_SHIFT) | FADE_IN;
		mplayInfo.status &= ~MUSICPLAYER_STATUS_PAUSE;
	}

	void m4aMPlayImmInit(MusicPlayerInfo *mplayInfo) {
		int trackCount = mplayInfo.trackCount;
		MusicPlayerTrack *track = &mplayInfo.tracks[0];

		while (trackCount > 0) {
			if (track.flags & MPT_FLG_EXIST) {
				if (track.flags & MPT_FLG_START) {
					track.flags = MPT_FLG_EXIST;
					track.bendRange = 2;
					track.volPublic = 64;
					track.lfoSpeed = 22;
					track.instrument.type = 1;
				}
			}

			trackCount--;
			track++;
		}
	}




	void ClearChain(ref SoundChannel x) @system pure {
		MP2KClearChain(x);
	}

	void SoundInit() @safe pure {
		soundInfo.reg.NR52 = SOUND_MASTER_ENABLE | SOUND_4_ON | SOUND_3_ON | SOUND_2_ON | SOUND_1_ON;
		soundInfo.reg.SOUNDCNT_H = SOUND_B_FIFO_RESET | SOUND_B_TIMER_0 | SOUND_B_LEFT_OUTPUT | SOUND_A_FIFO_RESET | SOUND_A_TIMER_0 | SOUND_A_RIGHT_OUTPUT | SOUND_ALL_MIX_FULL;
		soundInfo.reg.SOUNDBIAS_H = (soundInfo.reg.SOUNDBIAS_H & 0x3F) | 0x40;

		soundInfo.numChans = 8;
		soundInfo.masterVol = 15;
		soundInfo.mp2kEventNxxFunc = &MP2K_event_nxx;
		soundInfo.cgbMixerFunc = &DummyFunc;
		soundInfo.cgbNoteOffFunc = &DummyFunc2;
		soundInfo.cgbCalcFreqFunc = &DummyFunc3;
		soundInfo.ExtVolPit = &DummyFunc4;

		MPlayJumpTableCopy(gMPlayJumpTable);

		soundInfo.mp2kEventFuncTable = gMPlayJumpTable;
	}
	void SoundClear() @system {
		int i = MAX_DIRECTSOUND_CHANNELS;
		SoundChannel* chan = &soundInfo.chans[0];

		while (i > 0) {
			chan.statusFlags = 0;
			i--;
			chan++;
		}

		chan = &soundInfo.cgbChans[0];

		if (chan) {
			i = 1;

			while (i <= 4) {
				soundInfo.cgbNoteOffFunc(this, cast(ubyte)i);
				chan.statusFlags = 0;
				i++;
				chan++;
			}
		}
	}

	void MPlayOpen(ref MusicPlayerInfo* mplayInfo, MusicPlayerTrack[] tracks, ubyte trackCount) @safe pure {
		if (trackCount == 0) {
			return;
		}

		if (trackCount > MAX_MUSICPLAYER_TRACKS) {
			trackCount = MAX_MUSICPLAYER_TRACKS;
		}

		mplayInfo.tracks = tracks;
		mplayInfo.trackCount = trackCount;
		mplayInfo.status = MUSICPLAYER_STATUS_PAUSE;

		while (trackCount != 0) {
			tracks[0].flags = 0;
			trackCount--;
			tracks = tracks[1 .. $];
		}

		// append music player and MPlayMain to linked list

		if (soundInfo.firstPlayerFunc != null) {
			mplayInfo.nextPlayerFunc = soundInfo.firstPlayerFunc;
			mplayInfo.nextPlayer = soundInfo.firstPlayer;
		}

		soundInfo.firstPlayer = mplayInfo;
		soundInfo.firstPlayerFunc = &MP2KPlayerMain;
	}

	void MPlayStart(ref MusicPlayerInfo mplayInfo, const ref SongHeader songHeader) @system {
		int i;
		ubyte checkSongPriority;
		MusicPlayerTrack *track;
		if (!songHeader.instrument.isValid) {
			return;
		}

		checkSongPriority = mplayInfo.checkSongPriority;

		if (!checkSongPriority
			|| (((mplayInfo.playing == uint.max) || !(mplayInfo.tracks[0].flags & MPT_FLG_START))
				&& ((mplayInfo.status & MUSICPLAYER_STATUS_TRACK) == 0
					|| (mplayInfo.status & MUSICPLAYER_STATUS_PAUSE)))
			|| (mplayInfo.priority <= songHeader.priority)) {
			mplayInfo.status = 0;
			mplayInfo.songHeader = songHeader;
			mplayInfo.voicegroup = songHeader.instrument.toAbsoluteArray(musicData);
			mplayInfo.priority = songHeader.priority;
			mplayInfo.clock = 0;
			mplayInfo.tempoRawBPM = 150;
			mplayInfo.tempoInterval = 150;
			mplayInfo.tempoScale = 0x100;
			mplayInfo.tempoCounter = 0;
			mplayInfo.fadeInterval = 0;

			i = 0;
			track = &mplayInfo.tracks[0];

			while (i < songHeader.trackCount && i < mplayInfo.trackCount) {
				TrackStop(this, mplayInfo, *track);
				track.flags = MPT_FLG_EXIST | MPT_FLG_START;
				track.chan = null;
				track.cmdPtr = songHeader.part.ptr[i].toAbsoluteArray(musicData);
				i++;
				track++;
			}

			while (i < mplayInfo.trackCount) {
				TrackStop(this, mplayInfo, *track);
				track.flags = 0;
				i++;
				track++;
			}

			if (songHeader.reverb & SOUND_MODE_REVERB_SET) {
				m4aSoundMode(&soundInfo, songHeader.reverb);
			}
		}
	}

	void m4aMPlayStop(ref MusicPlayerInfo mplayInfo) {
		int i;
		MusicPlayerTrack *track;

		mplayInfo.status |= MUSICPLAYER_STATUS_PAUSE;

		i = mplayInfo.trackCount;
		track = &mplayInfo.tracks[0];

		while (i > 0) {
			TrackStop(this, mplayInfo, *track);
			i--;
			track++;
		}
	}

	void FadeOutBody(ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack) @system pure {
		return FadeOutBody(mplayInfo);
	}
	void FadeOutBody(ref MusicPlayerInfo mplayInfo) @system pure {
		int i;
		MusicPlayerTrack *track;
		ushort fadeVolume;

		if (mplayInfo.fadeInterval == 0) {
			return;
		}
		if (--mplayInfo.fadeCounter != 0) {
			return;
		}

		mplayInfo.fadeCounter = mplayInfo.fadeInterval;

		if (mplayInfo.fadeVolume & FADE_IN) {
			if ((ushort)(mplayInfo.fadeVolume += (4 << FADE_VOL_SHIFT)) >= (64 << FADE_VOL_SHIFT)) {
				mplayInfo.fadeVolume = (64 << FADE_VOL_SHIFT);
				mplayInfo.fadeInterval = 0;
			}
		} else {
			if ((short)(mplayInfo.fadeVolume -= (4 << FADE_VOL_SHIFT)) <= 0) {
				i = mplayInfo.trackCount;
				track = &mplayInfo.tracks[0];

				while (i > 0) {
					uint val;

					TrackStop(this, mplayInfo, *track);

					val = TEMPORARY_FADE;
					fadeVolume = mplayInfo.fadeVolume;
					val &= fadeVolume;

					if (!val) {
						track.flags = 0;
					}

					i--;
					track++;
				}

				if (mplayInfo.fadeVolume & TEMPORARY_FADE) {
					mplayInfo.status |= MUSICPLAYER_STATUS_PAUSE;
				} else {
					mplayInfo.status = MUSICPLAYER_STATUS_PAUSE;
				}

				mplayInfo.fadeInterval = 0;
				return;
			}
		}

		i = mplayInfo.trackCount;
		track = &mplayInfo.tracks[0];

		while (i > 0) {
			if (track.flags & MPT_FLG_EXIST) {
				fadeVolume = mplayInfo.fadeVolume;

				track.volPublic = cast(ubyte)(fadeVolume >> FADE_VOL_SHIFT);
				track.flags |= MPT_FLG_VOLCHG;
			}

			i--;
			track++;
		}
	}
	void cgbNoteOffFunc(ubyte chanNum) @safe pure {
		switch (chanNum) {
			case 1:
				soundInfo.reg.NR12 = 8;
				soundInfo.reg.NR14 = 0x80;
				break;
			case 2:
				soundInfo.reg.NR22 = 8;
				soundInfo.reg.NR24 = 0x80;
				break;
			case 3:
				soundInfo.reg.NR30 = 0;
				break;
			default:
				soundInfo.reg.NR42 = 8;
				soundInfo.reg.NR44 = 0x80;
		}

		gb.set_envelope(cast(ubyte)(chanNum - 1), 8);
		gb.trigger_note(cast(ubyte)(chanNum - 1));

	}

	private int CgbPan(SoundChannel *chan) pure {
		uint rightVolume = chan.rightVolume;
		uint leftVolume = chan.leftVolume;

		if ((rightVolume = cast(ubyte)rightVolume) >= (leftVolume = cast(ubyte)leftVolume)) {
			if (rightVolume / 2 >= leftVolume) {
				chan.pan = 0x0F;
				return 1;
			}
		}
		else {
			if (leftVolume / 2 >= rightVolume) {
				chan.pan = 0xF0;
				return 1;
			}
		}

		return 0;
	}

	void CgbModVol(SoundChannel *chan) pure {
		if ((soundInfo.mode & 1) || !CgbPan(chan)) {
			chan.pan = 0xFF;
			chan.envelopeGoal = (uint)(chan.rightVolume + chan.leftVolume) >> 4;
		} else {
			// Force chan.rightVolume and chan.leftVolume to be read from memory again,
			// even though there is no reason to do so.
			// The command line option "-fno-gcse" achieves the same result as this.

			chan.envelopeGoal = (uint)(chan.rightVolume + chan.leftVolume) >> 4;
			if (chan.envelopeGoal > 15) {
				chan.envelopeGoal = 15;
			}
		}

		chan.sustainGoal = cast(ubyte)((chan.envelopeGoal * chan.sustain + 15) >> 4);
		chan.pan &= chan.panMask;
	}

	void cgbMixerFunc() pure {
		int ch;
		SoundChannel *channels;
		int envelopeStepTimeAndDir;
		int prevC15;
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

		for (ch = 1, channels = &soundInfo.cgbChans[0]; ch <= 4; ch++, channels++) {
			int envelopeVolume, sustainGoal;
			if (!(channels.statusFlags & SOUND_CHANNEL_SF_ON)) {
				continue;
			}

			/* 1. determine hardware channel registers */
			switch (ch) {
				case 1:
					nrx0ptr = &soundInfo.reg.NR10;
					nrx1ptr = &soundInfo.reg.NR11;
					nrx2ptr = &soundInfo.reg.NR12;
					nrx3ptr = &soundInfo.reg.NR13;
					nrx4ptr = &soundInfo.reg.NR14;
					break;
				case 2:
					nrx0ptr = &soundInfo.reg.NR10x;
					nrx1ptr = &soundInfo.reg.NR21;
					nrx2ptr = &soundInfo.reg.NR22;
					nrx3ptr = &soundInfo.reg.NR23;
					nrx4ptr = &soundInfo.reg.NR24;
					break;
				case 3:
					nrx0ptr = &soundInfo.reg.NR30;
					nrx1ptr = &soundInfo.reg.NR31;
					nrx2ptr = &soundInfo.reg.NR32;
					nrx3ptr = &soundInfo.reg.NR33;
					nrx4ptr = &soundInfo.reg.NR34;
					break;
				default:
					nrx0ptr = &soundInfo.reg.NR30x;
					nrx1ptr = &soundInfo.reg.NR41;
					nrx2ptr = &soundInfo.reg.NR42;
					nrx3ptr = &soundInfo.reg.NR43;
					nrx4ptr = &soundInfo.reg.NR44;
					break;
			}

			prevC15 = soundInfo.cgbCounter15;
			envelopeStepTimeAndDir = *nrx2ptr;

			/* 2. calculate envelope volume */
			if (channels.statusFlags & SOUND_CHANNEL_SF_START) {
				if (!(channels.statusFlags & SOUND_CHANNEL_SF_STOP)) {
					channels.statusFlags = SOUND_CHANNEL_SF_ENV_ATTACK;
					channels.cgbStatus = CGB_CHANNEL_MO_PIT | CGB_CHANNEL_MO_VOL;
					CgbModVol(channels);
					switch (ch) {
						case 1:
							*nrx0ptr = channels.sweep;
							gb.set_sweep(channels.sweep);

							goto case;
						case 2:
							*nrx1ptr = cast(ubyte)((channels.squareNoiseConfig << 6) + channels.length);
							goto init_env_step_time_dir;
						case 3:
							if (&channels.gbWav[0] != channels.currentPointer) {
								*nrx0ptr = 0x40;
								channels.currentPointer = &channels.gbWav[0];
								gb.set_wavram(cast(ubyte[])channels.gbWav[]);
							}
							*nrx0ptr = 0;
							*nrx1ptr = channels.length;
							if (channels.length) {
								channels.n4 = 0xC0;
							} else {
								channels.n4 = 0x80;
							}
							break;
						default:
							*nrx1ptr = channels.length;
							*nrx3ptr = cast(ubyte)(channels.squareNoiseConfig << 3);
						init_env_step_time_dir:
							envelopeStepTimeAndDir = channels.attack + CGB_NRx2_ENV_DIR_INC;
							if (channels.length) {
								channels.n4 = 0x40;
							} else {
								channels.n4 = 0x00;
							}
							break;
					}
					gb.set_length(cast(ubyte)(ch - 1), channels.length);
					channels.envelopeCounter = channels.attack;
					if (cast(byte)(channels.attack & mask)) {
						channels.envelopeVolume = 0;
						goto envelope_step_complete;
					} else {
						// skip attack phase if attack is instantaneous (=0)
						goto envelope_decay_start;
					}
				} else {
					goto oscillator_off;
				}
			} else if (channels.statusFlags & SOUND_CHANNEL_SF_IEC) {
				channels.echoLength--;
				if (cast(byte)(channels.echoLength & mask) <= 0) {
				oscillator_off:
					cgbNoteOffFunc(cast(ubyte)ch);
					channels.statusFlags = 0;
					goto channel_complete;
				}
				goto envelope_complete;
			}
			else if ((channels.statusFlags & SOUND_CHANNEL_SF_STOP) && (channels.statusFlags & SOUND_CHANNEL_SF_ENV)) {
				channels.statusFlags &= ~SOUND_CHANNEL_SF_ENV;
				channels.envelopeCounter = channels.release;
				if (cast(byte)(channels.release & mask)) {
					channels.cgbStatus |= CGB_CHANNEL_MO_VOL;
					if (ch != 3) {
						envelopeStepTimeAndDir = channels.release | CGB_NRx2_ENV_DIR_DEC;
					}
					goto envelope_step_complete;
				} else {
					goto envelope_pseudoecho_start;
				}
			}
			else {
			envelope_step_repeat:
				if (channels.envelopeCounter == 0) {
					if (ch == 3) {
						channels.cgbStatus |= CGB_CHANNEL_MO_VOL;
					}

					CgbModVol(channels);
					if ((channels.statusFlags & SOUND_CHANNEL_SF_ENV) == SOUND_CHANNEL_SF_ENV_RELEASE) {
						channels.envelopeVolume--;
						if (cast(byte)(channels.envelopeVolume & mask) <= 0) {
						envelope_pseudoecho_start:
							channels.envelopeVolume = ((channels.envelopeGoal * channels.echoVolume) + 0xFF) >> 8;
							if (channels.envelopeVolume) {
								channels.statusFlags |= SOUND_CHANNEL_SF_IEC;
								channels.cgbStatus |= CGB_CHANNEL_MO_VOL;
								if (ch != 3) {
									envelopeStepTimeAndDir = 0 | CGB_NRx2_ENV_DIR_INC;
								}
								goto envelope_complete;
							} else {
								goto oscillator_off;
							}
						} else {
							channels.envelopeCounter = channels.release;
						}
					} else if ((channels.statusFlags & SOUND_CHANNEL_SF_ENV) == SOUND_CHANNEL_SF_ENV_SUSTAIN) {
					envelope_sustain:
						channels.envelopeVolume = channels.sustainGoal;
						channels.envelopeCounter = 7;
					} else if ((channels.statusFlags & SOUND_CHANNEL_SF_ENV) == SOUND_CHANNEL_SF_ENV_DECAY) {

						channels.envelopeVolume--;
						envelopeVolume = cast(byte)(channels.envelopeVolume & mask);
						sustainGoal = (byte)(channels.sustainGoal);
						if (envelopeVolume <= sustainGoal) {
						envelope_sustain_start:
							if (channels.sustain == 0) {
								channels.statusFlags &= ~SOUND_CHANNEL_SF_ENV;
								goto envelope_pseudoecho_start;
							} else {
								channels.statusFlags--;
								channels.cgbStatus |= CGB_CHANNEL_MO_VOL;
								if (ch != 3) {
									envelopeStepTimeAndDir = 0 | CGB_NRx2_ENV_DIR_INC;
								}
								goto envelope_sustain;
							}
						} else {
							channels.envelopeCounter = channels.decay;
						}
					} else {
						channels.envelopeVolume++;
						if ((ubyte)(channels.envelopeVolume & mask) >= channels.envelopeGoal) {
						envelope_decay_start:
							channels.statusFlags--;
							channels.envelopeCounter = channels.decay;
							if ((ubyte)(channels.envelopeCounter & mask)) {
								channels.cgbStatus |= CGB_CHANNEL_MO_VOL;
								channels.envelopeVolume = channels.envelopeGoal;
								if (ch != 3) {
									envelopeStepTimeAndDir = channels.decay | CGB_NRx2_ENV_DIR_DEC;
								}
							} else {
								goto envelope_sustain_start;
							}
						} else {
							channels.envelopeCounter = channels.attack;
						}
					}
				}
			}

		envelope_step_complete:
			// every 15 frames, envelope calculation has to be done twice
			// to keep up with the hardware envelope rate (1/64 s)
			channels.envelopeCounter--;
			if (prevC15 == 0) {
				prevC15--;
				goto envelope_step_repeat;
			}

		envelope_complete:
			/* 3. apply pitch to HW registers */
			if (channels.cgbStatus & CGB_CHANNEL_MO_PIT) {
				if (ch < 4 && (channels.type & TONEDATA_TYPE_FIX)) {
					int dac_pwm_rate = soundInfo.reg.SOUNDBIAS_H;

					if (dac_pwm_rate < 0x40) { // if PWM rate = 32768 Hz
						channels.freq = (channels.freq + 2) & 0x7fc;
					} else if (dac_pwm_rate < 0x80) { // if PWM rate = 65536 Hz
						channels.freq = (channels.freq + 1) & 0x7fe;
					}
				}

				if (ch != 4) {
					*nrx3ptr = cast(ubyte)channels.freq;
				} else {
					*nrx3ptr = cast(ubyte)((*nrx3ptr & 0x08) | channels.freq);
				}
				channels.n4 = cast(ubyte)((channels.n4 & 0xC0) + (*(cast(ubyte*)(&channels.freq) + 1)));
				*nrx4ptr = cast(byte)(channels.n4 & mask);
			}

			/* 4. apply envelope & volume to HW registers */
			if (channels.cgbStatus & CGB_CHANNEL_MO_VOL) {
				soundInfo.reg.NR51 = (soundInfo.reg.NR51 & ~channels.panMask) | channels.pan;
				if (ch == 3) {
					*nrx2ptr = gCgb3Vol[channels.envelopeVolume];
					if (channels.n4 & 0x80) {
						*nrx0ptr = 0x80;
						*nrx4ptr = channels.n4;
						channels.n4 &= 0x7f;
					}
				} else {
					envelopeStepTimeAndDir &= 0xf;
					*nrx2ptr = cast(ubyte)((channels.envelopeVolume << 4) + envelopeStepTimeAndDir);
					*nrx4ptr = channels.n4 | 0x80;
					if (ch == 1 && !(*nrx0ptr & 0x08)) {
						*nrx4ptr = channels.n4 | 0x80;
					}
				}
				gb.set_envelope(cast(ubyte)(ch - 1), *nrx2ptr);
				gb.toggle_length(cast(ubyte)(ch - 1), (*nrx4ptr & 0x40));
				gb.trigger_note(cast(ubyte)(ch - 1));
			}

		channel_complete:
			channels.cgbStatus = 0;
		}
	}
}

ushort getOrigSampleRate(ubyte rate) @safe pure {
	return gPcmSamplesPerVBlankTable[rate];
}

uint MidiKeyToFreq(const(WaveData)* wav, ubyte key, ubyte fineAdjust) @safe pure {
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

	return umul3232H32(wav.freq, val1 + umul3232H32(val2 - val1, fineAdjustShifted));
}

void MP2K_event_nothing(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack) @safe pure {
	assert(0);
}

void SampleFreqSet(SoundMixerState *soundInfo, uint freq) @safe pure {
	soundInfo.samplesPerFrame = cast(uint)((freq / 60.0f) + 0.5f);

	soundInfo.pcmDmaPeriod = 7;

	soundInfo.samplesPerDma = soundInfo.pcmDmaPeriod * soundInfo.samplesPerFrame;

	soundInfo.sampleRate = cast(int)(60.0f * soundInfo.samplesPerFrame);

	soundInfo.divFreq = 1.0f / soundInfo.sampleRate;

	soundInfo.origFreq = (getOrigSampleRate(soundInfo.freq) * 59.727678571);

	soundInfo.outBuffer = new float[2][](soundInfo.samplesPerDma);
	soundInfo.outBuffer[] = [0, 0];
	soundInfo.cgbBuffer = new float[2][](soundInfo.samplesPerDma);
	soundInfo.cgbBuffer[] = [0,0];
}

void m4aSoundMode(SoundMixerState* soundInfo, uint mode) @safe pure {
	uint temp;

	temp = mode & (SOUND_MODE_REVERB_SET | SOUND_MODE_REVERB_VAL);

	if (temp) {
		soundInfo.reverb = temp & SOUND_MODE_REVERB_VAL;
	}

	temp = mode & SOUND_MODE_MAXCHN;

	if (temp) {
		SoundChannel[] chan = soundInfo.chans[];

		// The following line is a fix, not sure how accurate it's supposed to be?
		soundInfo.numChans = MAX_DIRECTSOUND_CHANNELS;
		// The following line is the old code
		//soundInfo.numChans = temp >> SOUND_MODE_MAXCHN_SHIFT;

		temp = MAX_DIRECTSOUND_CHANNELS;

		while (temp != 0) {
			chan[0].statusFlags = 0;
			temp--;
			chan = chan[1 .. $];
		}
	}

	temp = mode & SOUND_MODE_MASVOL;

	if (temp) {
		soundInfo.masterVol = cast(ubyte)(temp >> SOUND_MODE_MASVOL_SHIFT);
	}

	temp = mode & SOUND_MODE_DA_BIT;

	if (temp) {
		temp = (temp & 0x300000) >> 14;
		soundInfo.reg.SOUNDBIAS_H = cast(ushort)((soundInfo.reg.SOUNDBIAS_H & 0x3F) | temp);
	}

	//temp = mode & SOUND_MODE_FREQ;

	//if (temp)
	//	SampleFreqSet(temp);
}


void TrkVolPitSet(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) @safe pure {
	if (track.flags & MPT_FLG_VOLSET) {
		int x;
		int y;

		x = (uint)(track.vol * track.volPublic) >> 5;

		if (track.modType == 1) {
			x = (uint)(x * (track.modCalculated + 128)) >> 7;
		}

		y = 2 * track.pan + track.panPublic;

		if (track.modType == 2) {
			y += track.modCalculated;
		}

		if (y < -128) {
			y = -128;
		} else if (y > 127) {
			y = 127;
		}

		track.volRightCalculated = cast(ubyte)(((y + 128) * x) >> 8);
		track.volLeftCalculated = cast(ubyte)(((127 - y) * x) >> 8);
	}

	if (track.flags & MPT_FLG_PITSET) {
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

	track.flags &= ~(MPT_FLG_PITSET | MPT_FLG_VOLSET);
}

uint cgbCalcFreqFunc(ubyte chanNum, ubyte key, ubyte fineAdjust) pure {
	if (chanNum == 4) {
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


void m4aMPlayTempoControl(MusicPlayerInfo *mplayInfo, ushort tempo) {
		mplayInfo.tempoScale = tempo;
		mplayInfo.tempoInterval = cast(ushort)((mplayInfo.tempoRawBPM * mplayInfo.tempoScale) >> 8);
}

void m4aMPlayVolumeControl(MusicPlayerInfo *mplayInfo, ushort trackBits, ushort volume) {
	int i;
	uint bit;
	MusicPlayerTrack *track;

	i = mplayInfo.trackCount;
	track = &mplayInfo.tracks[0];
	bit = 1;

	while (i > 0) {
		if (trackBits & bit) {
			if (track.flags & MPT_FLG_EXIST) {
				track.volPublic = cast(ubyte)(volume / 4);
				track.flags |= MPT_FLG_VOLCHG;
			}
		}

		i--;
		track++;
		bit <<= 1;
	}
}

void m4aMPlayPitchControl(MusicPlayerInfo *mplayInfo, ushort trackBits, short pitch) {
	int i;
	uint bit;
	MusicPlayerTrack *track;

	i = mplayInfo.trackCount;
	track = &mplayInfo.tracks[0];
	bit = 1;

	while (i > 0) {
		if (trackBits & bit) {
			if (track.flags & MPT_FLG_EXIST) {
				track.keyShiftPublic = pitch >> 8;
				track.pitchPublic = cast(ubyte)pitch;
				track.flags |= MPT_FLG_PITCHG;
			}
		}

		i--;
		track++;
		bit <<= 1;
	}
}

void m4aMPlayPanpotControl(MusicPlayerInfo *mplayInfo, ushort trackBits, byte pan) {
	int i;
	uint bit;
	MusicPlayerTrack *track;

	i = mplayInfo.trackCount;
	track = &mplayInfo.tracks[0];
	bit = 1;

	while (i > 0) {
		if (trackBits & bit) {
			if (track.flags & MPT_FLG_EXIST) {
				track.panPublic = pan;
				track.flags |= MPT_FLG_VOLCHG;
			}
		}

		i--;
		track++;
		bit <<= 1;
	}
}

void ClearModM(ref MusicPlayerTrack track) @safe pure {
	track.lfoSpeedCounter = 0;
	track.modCalculated = 0;

	if (track.modType == 0) {
		track.flags |= MPT_FLG_PITCHG;
	} else {
		track.flags |= MPT_FLG_VOLCHG;
	}
}

void m4aMPlayModDepthSet(MusicPlayerInfo *mplayInfo, ushort trackBits, ubyte modDepth) {
	int i;
	uint bit;
	MusicPlayerTrack *track;

	i = mplayInfo.trackCount;
	track = &mplayInfo.tracks[0];
	bit = 1;

	while (i > 0) {
		if (trackBits & bit) {
			if (track.flags & MPT_FLG_EXIST) {
				track.modDepth = modDepth;

				if (!track.modDepth) {
					ClearModM(*track);
				}
			}
		}

		i--;
		track++;
		bit <<= 1;
	}
}

void m4aMPlayLFOSpeedSet(MusicPlayerInfo *mplayInfo, ushort trackBits, ubyte lfoSpeed) {
	int i;
	uint bit;
	MusicPlayerTrack *track;

	i = mplayInfo.trackCount;
	track = &mplayInfo.tracks[0];
	bit = 1;

	while (i > 0) {
		if (trackBits & bit) {
			if (track.flags & MPT_FLG_EXIST) {
				track.lfoSpeed = lfoSpeed;

				if (!track.lfoSpeed) {
					ClearModM(*track);
				}
			}
		}

		i--;
		track++;
		bit <<= 1;
	}
}

void ply_memacc(ref M4APlayer player, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	uint op;
	ubyte *addr;
	ubyte data;

	op = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];

	addr = &mplayInfo.memAccArea[track.cmdPtr[0]];
	track.cmdPtr = track.cmdPtr[1 .. $];

	data = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];

	switch (op) {
		case 0:
			*addr = data;
			return;
		case 1:
			*addr += data;
			return;
		case 2:
			*addr -= data;
			return;
		case 3:
			*addr = mplayInfo.memAccArea[data];
			return;
		case 4:
			*addr += mplayInfo.memAccArea[data];
			return;
		case 5:
			*addr -= mplayInfo.memAccArea[data];
			return;
		case 6:
			if (*addr == data) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 7:
			if (*addr != data) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 8:
			if (*addr > data) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 9:
			if (*addr >= data) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 10:
			if (*addr <= data) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 11:
			if (*addr < data) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 12:
			if (*addr == mplayInfo.memAccArea[data]) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 13:
			if (*addr != mplayInfo.memAccArea[data]) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 14:
			if (*addr > mplayInfo.memAccArea[data]) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 15:
			if (*addr >= mplayInfo.memAccArea[data]) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 16:
			if (*addr <= mplayInfo.memAccArea[data]) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		case 17:
			if (*addr < mplayInfo.memAccArea[data]) {
				goto cond_true;
			} else {
				goto cond_false;
			}
			return;
		default:
			return;
	}

cond_true: {
		// *& is required for matching
		player.gMPlayJumpTable[1](player, mplayInfo, track);
		return;
	}

cond_false:
	track.cmdPtr = track.cmdPtr[4 .. $];
}

void ply_xcmd(ref M4APlayer player, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	uint n = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];

	gXcmdTable[n](player, mplayInfo, track);
}

void ply_xxx(ref M4APlayer player, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	player.gMPlayJumpTable[0](player, mplayInfo, track);
}

void READ_XCMD_BYTE(ref MusicPlayerTrack track, ref uint var, size_t n) pure {
	uint b = track.cmdPtr[(n)];
	b <<= n * 8;
	var &= ~(0xFF << (n * 8));
	var |= b;
}

void ply_xwave(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	uint wav;

	READ_XCMD_BYTE(track, wav, 0); // UB: uninitialized variable
	READ_XCMD_BYTE(track, wav, 1);
	READ_XCMD_BYTE(track, wav, 2);
	READ_XCMD_BYTE(track, wav, 3);

	track.instrument.wav = wav;
	track.cmdPtr = track.cmdPtr[4 .. $];
}

void ply_xtype(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	track.instrument.type = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

void ply_xatta(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	track.instrument.attack = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

void ply_xdeca(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	track.instrument.decay = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

void ply_xsust(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	track.instrument.sustain = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

void ply_xrele(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	track.instrument.release = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

void ply_xiecv(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	track.echoVolume = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

void ply_xiecl(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	track.echoLength = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

void ply_xleng(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	track.instrument.length = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

void ply_xswee(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	track.instrument.panSweep = track.cmdPtr[0];
	track.cmdPtr = track.cmdPtr[1 .. $];
}

void ply_xcmd_0C(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
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

void ply_xcmd_0D(ref M4APlayer, ref MusicPlayerInfo mplayInfo, ref MusicPlayerTrack track) pure {
	uint unk;

	READ_XCMD_BYTE(track, unk, 0); // UB: uninitialized variable
	READ_XCMD_BYTE(track, unk, 1);
	READ_XCMD_BYTE(track, unk, 2);
	READ_XCMD_BYTE(track, unk, 3);

	track.count = unk;
	track.cmdPtr = track.cmdPtr[4 .. $];
}

void DummyFunc(ref M4APlayer) @safe pure {
}

void DummyFunc2(ref M4APlayer, ubyte) @safe pure {
}

uint DummyFunc3(ubyte, ubyte, ubyte) @safe pure {
	return 0;
}

void DummyFunc4() @safe pure {
}
