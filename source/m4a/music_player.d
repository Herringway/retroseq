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

void SoundMainBTM(MusicPlayerInfo*, MusicPlayerTrack*)
{
    //CpuFill32(0, ptr, 0x40);
}

// Removes chan from the doubly-linked list of channels associated with chan.track.
// Gonna rename this to like "FreeChannel" or something, similar to VGMS
void MP2KClearChain(SoundChannel *chan) {
    MusicPlayerTrack *track = chan.track;
    if (chan.track == null) {
        return;
    }
    SoundChannel *nextChannelPointer = cast(SoundChannel*)chan.nextChannelPointer;
    SoundChannel *prevChannelPointer = cast(SoundChannel*)chan.prevChannelPointer;

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

void VERIFY_PTR(void*) {}

private ubyte SafeDereferenceU8(ubyte *addr) {
    ubyte ret = *addr;
    VERIFY_PTR(addr);
    return ret;
}

private uint SafeDereferenceU32(uint *addr) {
    uint ret = *addr;
    VERIFY_PTR(addr);
    return ret;
}

ubyte ConsumeTrackByte(MusicPlayerTrack *track) {
    ubyte *ptr = track.cmdPtr++;
    return SafeDereferenceU8(ptr);
}

void MPlayJumpTableCopy(MPlayFunc[] mplayJumpTable) @safe {
    mplayJumpTable[] = gMPlayJumpTableTemplate;
}

// Ends the current track. (Fine as in the Italian musical word, not English)
void MP2K_event_fine(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    MusicPlayerTrack *r5 = track;
    for (SoundChannel *chan = track.chan; chan != null; chan = cast(SoundChannel*)chan.nextChannelPointer) {
        if (chan.statusFlags & 0xC7) {
            chan.statusFlags |= 0x40;
        }
        MP2KClearChain(chan);
    }
    track.flags = 0;
}

// Sets the track's cmdPtr to the specified address.
void MP2K_event_goto(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.cmdPtr = offsetPointer!ubyte(*cast(uint *)track.cmdPtr);
}

// Sets the track's cmdPtr to the specified address after backing up its current position.
void MP2K_event_patt(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    ubyte level = track.patternLevel;
    if (level < 3) {
        track.patternStack[level] = track.cmdPtr + 4;  // sizeof(ubyte *);
        track.patternLevel++;
        MP2K_event_goto(unused, track);
    } else {
        // Stop playing this track, as an indication to the music programmer that they need to quit
        // nesting patterns so darn much.
        MP2K_event_fine(unused, track);
    }
}

// Marks the end of the current pattern, if there is one, by resetting the pattern to the
// most recently saved value.
void MP2K_event_pend(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    if (track.patternLevel != 0) {
        ubyte index = --track.patternLevel;
        track.cmdPtr = track.patternStack[index];
    }
}

// Loops back until a REPT event has been reached the specified number of times
void MP2K_event_rept(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    if (*track.cmdPtr == 0) {
        // "Repeat 0 times" == loop forever
        track.cmdPtr++;
        MP2K_event_goto(unused, track);
    } else {
        ubyte repeatCount = ++track.repeatCount;
        if (repeatCount < ConsumeTrackByte(track)) {
            MP2K_event_goto(unused, track);
        } else {
            track.repeatCount = 0;
            track.cmdPtr += ubyte.sizeof + uint.sizeof;
        }
    }
}

// Sets the note priority for new notes in this track.
void MP2K_event_prio(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.priority = ConsumeTrackByte(track);
}

// Sets the BPM of all tracks to the specified tempo (in beats per half-minute, because 255 as a max tempo
// kinda sucks but 510 is plenty).
void MP2K_event_tempo(MusicPlayerInfo *player, MusicPlayerTrack *track) {
    ushort bpm = ConsumeTrackByte(track);
    bpm *= 2;
    player.tempoRawBPM = bpm;
    player.tempoInterval = cast(ushort)((bpm * player.tempoScale) / 256);
}

void MP2K_event_keysh(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.keyShift = ConsumeTrackByte(track);
    track.flags |= 0xC;
}

void MP2K_event_voice(MusicPlayerInfo *player, MusicPlayerTrack *track) {
    ubyte voice = *(track.cmdPtr++);
    ToneData *instrument = &player.voicegroup[voice];
    track.instrument = *instrument;
}

void MP2K_event_vol(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.vol = ConsumeTrackByte(track);
    track.flags |= 0x3;
}

void MP2K_event_pan(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.pan = cast(byte)(ConsumeTrackByte(track) - 0x40);
    track.flags |= 0x3;
}

void MP2K_event_bend(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.bend = cast(byte)(ConsumeTrackByte(track) - 0x40);
    track.flags |= 0xC;
}

void MP2K_event_bendr(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.bendRange = ConsumeTrackByte(track);
    track.flags |= 0xC;
}

void MP2K_event_lfodl(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.lfoDelay = ConsumeTrackByte(track);
}

void MP2K_event_modt(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    ubyte type = ConsumeTrackByte(track);
    if (type != track.modType) {
        track.modType = type;
        track.flags |= 0xF;
    }
}

void MP2K_event_tune(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.tune = cast(byte)(ConsumeTrackByte(track) - 0x40);
    track.flags |= 0xC;
}

void MP2K_event_port(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    // I'm really curious whether any games actually use this event...
    // I assume anything done by this command will get immediately overwritten by cgbMixerFunc?
    track.cmdPtr += 2;
}

void MP2KPlayerMain(void *voidPtrPlayer) {
    MusicPlayerInfo *player = cast(MusicPlayerInfo *)voidPtrPlayer;
    SoundMixerState *mixer = SOUND_INFO_PTR;

    if (player.nextPlayerFunc != null) {
        player.nextPlayerFunc(player.nextPlayer);
    }

    if (player.status & MUSICPLAYER_STATUS_PAUSE) {
        return;
    }
    FadeOutBody(cast(MusicPlayerInfo*)voidPtrPlayer, null);
    if (player.status & MUSICPLAYER_STATUS_PAUSE) {
        return;
    }

    player.tempoCounter += player.tempoInterval;
    while (player.tempoCounter >= 150) {
        ushort trackBits = 0;

        for (uint i = 0; i < player.trackCount; i++) {
            MusicPlayerTrack *currentTrack = player.tracks + i;
            SoundChannel *chan;
            if ((currentTrack.flags & MPT_FLG_EXIST) == 0) {
                continue;
            }
            trackBits |= (1 << i);

            chan = currentTrack.chan;
            while (chan != null) {
                if ((chan.statusFlags & SOUND_CHANNEL_SF_ON) == 0) {
                    ClearChain(chan);
                } else if (chan.gateTime != 0 && --chan.gateTime == 0) {
                    chan.statusFlags |= SOUND_CHANNEL_SF_STOP;
                }
                chan = cast(SoundChannel*)chan.nextChannelPointer;
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
                ubyte event = *currentTrack.cmdPtr;
                if (event < 0x80) {
                    event = currentTrack.runningStatus;
                } else {
                    currentTrack.cmdPtr++;
                    if (event >= 0xBD) {
                        currentTrack.runningStatus = event;
                    }
                }

                if (event >= 0xCF) {
                    mixer.mp2kEventNxxFunc(event - 0xCF, player, currentTrack);
                } else if (event >= 0xB1) {
                    MPlayFunc eventFunc;
                    player.cmd = cast(ubyte)(event - 0xB1);
                    eventFunc = mixer.mp2kEventFuncTable[player.cmd];
                    eventFunc(player, currentTrack);

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

        player.clock++;
        if (trackBits == 0) {
            player.status = MUSICPLAYER_STATUS_PAUSE;
            return;
        }
        player.status = trackBits;
        player.tempoCounter -= 150;
    }

    uint i = 0;

    do {
        MusicPlayerTrack *track = player.tracks + i;

        if ((track.flags & MPT_FLG_EXIST) == 0 || (track.flags & 0xF) == 0) {
            continue;
        }
        TrkVolPitSet(player, track);
        for (SoundChannel *chan = track.chan; chan != null; chan = cast(SoundChannel*)chan.nextChannelPointer) {
            if ((chan.statusFlags & 0xC7) == 0) {
                ClearChain(chan);
                continue;
            }
            ubyte cgbType = chan.type & 0x7;
            if (track.flags & MPT_FLG_VOLCHG) {
                ChnVolSetAsm(chan, track);
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
                    chan.freq = mixer.cgbCalcFreqFunc(cgbType, cast(ubyte)key, track.pitchCalculated);
                    chan.cgbStatus |= 0x2;
                } else {
                    chan.freq = MidiKeyToFreq(chan.wav, cast(ubyte)key, track.pitchCalculated);
                }
            }
        }
        track.flags &= ~0xF;
    }
    while(++i < player.trackCount);
}

void TrackStop(MusicPlayerInfo *player, MusicPlayerTrack *track) {
    if (track.flags & 0x80) {
        for (SoundChannel *chan = track.chan; chan != null; chan = cast(SoundChannel*)chan.nextChannelPointer) {
            if (chan.statusFlags != 0) {
                ubyte cgbType = chan.type & 0x7;
                if (cgbType != 0) {
                    SoundMixerState *mixer = SOUND_INFO_PTR;
                    mixer.cgbNoteOffFunc(cgbType);
                }
                chan.statusFlags = 0;
            }
            chan.track = null;
        }
        track.chan = null;
    }
}

void ChnVolSetAsm(SoundChannel *chan, MusicPlayerTrack *track) {
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

void MP2K_event_nxx(uint clock, MusicPlayerInfo *player, MusicPlayerTrack *track) {
    SoundMixerState *mixer = SOUND_INFO_PTR;

    // A note can be anywhere from 1 to 4 bytes long. First is always the note length...
    track.gateTime = gClockTable[clock];
    if (*track.cmdPtr < 0x80) {
        // Then the note name...
        track.key = *(track.cmdPtr++);
        if (*track.cmdPtr < 0x80) {
            // Then the velocity...
            track.velocity = *(track.cmdPtr++);
            if (*track.cmdPtr < 0x80) {
                // Then a number to add ticks to get exotic or more precise note lengths without TIE.
                track.gateTime += *(track.cmdPtr++);
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
            ubyte *keySplitTableOffset = offsetPointer!ubyte(instrument.keySplitTable);
            instrumentIndex = keySplitTableOffset[track.key];
        } else {
            instrumentIndex = track.key;
        }

        instrument = offsetPointer!ToneData(instrument.group + (instrumentIndex * 12));
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
    ushort priority = player.priority + track.priority;
    if (priority > 0xFF) {
        priority = 0xFF;
    }

    ubyte cgbType = instrument.type & TONEDATA_TYPE_CGB;
    SoundChannel *chan;

    if (cgbType != 0) {
        if (mixer.cgbChans == null) {
            return;
        }
        // There's only one CgbChannel of a given type, so we don't need to loop to find it.
        chan = cast(SoundChannel*)(mixer.cgbChans + cgbType - 1);

        // If this channel is running and not stopped,
        if ((chan.statusFlags & SOUND_CHANNEL_SF_ON)
        && (chan.statusFlags & SOUND_CHANNEL_SF_STOP) == 0) {
            // then make sure this note is higher priority (or same priority but from a later track).
            if (chan.priority > priority || (chan.priority == priority && chan.track < track)) {
                return;
            }
        }
    } else {
        ushort p = priority;
        MusicPlayerTrack *t = track;
        uint foundStoppingChannel = 0;
        chan = null;
        ubyte maxChans = mixer.numChans;
        SoundChannel *currChan = &mixer.chans[0];

        for (ubyte i = 0; i < maxChans; i++, currChan++) {
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
    ClearChain(chan);

    chan.prevChannelPointer = null;
    chan.nextChannelPointer = track.chan;
    if (track.chan != null) {
        track.chan.prevChannelPointer = chan;
    }
    track.chan = chan;
    chan.track = track;

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
        chan.wav = offsetPointer!WaveData(instrument.wav);
    } else {
        //chan.wav = cast(WaveData*)instrument.cgbSample;
    }
    chan.attack = instrument.attack;
    chan.decay = instrument.decay;
    chan.sustain = instrument.sustain;
    chan.release = instrument.release;
    chan.echoVolume = track.echoVolume;
    chan.echoLength = track.echoLength;
    ChnVolSetAsm(chan, track);

    // Avoid promoting keyShiftCalculated to ubyte by splitting the addition into a separate statement
    short transposedKey = chan.key;
    transposedKey += track.keyShiftCalculated;
    if (transposedKey < 0) {
        transposedKey = 0;
    }

    if (cgbType != 0) {
        //CgbChannel *cgbChan = (CgbChannel *)chan;
        chan.length = instrument.length;
        if (instrument.panSweep & 0x80 || (instrument.panSweep & 0x70) == 0) {
            chan.sweep = 8;
        } else {
            chan.sweep = instrument.panSweep;
        }

        chan.freq = mixer.cgbCalcFreqFunc(cgbType, cast(ubyte)transposedKey, track.pitchCalculated);
    } else {
        chan.count = track.count;
        chan.freq = MidiKeyToFreq(chan.wav, cast(ubyte)transposedKey, track.pitchCalculated);
    }

    chan.statusFlags = SOUND_CHANNEL_SF_START;
    track.flags &= ~0xF;
}

void MP2K_event_endtie(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    ubyte key = *track.cmdPtr;
    if (key < 0x80) {
        track.key = key;
        track.cmdPtr++;
    } else {
        key = track.key;
    }

    SoundChannel *chan = track.chan;
    while (chan != null) {
        if (chan.statusFlags & 0x83 && (chan.statusFlags & 0x40) == 0 && chan.midiKey == key) {
            chan.statusFlags |= 0x40;
            return;
        }
        chan = cast(SoundChannel*)chan.nextChannelPointer;
    }
}

void MP2K_event_lfos(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.lfoSpeed = *(track.cmdPtr++);
    if (track.lfoSpeed == 0) {
        ClearModM(track);
    }
}

void MP2K_event_mod(MusicPlayerInfo *unused, MusicPlayerTrack *track) {
    track.modDepth = *(track.cmdPtr++);
    if (track.modDepth == 0) {
        ClearModM(track);
    }
}

void m4aSoundVSync()
{

}

// In:
// - wav: pointer to sample
// - key: the note after being transposed. If pitch bend puts it between notes, then the note below.
// - pitch: how many 256ths of a semitone above `key` the current note is.
// Out:
// - The freq in Hz at which the sample should be played back.

uint MidiKeyToFreq_(WaveData *wav, ubyte key, ubyte pitch) {
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
    uint freq = SafeDereferenceU32(&wav.freq);
    return umul3232H32(freq, baseFreq1 + freqDifference);
}
