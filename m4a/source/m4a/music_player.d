module m4a.music_player;

import m4a.mp2k_common;
import m4a.internal;
import m4a.m4a;
import m4a.m4a_tables;

uint umul3232H32(uint a, uint b) @safe pure {
	ulong result = a;
	result *= b;
	return result >> 32;
}

void SoundMainBTM(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack) @safe pure {
	//CpuFill32(0, ptr, 0x40);
}

// Removes chan from the doubly-linked list of channels associated with chan.track.
// Gonna rename this to like "FreeChannel" or something, similar to VGMS
void MP2KClearChain(ref SoundChannel chan) @system pure {
	MusicPlayerTrack *track = chan.track;
	if (chan.track == null) {
		return;
	}
	SoundChannel *nextChannelPointer = chan.nextChannelPointer;
	SoundChannel *prevChannelPointer = chan.prevChannelPointer;

	if (prevChannelPointer != null) {
		prevChannelPointer.nextChannelPointer = nextChannelPointer;
	} else {
		track.chan = nextChannelPointer;
	}

	if (nextChannelPointer != null) {
		nextChannelPointer.prevChannelPointer = prevChannelPointer;
	}

	chan.track = null;
}

ubyte ConsumeTrackByte(ref MusicPlayerTrack track) @safe pure {
	scope(exit) track.cmdPtr = track.cmdPtr[1 .. $];
	return track.cmdPtr[0];
}

void MPlayJumpTableCopy(MPlayFunc[] mplayJumpTable) @safe pure {
	mplayJumpTable[] = gMPlayJumpTableTemplate;
}

