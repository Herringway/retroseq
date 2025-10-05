///
module retroseq.m4a.music_player;

import retroseq.utility;

import retroseq.m4a.mp2k_common;
import retroseq.m4a.internal;
import retroseq.m4a.m4a;
import retroseq.m4a.m4a_tables;

///
uint umul3232H32(uint a, uint b) @safe pure {
	ulong result = a;
	result *= b;
	return result >> 32;
}

///
void SoundMainBTM(ref M4APlayer, ref MusicPlayerTrack) @safe pure {
	//CpuFill32(0, ptr, 0x40);
}

/// Removes chan from the doubly-linked list of channels associated with chan.track.
/// Gonna rename this to like "FreeChannel" or something, similar to VGMS
void MP2KClearChain(ref SoundChannel chan) @safe pure {
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

/// Ends the current track. (Fine as in the Italian musical word, not English)
void MP2K_event_fine(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	for (SoundChannel *chan = track.chan; chan != null; chan = chan.nextChannelPointer) {
		if (chan.statusFlags & 0xC7) {
			chan.statusFlags |= 0x40;
		}
		MP2KClearChain(*chan);
	}
	track.flags = MusicPlayerTrack.Flags.none;
}

/// Sets the track's cmdPtr to the specified address.
void MP2K_event_goto(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure {
	track.cmdPtr = (cast(const(RelativePointer!(ubyte, uint))[])track.cmdPtr[0 .. 4])[0].toAbsoluteArray(player.musicData);
}

/// Sets the track's cmdPtr to the specified address after backing up its current position.
void MP2K_event_patt(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure {
	ubyte level = track.patternLevel;
	if (level < 3) {
		track.patternStack[level] = track.cmdPtr[4 .. $]; // sizeof(ubyte *);
		track.patternLevel++;
		MP2K_event_goto(player, track);
	} else {
		// Stop playing this track, as an indication to the music programmer that they need to quit
		// nesting patterns so darn much.
		MP2K_event_fine(player, track);
	}
}

/// Marks the end of the current pattern, if there is one, by resetting the pattern to the
/// most recently saved value.
void MP2K_event_pend(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	if (track.patternLevel != 0) {
		ubyte index = --track.patternLevel;
		track.cmdPtr = track.patternStack[index];
	}
}

/// Loops back until a REPT event has been reached the specified number of times
void MP2K_event_rept(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure {
	if (track.cmdPtr[0] == 0) {
		// "Repeat 0 times" == loop forever
		track.cmdPtr = track.cmdPtr[1 .. $];
		MP2K_event_goto(player, track);
	} else {
		ubyte repeatCount = ++track.repeatCount;
		if (repeatCount < track.cmdPtr.pop!ubyte) {
			MP2K_event_goto(player, track);
		} else {
			track.repeatCount = 0;
			track.cmdPtr = track.cmdPtr[ubyte.sizeof + uint.sizeof .. $];
		}
	}
}

/// Sets the note priority for new notes in this track.
void MP2K_event_prio(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.priority = track.cmdPtr.pop!ubyte;
}

/// Sets the BPM of all tracks to the specified tempo (in beats per half-minute, because 255 as a max tempo
/// kinda sucks but 510 is plenty).
void MP2K_event_tempo(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure {
	ushort bpm = track.cmdPtr.pop!ubyte;
	bpm *= 2;
	player.tempoRawBPM = bpm;
	player.tempoInterval = cast(ushort)((bpm * player.tempoScale) / 256);
}

///
void MP2K_event_keysh(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.keyShift = track.cmdPtr.pop!ubyte;
	track.flags |= MusicPlayerTrack.Flags.pitchSet;
	track.flags |= MusicPlayerTrack.Flags.unknown8;
}

///
void MP2K_event_voice(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure {
	ubyte voice = track.cmdPtr.pop!ubyte;
	const(ToneData)* instrument = &player.voicegroup[voice];
	track.instrument = *instrument;
}

///
void MP2K_event_vol(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.vol = track.cmdPtr.pop!ubyte;
	track.flags |= MusicPlayerTrack.Flags.volumeSet;
	track.flags |= MusicPlayerTrack.Flags.unknown2;
}

///
void MP2K_event_pan(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.pan = cast(byte)(track.cmdPtr.pop!ubyte - 0x40);
	track.flags |= MusicPlayerTrack.Flags.volumeSet;
	track.flags |= MusicPlayerTrack.Flags.unknown2;
}

///
void MP2K_event_bend(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.bend = cast(byte)(track.cmdPtr.pop!ubyte - 0x40);
	track.flags |= MusicPlayerTrack.Flags.pitchSet;
	track.flags |= MusicPlayerTrack.Flags.unknown8;
}

///
void MP2K_event_bendr(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.bendRange = track.cmdPtr.pop!ubyte;
	track.flags |= MusicPlayerTrack.Flags.pitchSet;
	track.flags |= MusicPlayerTrack.Flags.unknown8;
}

///
void MP2K_event_lfodl(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.lfoDelay = track.cmdPtr.pop!ubyte;
}

///
void MP2K_event_modt(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	ubyte type = track.cmdPtr.pop!ubyte;
	if (type != track.modType) {
		track.modType = type;
		track.flags |= MusicPlayerTrack.Flags.volumeSet;
		track.flags |= MusicPlayerTrack.Flags.unknown2;
		track.flags |= MusicPlayerTrack.Flags.pitchSet;
		track.flags |= MusicPlayerTrack.Flags.unknown8;
	}
}

///
void MP2K_event_tune(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.tune = cast(byte)(track.cmdPtr.pop!ubyte - 0x40);
	track.flags |= MusicPlayerTrack.Flags.pitchSet;
	track.flags |= MusicPlayerTrack.Flags.unknown8;
}

///
void MP2K_event_port(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	// I'm really curious whether any games actually use this event...
	// I assume anything done by this command will get immediately overwritten by cgbMixerFunc?
	track.cmdPtr = track.cmdPtr[2 .. $];
}

///
void MP2KPlayerMain(ref M4APlayer player) @safe pure {
	if (player.paused) {
		return;
	}
	player.FadeOutBody();
	if (player.paused) {
		return;
	}

	player.tempoCounter += player.tempoInterval;
	while (player.tempoCounter >= 150) {
		ushort trackBits = 0;

		trackLoop: foreach (idx, ref currentTrack; player.tracks) {
			if (!currentTrack.flags.exists) {
				continue;
			}
			trackBits |= (1 << idx);

			for (SoundChannel* chan = currentTrack.chan; chan != null; chan = chan.nextChannelPointer) {
				if (!chan.isActive) {
					player.ClearChain(*chan);
				} else if (chan.gateTime != 0 && --chan.gateTime == 0) {
					chan.stop = true;
				}
			}

			if (currentTrack.flags.start) {
				//CpuFill32(0, currentTrack, 0x40);
				currentTrack.flags = MusicPlayerTrack.Flags.exists;
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
					player.soundInfo.mp2kEventNxxFunc(player, event - 0xCF, currentTrack);
				} else if (event >= 0xB1) {
					MPlayFunc eventFunc;
					player.cmd = cast(ubyte)(event - 0xB1);
					eventFunc = gMPlayJumpTable[player.cmd];
					eventFunc(player, currentTrack);

					if (!currentTrack.flags) {
						continue trackLoop;
					}
				} else {
					currentTrack.wait = gClockTable[event - 0x80];
				}
			}

			currentTrack.wait--;

			if (currentTrack.lfoSpeed != 0 && currentTrack.modDepth != 0) {
				if (currentTrack.lfoDelayCounter != 0U) {
					currentTrack.lfoDelayCounter--;
					continue trackLoop;
				}

				currentTrack.lfoSpeedCounter += currentTrack.lfoSpeed;

				byte r;
				if (currentTrack.lfoSpeedCounter >= 0x40U && currentTrack.lfoSpeedCounter < 0xC0U) {
					r = cast(byte)(128 - currentTrack.lfoSpeedCounter);
				} else if (currentTrack.lfoSpeedCounter >= 0xC0U) {
					r = cast(byte)(currentTrack.lfoSpeedCounter - 256);
				} else {
					r = currentTrack.lfoSpeedCounter;
				}
				r = cast(byte)FLOOR_DIV_POW2(currentTrack.modDepth * r, 64);

				if (r != currentTrack.modCalculated) {
					currentTrack.modCalculated = r;
					if (currentTrack.modType == 0) {
						currentTrack.flags |= MusicPlayerTrack.Flags.pitchSet;
						currentTrack.flags |= MusicPlayerTrack.Flags.unknown8;
					} else {
						currentTrack.flags |= MusicPlayerTrack.Flags.volumeSet;
						currentTrack.flags |= MusicPlayerTrack.Flags.unknown2;
					}
				}
			}
		}

		player.clock++;
		player.activeTracks = trackBits;
		if (trackBits == 0) {
			player.paused = true;
			return;
		}
		player.tempoCounter -= 150;
	}

	uint i = 0;

	do {
		MusicPlayerTrack *track = &player.tracks[i];

		if (!track.flags.exists || (!track.flags.volumeSet && !track.flags.unknown2 && !track.flags.pitchSet && !track.flags.unknown8)) {
			continue;
		}
		TrkVolPitSet(player, *track);
		for (SoundChannel *chan = track.chan; chan != null; chan = chan.nextChannelPointer) {
			if ((chan.statusFlags & 0xC7) == 0) {
				player.ClearChain(*chan);
				continue;
			}
			ubyte cgbType = chan.cgbType;
			if (track.flags.volumeSet || track.flags.unknown2) {
				ChnVolSetAsm(*chan, *track);
				if (cgbType != 0) {
					chan.cgbVolumeChange = true;
				}
			}
			if (track.flags.pitchSet || track.flags.unknown8) {
				int key = chan.key + track.keyShiftCalculated;
				if (key < 0) {
					key = 0;
				}
				if (cgbType != 0) {
					chan.freq = player.soundInfo.cgbCalcFreqFunc(cgbType, cast(ubyte)key, track.pitchCalculated);
					chan.cgbPitchChange = true;
				} else {
					chan.freq = MidiKeyToFreq(chan.wav, cast(ubyte)key, track.pitchCalculated);
				}
			}
		}
		track.flags &= cast(MusicPlayerTrack.Flags)~(MusicPlayerTrack.Flags.pitchSet | MusicPlayerTrack.Flags.unknown8 | MusicPlayerTrack.Flags.volumeSet | MusicPlayerTrack.Flags.unknown2);
	}
	while(++i < player.tracks.length);
}

///
void TrackStop(ref M4APlayer player, ref MusicPlayerTrack track) @safe pure {
	if (track.flags.exists) {
		for (SoundChannel *chan = track.chan; chan != null; chan = chan.nextChannelPointer) {
			if (chan.statusFlags != 0) {
				ubyte cgbType = chan.cgbType;
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

///
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

///
void MP2K_event_nxx(ref M4APlayer player, uint clock, ref MusicPlayerTrack track) @trusted pure {
	// A note can be anywhere from 1 to 4 bytes long. First is always the note length...
	track.gateTime = gClockTable[clock];
	if (track.cmdPtr[0] < 0x80) {
		// Then the note name...
		track.key = track.cmdPtr.pop!ubyte;
		if (track.cmdPtr[0] < 0x80) {
			// Then the velocity...
			track.velocity = track.cmdPtr.pop!ubyte;
			if (track.cmdPtr[0] < 0x80) {
				// Then a number to add ticks to get exotic or more precise note lengths without TIE.
				track.gateTime += track.cmdPtr.pop!ubyte;
			}
		}
	}

	// sp14
	byte forcedPan = 0;
	// First r4, then r9
	const(ToneData)* instrument = &track.instrument;
	// sp8
	ubyte key = track.key;
	const oldRhy = instrument.rhy;

	if (instrument.rhy || instrument.spl) {
		ubyte instrumentIndex;
		if (instrument.spl) {
			const keySplitTableOffset = instrument.keySplitTable.toAbsoluteArray(player.musicData);
			instrumentIndex = keySplitTableOffset[track.key];
		} else {
			instrumentIndex = track.key;
		}

		instrument = &instrument.group.toAbsoluteArray(player.musicData)[instrumentIndex];
		if (instrument.rhy || instrument.spl) {
			return;
		}
		if (oldRhy) {
			if (instrument.panSweep & 0x80) {
				forcedPan = ((byte)(instrument.panSweep & 0x7F) - 0x40) * 2;
			}
			key = instrument.drumKey;
		}
	}

	// sp10
	ushort priority = player.priority + track.priority;
	if (priority > 0xFF) {
		priority = 0xFF;
	}

	ubyte cgbType = instrument.cgbType;
	SoundChannel *chan;

	if (cgbType != 0) {
		// There's only one CgbChannel of a given type, so we don't need to loop to find it.
		chan = &player.soundInfo.cgbChans[cgbType - 1];

		// If this channel is running and not stopped,
		if (chan.isActive && !chan.stop) {
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
			if (!currChan.isActive) {
				// Hey, we found a completely inactive channel! Let's use that.
				chan = currChan;
				break;
			}

			if (currChan.stop && !foundStoppingChannel) {
				// In the absence of a completely finalized channel, we can take over one that's about to
				// finalize. That's a tier above any channel that's currently playing a note.
				foundStoppingChannel = 1;
				p = currChan.priority;
				t = currChan.track;
				chan = currChan;
			} else if ((currChan.stop && foundStoppingChannel) || (!currChan.stop && !foundStoppingChannel)) {
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
	TrkVolPitSet(player, track);

	chan.gateTime = track.gateTime;
	chan.midiKey = track.key;
	chan.velocity = track.velocity;
	chan.priority = cast(ubyte)priority;
	chan.key = key;
	chan.rhythmPan = forcedPan;
	chan.type = instrument.type;
	if (cgbType == 0) {
		const header = instrument.wav.toAbsoluteArray(player.musicData);
		const waveData = (cast(const(byte)[])header)[WaveData.sizeof .. WaveData.sizeof + header[0].size];
		chan.wav = Wave(header[0], waveData);
	} else if (cgbType == 3) {
		chan.gbWav = instrument.cgbSample.toAbsoluteArray(player.musicData)[0];
	} else {
		chan.squareNoiseConfig = instrument.squareNoiseConfig;
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

	chan.statusFlags = 0;
	chan.start = true;
	track.flags &= cast(MusicPlayerTrack.Flags)~(MusicPlayerTrack.Flags.pitchSet | MusicPlayerTrack.Flags.unknown8 | MusicPlayerTrack.Flags.volumeSet | MusicPlayerTrack.Flags.unknown2);
}

///
void MP2K_event_endtie(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
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

///
void MP2K_event_lfos(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.lfoSpeed = track.cmdPtr.pop!ubyte;
	if (track.lfoSpeed == 0) {
		ClearModM(track);
	}
}

///
void MP2K_event_mod(ref M4APlayer, ref MusicPlayerTrack track) @safe pure {
	track.modDepth = track.cmdPtr.pop!ubyte;
	if (track.modDepth == 0) {
		ClearModM(track);
	}
}

/**
* Params:
* 	wav = pointer to sample
* 	key = the note after being transposed. If pitch bend puts it between notes, then the note below.
* 	pitch = how many 256ths of a semitone above `key` the current note is.
* Returns: The freq in Hz at which the sample should be played back.
*/
uint MidiKeyToFreq_(const(WaveData) *wav, ubyte key, ubyte pitch) @safe {
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
