///
module retroseq.m4a.cgb_audio;

import retroseq.m4a.cgb_tables;
import retroseq.m4a.internal;

///
struct AudioCGB {
	ubyte ch1SweepCounter; ///
	ubyte ch1SweepCounterI; ///
	ubyte ch1SweepDir; ///
	ubyte ch1SweepShift; ///
	ubyte[4] Vol; ///
	ubyte[4] VolI; ///
	ubyte[4] Len; ///
	ubyte[4] LenI; ///
	ubyte[4] LenOn; ///
	ubyte[4] EnvCounter; ///
	ubyte[4] EnvCounterI; ///
	ubyte[4] EnvDir; ///
	ubyte[4] DAC; ///
	float[32] WAVRAM = 0; ///
	static immutable ushort[2] lfsrMax = [0x8000, 0x80]; ///
	ushort [2] ch4LFSR = lfsrMax; ///

	float[4] soundChannelPos = [0, 1, 0, 0]; ///
	uint apuFrame; ///
	uint sampleRate; ///
	float ch4Samples = 0; ///
	ubyte apuCycle; ///
	///
	void initialize(uint rate) @safe pure {
		this = this.init;
		sampleRate = rate;
	}
	///
	void set_sweep(ubyte sweep) @safe pure {
		ch1SweepDir = (sweep & 0x08) >> 3;
		ch1SweepCounter = ch1SweepCounterI = (sweep & 0x70) >> 4;
		ch1SweepShift = (sweep & 0x07);
	}
	///
	void set_wavram(ubyte[] wavePointer) @safe pure {
		for (ubyte wavi = 0; wavi < 0x10; wavi++) {
			WAVRAM[(wavi << 1)] = ((wavePointer[wavi] & 0xF0) >> 4) / 7.5f - 1.0f;
			WAVRAM[(wavi << 1) + 1] = ((wavePointer[wavi] & 0x0F)) / 7.5f - 1.0f;
		}
	}
	///
	void toggle_length(ubyte channel, ubyte state) @safe pure {
		LenOn[channel] = state;
	}
	///
	void set_length(ubyte channel, ubyte length) @safe pure {
		Len[channel] = LenI[channel] = length;
	}
	///
	void set_envelope(ubyte channel, ubyte envelope) @safe pure {
		static immutable ubyte[] volTableNR32 = [0, 4, 2, 1, 3, 3, 3, 3];
		if (channel == 2) {
			Vol[2] = VolI[2] = volTableNR32[envelope >> 5];
		} else {
			DAC[channel] = (envelope & 0xF8) > 0;
			Vol[channel] = VolI[channel] = (envelope & 0xF0) >> 4;
			EnvDir[channel] = (envelope & 0x08) >> 3;
			EnvCounter[channel] = EnvCounterI[channel] = (envelope & 0x07);
		}
	}
	///
	void trigger_note(ubyte channel) @safe pure {
		Vol[channel] = VolI[channel];
		Len[channel] = LenI[channel];
		if (channel != 2) {
			EnvCounter[channel] = EnvCounterI[channel];
		}
		if (channel == 3) {
			ch4LFSR[] = lfsrMax;
		}
	}
	///
	void audio_generate(ref SoundMixerState mixer, float[2][] outBuffer) @safe pure {
		const PU1Table = pulseWaveTables[mixer.reg.NR11 >> 6];
		const PU2Table = pulseWaveTables[mixer.reg.NR21 >> 6];
		foreach (ref samples; outBuffer) {
			apuFrame += 512;
			if (apuFrame >= sampleRate) {
				apuFrame -= sampleRate;
				apuCycle++;

				// Length
				if ((apuCycle & 1) == 0) {
					for (ubyte ch = 0; ch < 4; ch++) {
						if (Len[ch]) {
							if (--Len[ch] == 0 && LenOn[ch]) {
								mixer.reg.enabledChannels[ch] = false;
							}
						}
					}
				}

				// Envelope
				if ((apuCycle & 7) == 7) {
					for (ubyte ch = 0; ch < 4; ch++) {
						if (ch == 2) {
							continue; // Skip wave channel
						}
						if (EnvCounter[ch]) {
							if (--EnvCounter[ch] == 0) {
								if (Vol[ch] && !EnvDir[ch]) {
									Vol[ch]--;
									EnvCounter[ch] = EnvCounterI[ch];
								} else if (Vol[ch] < 0x0F && EnvDir[ch]) {
									Vol[ch]++;
									EnvCounter[ch] = EnvCounterI[ch];
								}
							}
						}
					}
				}

				// Sweep
				if ((apuCycle & 3) == 2) {
					if (ch1SweepCounterI && ch1SweepShift) {
						if (--ch1SweepCounter == 0) {
							ushort ch1Freq = mixer.reg.sound1CntX.frequency;
							if (ch1SweepDir) {
								ch1Freq -= ch1Freq >> ch1SweepShift;
								if (ch1Freq & 0xF800) {
									ch1Freq = 0;
								}
							} else {
								ch1Freq += ch1Freq >> ch1SweepShift;
								if (ch1Freq & 0xF800) {
									ch1Freq = 0;
									EnvCounter[0] = 0;
									Vol[0] = 0;
								}
							}
							mixer.reg.sound1CntX.frequency = ch1Freq & 0x7FF;
							ch1SweepCounter = ch1SweepCounterI;
						}
					}
				}
			}
			//Sound generation loop
			soundChannelPos[0] += freqTable[mixer.reg.sound1CntX.frequency] / (sampleRate / 16);
			soundChannelPos[1] += freqTable[mixer.reg.sound2CntH.frequency] / (sampleRate / 16);
			soundChannelPos[2] += freqTable[mixer.reg.sound3CntX.frequency] / (sampleRate / 16);
			soundChannelPos[0] %= 32;
			soundChannelPos[1] %= 32;
			soundChannelPos[2] %= 32;
			samples[] = 0.0;
			if (mixer.reg.enableAPU) {
				if ((DAC[0]) && mixer.reg.enabledChannels[0]) {
					if (mixer.reg.panCh1Left) {
						samples[0] += Vol[0] * PU1Table[cast(int)(soundChannelPos[0])] / 15.0f;
					}
					if (mixer.reg.panCh1Right) {
						samples[1] += Vol[0] * PU1Table[cast(int)(soundChannelPos[0])] / 15.0f;
					}
				}
				if ((DAC[1]) && mixer.reg.enabledChannels[1]) {
					if(mixer.reg.panCh2Left) {
						samples[0] += Vol[1] * PU2Table[cast(int)(soundChannelPos[1])] / 15.0f;
					}
					if(mixer.reg.panCh2Right) {
						samples[1] += Vol[1] * PU2Table[cast(int)(soundChannelPos[1])] / 15.0f;
					}
				}
				if (mixer.reg.channel3DACEnable && mixer.reg.enabledChannels[2]) {
					if(mixer.reg.panCh3Left) {
						samples[0] += Vol[2] * WAVRAM[cast(int)(soundChannelPos[2])] / 4.0f;
					}
					if(mixer.reg.panCh3Right) {
						samples[1] += Vol[2] * WAVRAM[cast(int)(soundChannelPos[2])] / 4.0f;
					}
				}
				if (DAC[3] && mixer.reg.enabledChannels[3]) {
					uint lfsrMode = mixer.reg.thinnerLFSR;
					ch4Samples += freqTableNoise[mixer.reg.NR43] / sampleRate;
					int ch4Out = [-1, 1][ch4LFSR[lfsrMode] & 1];
					float avgDiv = 1.0f;
					while (ch4Samples >= 1) {
						avgDiv += 1.0f;
						ubyte lfsrCarry = 0;
						lfsrCarry ^= !!(ch4LFSR[lfsrMode] & 2);
						ch4LFSR[lfsrMode] >>= 1;
						lfsrCarry ^= !!(ch4LFSR[lfsrMode] & 2);
						if (lfsrCarry) {
							ch4LFSR[lfsrMode] |= lfsrMax[lfsrMode];
						}
						ch4Out += [-1, 1][ch4LFSR[lfsrMode] & 1];
						ch4Samples--;
					}
					float sample = ch4Out;
					if (avgDiv > 1) {
						sample /= avgDiv;
					}
					if (mixer.reg.panCh4Left) {
						samples[0] += (Vol[3] * sample) / 15.0f;
					}
					if (mixer.reg.panCh4Right) {
						samples[1] += (Vol[3] * sample) / 15.0f;
					}
				}
			}
			samples[0] /= 4.0f;
			samples[1] /= 4.0f;
		}
	}
}