// Ends the current track. (Fine as in the Italian musical word, not English)
void MP2K_event_fine(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @system pure {
	for (SoundChannel *chan = track.chan; chan != null; chan = chan.nextChannelPointer) {
		if (chan.statusFlags & 0xC7) {
			chan.statusFlags |= 0x40;
		}
		MP2KClearChain(*chan);
	}
	track.flags = 0;
}

// Sets the track's cmdPtr to the specified address.
void MP2K_event_goto(ref M4APlayer player, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.cmdPtr = (cast(const(RelativePointer!(ubyte, uint))[])track.cmdPtr[0 .. 4])[0].toAbsoluteArray(player.musicData);
}

// Sets the track's cmdPtr to the specified address after backing up its current position.
void MP2K_event_patt(ref M4APlayer player, ref MusicPlayerInfo subPlayer, ref MusicPlayerTrack track) @system pure {
	ubyte level = track.patternLevel;
	if (level < 3) {
		track.patternStack[level] = track.cmdPtr[4 .. $]; // sizeof(ubyte *);
		track.patternLevel++;
		MP2K_event_goto(player, subPlayer, track);
	} else {
		// Stop playing this track, as an indication to the music programmer that they need to quit
		// nesting patterns so darn much.
		MP2K_event_fine(player, subPlayer, track);
	}
}

// Marks the end of the current pattern, if there is one, by resetting the pattern to the
// most recently saved value.
void MP2K_event_pend(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	if (track.patternLevel != 0) {
		ubyte index = --track.patternLevel;
		track.cmdPtr = track.patternStack[index];
	}
}

// Loops back until a REPT event has been reached the specified number of times
void MP2K_event_rept(ref M4APlayer player, ref MusicPlayerInfo subPlayer, ref MusicPlayerTrack track) @safe pure {
	if (track.cmdPtr[0] == 0) {
		// "Repeat 0 times" == loop forever
		track.cmdPtr = track.cmdPtr[1 .. $];
		MP2K_event_goto(player, subPlayer, track);
	} else {
		ubyte repeatCount = ++track.repeatCount;
		if (repeatCount < ConsumeTrackByte(track)) {
			MP2K_event_goto(player, subPlayer, track);
		} else {
			track.repeatCount = 0;
			track.cmdPtr = track.cmdPtr[ubyte.sizeof + uint.sizeof .. $];
		}
	}
}

// Sets the note priority for new notes in this track.
void MP2K_event_prio(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.priority = ConsumeTrackByte(track);
}

// Sets the BPM of all tracks to the specified tempo (in beats per half-minute, because 255 as a max tempo
// kinda sucks but 510 is plenty).
void MP2K_event_tempo(ref M4APlayer, ref MusicPlayerInfo player, ref MusicPlayerTrack track) @safe pure {
	ushort bpm = ConsumeTrackByte(track);
	bpm *= 2;
	player.tempoRawBPM = bpm;
	player.tempoInterval = cast(ushort)((bpm * player.tempoScale) / 256);
}

void MP2K_event_keysh(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.keyShift = ConsumeTrackByte(track);
	track.flags |= 0xC;
}

void MP2K_event_voice(ref M4APlayer, ref MusicPlayerInfo player, ref MusicPlayerTrack track) @safe pure {
	ubyte voice = ConsumeTrackByte(track);
	const(ToneData)* instrument = &player.voicegroup[voice];
	track.instrument = *instrument;
}

void MP2K_event_vol(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.vol = ConsumeTrackByte(track);
	track.flags |= 0x3;
}

void MP2K_event_pan(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.pan = cast(byte)(ConsumeTrackByte(track) - 0x40);
	track.flags |= 0x3;
}

void MP2K_event_bend(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.bend = cast(byte)(ConsumeTrackByte(track) - 0x40);
	track.flags |= 0xC;
}

void MP2K_event_bendr(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.bendRange = ConsumeTrackByte(track);
	track.flags |= 0xC;
}

void MP2K_event_lfodl(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.lfoDelay = ConsumeTrackByte(track);
}

void MP2K_event_modt(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	ubyte type = ConsumeTrackByte(track);
	if (type != track.modType) {
		track.modType = type;
		track.flags |= 0xF;
	}
}

void MP2K_event_tune(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.tune = cast(byte)(ConsumeTrackByte(track) - 0x40);
	track.flags |= 0xC;
}

void MP2K_event_port(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	// I'm really curious whether any games actually use this event...
	// I assume anything done by this command will get immediately overwritten by cgbMixerFunc?
	track.cmdPtr = track.cmdPtr[2 .. $];
}

void MP2KPlayerMain(ref M4APlayer player, ref MusicPlayerInfo subPlayer) @system pure {
	if (subPlayer.nextPlayerFunc != null) {
		subPlayer.nextPlayerFunc(player, *subPlayer.nextPlayer);
	}

	if (subPlayer.status & MUSICPLAYER_STATUS_PAUSE) {
		return;
	}
	player.FadeOutBody(subPlayer);
	if (subPlayer.status & MUSICPLAYER_STATUS_PAUSE) {
		return;
	}

	subPlayer.tempoCounter += subPlayer.tempoInterval;
	while (subPlayer.tempoCounter >= 150) {
		ushort trackBits = 0;

		for (uint i = 0; i < subPlayer.trackCount; i++) {
			MusicPlayerTrack *currentTrack = &subPlayer.tracks[i];
			SoundChannel *chan;
			if ((currentTrack.flags & MPT_FLG_EXIST) == 0) {
				continue;
			}
			trackBits |= (1 << i);

			chan = currentTrack.chan;
			while (chan != null) {
				if ((chan.statusFlags & SOUND_CHANNEL_SF_ON) == 0) {
					player.ClearChain(*chan);
				} else if (chan.gateTime != 0 && --chan.gateTime == 0) {
					chan.statusFlags |= SOUND_CHANNEL_SF_STOP;
				}
				chan = chan.nextChannelPointer;
			}

			if (currentTrack.flags & MPT_FLG_START) {
				//CpuFill32(0, currentTrack, 0x40);
				currentTrack.flags = MPT_FLG_EXIST;
				currentTrack.bendRange = 2;
				currentTrack.volPublic = 64;
				currentTrack.lfoSpeed = 22;
				currentTrack.instrument.type = 1;
			}

			while (currentTrack.wait == 0) {
				ubyte event = currentTrack.cmdPtr[0];
				if (event < 0x80) {
					event = currentTrack.runningStatus;
				} else {
					currentTrack.cmdPtr = currentTrack.cmdPtr[1 .. $];
					if (event >= 0xBD) {
						currentTrack.runningStatus = event;
					}
				}

				if (event >= 0xCF) {
					player.soundInfo.mp2kEventNxxFunc(player, event - 0xCF, subPlayer, *currentTrack);
				} else if (event >= 0xB1) {
					MPlayFunc eventFunc;
					subPlayer.cmd = cast(ubyte)(event - 0xB1);
					eventFunc = player.soundInfo.mp2kEventFuncTable[subPlayer.cmd];
					eventFunc(player, subPlayer, *currentTrack);

					if (currentTrack.flags == 0) {
						goto nextTrack;
					}
				} else {
					currentTrack.wait = gClockTable[event - 0x80];
				}
			}

			currentTrack.wait--;

			if (currentTrack.lfoSpeed != 0 && currentTrack.modDepth != 0) {
				if (currentTrack.lfoDelayCounter != 0U) {
					currentTrack.lfoDelayCounter--;
					goto nextTrack;
				}

				currentTrack.lfoSpeedCounter += currentTrack.lfoSpeed;

				byte r;
				if (currentTrack.lfoSpeedCounter >= 0x40U && currentTrack.lfoSpeedCounter < 0xC0U) {
					r = cast(byte)(128 - currentTrack.lfoSpeedCounter);
				} else if (currentTrack.lfoSpeedCounter >= 0xC0U) {
					// Unsigned . signed casts where the value is out of range are implementation defined.
					// Why not add a few extra lines to make behavior the same for literally everyone?
					r = cast(byte)(currentTrack.lfoSpeedCounter - 256);
				} else {
					r = currentTrack.lfoSpeedCounter;
				}
				r = cast(byte)FLOOR_DIV_POW2(currentTrack.modDepth * r, 64);

				if (r != currentTrack.modCalculated) {
					currentTrack.modCalculated = r;
					if (currentTrack.modType == 0) {
						currentTrack.flags |= MPT_FLG_PITCHG;
					} else {
						currentTrack.flags |= MPT_FLG_VOLCHG;
					}
				}
			}

			nextTrack:;
		}

		subPlayer.clock++;
		if (trackBits == 0) {
			subPlayer.status = MUSICPLAYER_STATUS_PAUSE;
			return;
		}
		subPlayer.status = trackBits;
		subPlayer.tempoCounter -= 150;
	}

	uint i = 0;

	do {
		MusicPlayerTrack *track = &subPlayer.tracks[i];

		if ((track.flags & MPT_FLG_EXIST) == 0 || (track.flags & 0xF) == 0) {
			continue;
		}
		TrkVolPitSet(player, subPlayer, *track);
		for (SoundChannel *chan = track.chan; chan != null; chan = chan.nextChannelPointer) {
			if ((chan.statusFlags & 0xC7) == 0) {
				player.ClearChain(*chan);
				continue;
			}
			ubyte cgbType = chan.type & 0x7;
			if (track.flags & MPT_FLG_VOLCHG) {
				ChnVolSetAsm(*chan, *track);
				if (cgbType != 0) {
					chan.cgbStatus |= 1;
				}
			}
			if (track.flags & MPT_FLG_PITCHG) {
				int key = chan.key + track.keyShiftCalculated;
				if (key < 0) {
					key = 0;
				}
				if (cgbType != 0) {
					chan.freq = player.soundInfo.cgbCalcFreqFunc(cgbType, cast(ubyte)key, track.pitchCalculated);
					chan.cgbStatus |= 0x2;
				} else {
					chan.freq = MidiKeyToFreq(chan.wav, cast(ubyte)key, track.pitchCalculated);
				}
			}
		}
		track.flags &= ~0xF;
	}
	while(++i < subPlayer.trackCount);
}

void TrackStop(ref M4APlayer player, ref MusicPlayerInfo subPlayer, ref MusicPlayerTrack track) @safe pure {
	if (track.flags & 0x80) {
		for (SoundChannel *chan = track.chan; chan != null; chan = chan.nextChannelPointer) {
			if (chan.statusFlags != 0) {
				ubyte cgbType = chan.type & 0x7;
				if (cgbType != 0) {
					player.soundInfo.cgbNoteOffFunc(player, cgbType);
				}
				chan.statusFlags = 0;
			}
			chan.track = null;
		}
		track.chan = null;
	}
}

void ChnVolSetAsm(ref SoundChannel chan, ref MusicPlayerTrack track) @safe pure {
	byte forcedPan = chan.rhythmPan;
	uint rightVolume = (ubyte)(forcedPan + 128) * chan.velocity * track.volRightCalculated / 128 / 128;
	if (rightVolume > 0xFF) {
		rightVolume = 0xFF;
	}
	chan.rightVolume = cast(ubyte)rightVolume;

	uint leftVolume = (ubyte)(127 - forcedPan) * chan.velocity * track.volLeftCalculated / 128 / 128;
	if (leftVolume > 0xFF) {
		leftVolume = 0xFF;
	}
	chan.leftVolume = cast(ubyte)leftVolume;
}

void MP2K_event_nxx(ref M4APlayer player, uint clock, ref MusicPlayerInfo subPlayer, ref MusicPlayerTrack track) @system pure {
	// A note can be anywhere from 1 to 4 bytes long. First is always the note length...
	track.gateTime = gClockTable[clock];
	if (track.cmdPtr[0] < 0x80) {
		// Then the note name...
		track.key = ConsumeTrackByte(track);
		if (track.cmdPtr[0] < 0x80) {
			// Then the velocity...
			track.velocity = ConsumeTrackByte(track);
			if (track.cmdPtr[0] < 0x80) {
				// Then a number to add ticks to get exotic or more precise note lengths without TIE.
				track.gateTime += ConsumeTrackByte(track);
			}
		}
	}

	// sp14
	byte forcedPan = 0;
	// First r4, then r9
	ToneData *instrument = &track.instrument;
	// sp8
	ubyte key = track.key;
	ubyte type = instrument.type;

	if (type & (TONEDATA_TYPE_RHY | TONEDATA_TYPE_SPL)) {
		ubyte instrumentIndex;
		if (instrument.type & TONEDATA_TYPE_SPL) {
			ubyte[] keySplitTableOffset = instrument.keySplitTable.toAbsoluteArray(player.musicData);
			instrumentIndex = keySplitTableOffset[track.key];
		} else {
			instrumentIndex = track.key;
		}

		instrument = &instrument.group.toAbsoluteArray(player.musicData)[instrumentIndex];
		if (instrument.type & (TONEDATA_TYPE_RHY | TONEDATA_TYPE_SPL)) {
			return;
		}
		if (type & TONEDATA_TYPE_RHY) {
			if (instrument.panSweep & 0x80) {
				forcedPan = ((byte)(instrument.panSweep & 0x7F) - 0x40) * 2;
			}
			key = instrument.drumKey;
		}
	}

	// sp10
	ushort priority = subPlayer.priority + track.priority;
	if (priority > 0xFF) {
		priority = 0xFF;
	}

	ubyte cgbType = instrument.type & TONEDATA_TYPE_CGB;
	SoundChannel *chan;

	if (cgbType != 0) {
		if (player.soundInfo.cgbChans == null) {
			return;
		}
		// There's only one CgbChannel of a given type, so we don't need to loop to find it.
		chan = &player.soundInfo.cgbChans[cgbType - 1];

		// If this channel is running and not stopped,
		if ((chan.statusFlags & SOUND_CHANNEL_SF_ON)
		&& (chan.statusFlags & SOUND_CHANNEL_SF_STOP) == 0) {
			// then make sure this note is higher priority (or same priority but from a later track).
			if (chan.priority > priority || (chan.priority == priority && chan.track < &track)) {
				return;
			}
		}
	} else {
		ushort p = priority;
		MusicPlayerTrack *t = &track;
		uint foundStoppingChannel = 0;
		ubyte maxChans = player.soundInfo.numChans;

		for (ubyte i = 0; i < maxChans; i++) {
			SoundChannel *currChan = &player.soundInfo.chans[i];
			if ((currChan.statusFlags & SOUND_CHANNEL_SF_ON) == 0) {
				// Hey, we found a completely inactive channel! Let's use that.
				chan = currChan;
				break;
			}

			if (currChan.statusFlags & SOUND_CHANNEL_SF_STOP && !foundStoppingChannel) {
				// In the absence of a completely finalized channel, we can take over one that's about to
				// finalize. That's a tier above any channel that's currently playing a note.
				foundStoppingChannel = 1;
				p = currChan.priority;
				t = currChan.track;
				chan = currChan;
			} else if ((currChan.statusFlags & SOUND_CHANNEL_SF_STOP && foundStoppingChannel)
				 || ((currChan.statusFlags & SOUND_CHANNEL_SF_STOP) == 0 && !foundStoppingChannel)) {
				// The channel we're checking is on the same tier, so check the priority and track order
				if (currChan.priority < p) {
					p = currChan.priority;
					t = currChan.track;
					chan = currChan;
				} else if (currChan.priority == p && currChan.track > t) {
					t = currChan.track;
					chan = currChan;
				} else if (currChan.priority == p && currChan.track == t) {
					chan = currChan;
				}
			}
		}

	}

	if (chan == null) {
		return;
	}
	player.ClearChain(*chan);

	chan.prevChannelPointer = null;
	chan.nextChannelPointer = track.chan;
	if (track.chan != null) {
		track.chan.prevChannelPointer = chan;
	}
	track.chan = chan;
	chan.track = &track;

	track.lfoDelayCounter = track.lfoDelay;
	if (track.lfoDelay != 0) {
		ClearModM(track);
	}
	TrkVolPitSet(player, subPlayer, track);

	chan.gateTime = track.gateTime;
	chan.midiKey = track.key;
	chan.velocity = track.velocity;
	chan.priority = cast(ubyte)priority;
	chan.key = key;
	chan.rhythmPan = forcedPan;
	chan.type = instrument.type;
	if (cgbType == 0) {
		chan.wav = instrument.wav.toAbsolute(player.musicData);
	} else {
		//chan.wav = cast(WaveData*)instrument.cgbSample;
	}
	chan.attack = instrument.attack;
	chan.decay = instrument.decay;
	chan.sustain = instrument.sustain;
	chan.release = instrument.release;
	chan.echoVolume = track.echoVolume;
	chan.echoLength = track.echoLength;
	ChnVolSetAsm(*chan, track);

	// Avoid promoting keyShiftCalculated to ubyte by splitting the addition into a separate statement
	short transposedKey = chan.key;
	transposedKey += track.keyShiftCalculated;
	if (transposedKey < 0) {
		transposedKey = 0;
	}

	if (cgbType != 0) {
		chan.length = instrument.length;
		if (instrument.panSweep & 0x80 || (instrument.panSweep & 0x70) == 0) {
			chan.sweep = 8;
		} else {
			chan.sweep = instrument.panSweep;
		}

		chan.freq = player.soundInfo.cgbCalcFreqFunc(cgbType, cast(ubyte)transposedKey, track.pitchCalculated);
	} else {
		chan.count = track.count;
		chan.freq = MidiKeyToFreq(chan.wav, cast(ubyte)transposedKey, track.pitchCalculated);
	}

	chan.statusFlags = SOUND_CHANNEL_SF_START;
	track.flags &= ~0xF;
}

void MP2K_event_endtie(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @system pure {
	ubyte key = track.cmdPtr[0];
	if (key < 0x80) {
		track.key = key;
		track.cmdPtr = track.cmdPtr[1 .. $];
	} else {
		key = track.key;
	}

	SoundChannel *chan = track.chan;
	while (chan != null) {
		if (chan.statusFlags & 0x83 && (chan.statusFlags & 0x40) == 0 && chan.midiKey == key) {
			chan.statusFlags |= 0x40;
			return;
		}
		chan = chan.nextChannelPointer;
	}
}

void MP2K_event_lfos(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.lfoSpeed = ConsumeTrackByte(track);
	if (track.lfoSpeed == 0) {
		ClearModM(track);
	}
}

void MP2K_event_mod(ref M4APlayer, ref MusicPlayerInfo, ref MusicPlayerTrack track) @safe pure {
	track.modDepth = ConsumeTrackByte(track);
	if (track.modDepth == 0) {
		ClearModM(track);
	}
}

// In:
// - wav: pointer to sample
// - key: the note after being transposed. If pitch bend puts it between notes, then the note below.
// - pitch: how many 256ths of a semitone above `key` the current note is.
// Out:
// - The freq in Hz at which the sample should be played back.

uint MidiKeyToFreq_(WaveData *wav, ubyte key, ubyte pitch) @safe {
	if (key > 178) {
		key = 178;
		pitch = 255;
	}

	// Alternatively, note = key % 12 and octave = 14 - (key / 12)
	ubyte note = gScaleTable[key] & 0xF;
	ubyte octave = gScaleTable[key] >> 4;
	ubyte nextNote = gScaleTable[key + 1] & 0xF;
	ubyte nextOctave = gScaleTable[key + 1] >> 4;

	uint baseFreq1 = gFreqTable[note] >> octave;
	uint baseFreq2 = gFreqTable[nextNote] >> nextOctave;

	uint freqDifference = umul3232H32(baseFreq2 - baseFreq1, pitch << 24);
	// This is added by me. The real GBA and GBA BIOS don't verify this address, and as a result the
	// BIOS's memory can be dumped.
	uint freq = wav.freq;
	return umul3232H32(freq, baseFreq1 + freqDifference);
}
