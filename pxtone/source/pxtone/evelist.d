module pxtone.evelist;

import pxtone.descriptor;
import pxtone.error;
import pxtone.util;

///////////////////////
// global
///////////////////////

private bool evelistKindIsTail(int kind) nothrow @safe {
	if (kind == EventKind.on || kind == EventKind.portament) {
		return true;
	}
	return false;
}

enum EventKind {
	none = 0, //  0

	on, //  1
	key, //  2
	panVolume, //  3
	velocity, //  4
	volume, //  5
	portament, //  6
	beatClock, //  7
	beatTempo, //  8
	beatNumber, //  9
	repeat, // 10
	last, // 11
	voiceNumber, // 12
	groupNumber, // 13
	tuning, // 14
	panTime, // 15

	num, // 16
}

struct EventDefault {
	enum volume = 104;
	enum velocity = 104;
	enum panVolume = 64;
	enum panTime = 64;
	enum portament = 0;
	enum voiceNumber = 0;
	enum groupNumber = 0;
	enum key = 0x6000;
	enum basicKey = 0x4500; // 4A(440Hz?)
	enum tuning = 1.0f;

	enum beatNumber = 4;
	enum beatTempo = 120;
	enum beatClock = 480;
}

struct EveRecord {
	ubyte kind;
	ubyte unitNumber;
	ubyte reserve1;
	ubyte reserve2;
	int value;
	int clock;
	EveRecord* prev;
	EveRecord* next;
}

private int defaultKindValue(ubyte kind) nothrow @safe {
	switch (kind) {
		//	case EventKind.on        : return ;
	case EventKind.key:
		return EventDefault.key;
	case EventKind.panVolume:
		return EventDefault.panVolume;
	case EventKind.velocity:
		return EventDefault.velocity;
	case EventKind.volume:
		return EventDefault.volume;
	case EventKind.portament:
		return EventDefault.portament;
	case EventKind.beatClock:
		return EventDefault.beatClock;
	case EventKind.beatTempo:
		return EventDefault.beatTempo;
	case EventKind.beatNumber:
		return EventDefault.beatNumber;
		//	case EventKind.repeat    : return ;
		//	case EventKind.last      : return ;
	case EventKind.voiceNumber:
		return EventDefault.voiceNumber;
	case EventKind.groupNumber:
		return EventDefault.groupNumber;
	case EventKind.tuning:
		return reinterpretFloat(EventDefault.tuning);
	case EventKind.panTime:
		return EventDefault.panTime;
	default:
		break;
	}
	return 0;
}

private int comparePriority(ubyte kind1, ubyte kind2) nothrow @safe {
	static immutable int[EventKind.num] priorityTable = [
		0, // EventKind.none  = 0
		50, // EventKind.on
		40, // EventKind.key
		60, // EventKind.panVolume
		70, // EventKind.velocity
		80, // EventKind.volume
		30, // EventKind.portament
		0, // EventKind.beatClock
		0, // EventKind.beatTempo
		0, // EventKind.beatNumber
		0, // EventKind.repeat
		255, // EventKind.last
		10, // EventKind.voiceNumber
		20, // EventKind.groupNumber
		90, // EventKind.tuning
		100, // EventKind.panTime
	];

	return priorityTable[kind1] - priorityTable[kind2];
}

// event struct(12byte) =================
struct EventStructure {
	ushort unitIndex;
	ushort eventKind;
	ushort dataNumber; // １イベントのデータ数。現在は 2 ( clock / volume ）
	ushort rrr;
	uint eventNumber;
}

//--------------------------------

struct PxtnEventList {

private:

	int eventAllocatedNum;
	EveRecord[] events;
	EveRecord* start;
	int linear;

	EveRecord* eventRecords;

	void recordSet(EveRecord* pRec, EveRecord* prev, EveRecord* next, int clock, ubyte unitNumber, ubyte kind, int value) nothrow @safe {
		if (prev) {
			prev.next = pRec;
		} else {
			start = pRec;
		}
		if (next) {
			next.prev = pRec;
		}

		pRec.next = next;
		pRec.prev = prev;
		pRec.clock = clock;
		pRec.kind = kind;
		pRec.unitNumber = unitNumber;
		pRec.value = value;
	}

	void recordCut(EveRecord* pRec) nothrow @safe {
		if (pRec.prev) {
			pRec.prev.next = pRec.next;
		} else {
			start = pRec.next;
		}
		if (pRec.next) {
			pRec.next.prev = pRec.prev;
		}
		pRec.kind = EventKind.none;
	}

public:

	void release() nothrow @safe {
		events = null;
		start = null;
		eventAllocatedNum = 0;
	}

	void clear() nothrow @safe {
		if (events) {
			events[0 .. eventAllocatedNum] = EveRecord.init;
		}
		start = null;
	}

	~this() nothrow @safe {
		release();
	}

	void allocate(int maxEventNumber) @safe {
		release();
		events = new EveRecord[](maxEventNumber);
		if (!(events)) {
			throw new PxtoneException("Unable to allocate memory");
		}
		events[0 .. maxEventNumber] = EveRecord.init;
		eventAllocatedNum = maxEventNumber;
	}

	int getNumMax() const nothrow @safe {
		if (!events) {
			return 0;
		}
		return eventAllocatedNum;
	}

	int getMaxClock() const nothrow @safe {
		int maxClock = 0;
		int clock;

		for (const(EveRecord)* p = start; p; p = p.next) {
			if (evelistKindIsTail(p.kind)) {
				clock = p.clock + p.value;
			} else {
				clock = p.clock;
			}
			if (clock > maxClock) {
				maxClock = clock;
			}
		}

		return maxClock;

	}

	int getCount() const nothrow @safe {
		if (!events || !start) {
			return 0;
		}

		int count = 0;
		for (const(EveRecord)* p = start; p; p = p.next) {
			count++;
		}
		return count;
	}

	int getCount(ubyte kind, int value) const nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;
		for (const(EveRecord)* p = start; p; p = p.next) {
			if (p.kind == kind && p.value == value) {
				count++;
			}
		}
		return count;
	}

	int getCount(ubyte unitNumber) const nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;
		for (const(EveRecord)* p = start; p; p = p.next) {
			if (p.unitNumber == unitNumber) {
				count++;
			}
		}
		return count;
	}

	int getCount(ubyte unitNumber, ubyte kind) const nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;
		for (const(EveRecord)* p = start; p; p = p.next) {
			if (p.unitNumber == unitNumber && p.kind == kind) {
				count++;
			}
		}
		return count;
	}

	int getCount(int clock1, int clock2, ubyte unitNumber) const nothrow @safe {
		if (!events) {
			return 0;
		}

		const(EveRecord)* p;
		for (p = start; p; p = p.next) {
			if (p.unitNumber == unitNumber) {
				if (p.clock >= clock1) {
					break;
				}
				if (evelistKindIsTail(p.kind) && p.clock + p.value > clock1) {
					break;
				}
			}
		}

		int count = 0;
		for (; p; p = p.next) {
			if (p.clock != clock1 && p.clock >= clock2) {
				break;
			}
			if (p.unitNumber == unitNumber) {
				count++;
			}
		}
		return count;
	}

	int getValue(int clock, ubyte unitNumber, ubyte kind) const nothrow @safe {
		if (!events) {
			return 0;
		}

		const(EveRecord)* p;
		int val = defaultKindValue(kind);

		for (p = start; p; p = p.next) {
			if (p.clock > clock) {
				break;
			}
			if (p.unitNumber == unitNumber && p.kind == kind) {
				val = p.value;
			}
		}

		return val;
	}

	const(EveRecord)* getRecords() const nothrow @safe {
		if (!events) {
			return null;
		}
		return start;
	}

	bool recordAdd(int clock, ubyte unitNumber, ubyte kind, int value) nothrow @safe {
		if (!events) {
			return false;
		}

		EveRecord* pNew = null;
		EveRecord* pPrev = null;
		EveRecord* pNext = null;

		// 空き検索
		for (int r = 0; r < eventAllocatedNum; r++) {
			if (events[r].kind == EventKind.none) {
				pNew = &events[r];
				break;
			}
		}
		if (!pNew) {
			return false;
		}

		// first.
		if (!start) {
		}  // top.
		else if (clock < start.clock) {
			pNext = start;
		} else {

			for (EveRecord* p = start; p; p = p.next) {
				// 同時 
				if (p.clock == clock) {
					for (; true; p = p.next) {
						if (p.clock != clock) {
							pPrev = p.prev;
							pNext = p;
							break;
						}
						if (unitNumber == p.unitNumber && kind == p.kind) {
							pPrev = p.prev;
							pNext = p.next;
							p.kind = EventKind.none;
							break;
						} // 置き換え
						if (comparePriority(kind, p.kind) < 0) {
							pPrev = p.prev;
							pNext = p;
							break;
						} // プライオリティを検査
						if (!p.next) {
							pPrev = p;
							break;
						} // 末端
					}
					break;
				} else if (p.clock > clock) {
					pPrev = p.prev;
					pNext = p;
					break;
				}  // 追い越した
				else if (!p.next) {
					pPrev = p;
					break;
				} // 末端
			}
		}

		recordSet(pNew, pPrev, pNext, clock, unitNumber, kind, value);

		// cut prev tail
		if (evelistKindIsTail(kind)) {
			for (EveRecord* p = pNew.prev; p; p = p.prev) {
				if (p.unitNumber == unitNumber && p.kind == kind) {
					if (clock < p.clock + p.value) {
						p.value = clock - p.clock;
					}
					break;
				}
			}
		}

		// delete next
		if (evelistKindIsTail(kind)) {
			for (EveRecord* p = pNew.next; p && p.clock < clock + value; p = p.next) {
				if (p.unitNumber == unitNumber && p.kind == kind) {
					recordCut(p);
				}
			}
		}

		return true;
	}

	bool recordAdd(int clock, ubyte unitNumber, ubyte kind, float newValue) nothrow @safe {
		union Reinterpret {
			float f;
			int i;
		}
		int value = Reinterpret(newValue).i;
		return recordAdd(clock, unitNumber, kind, value);
	}

	/////////////////////
	// linear
	/////////////////////

	bool linearStart() nothrow @safe {
		if (!events) {
			return false;
		}
		clear();
		linear = 0;
		return true;
	}

	void linearAdd(int clock, ubyte unitNumber, ubyte kind, int value) nothrow @safe {
		EveRecord* p = &events[linear];

		p.clock = clock;
		p.unitNumber = unitNumber;
		p.kind = kind;
		p.value = value;

		linear++;
	}

	void linearAdd(int clock, ubyte unitNumber, ubyte kind, float newValue) nothrow @safe {
		union Reinterpret {
			float f;
			int i;
		}
		int value = Reinterpret(newValue).i;
		linearAdd(clock, unitNumber, kind, value);
	}

	void linearEnd(bool bConnect) nothrow @safe {
		if (events[0].kind != EventKind.none) {
			start = &events[0];
		}

		if (bConnect) {
			for (int r = 1; r < eventAllocatedNum; r++) {
				if (events[r].kind == EventKind.none) {
					break;
				}
				events[r].prev = &events[r - 1];
				events[r - 1].next = &events[r];
			}
		}
	}

	int recordClockShift(int clock, int shift, ubyte unitNumber) nothrow @safe  // can't be under 0.
	{
		if (!events) {
			return 0;
		}
		if (!start) {
			return 0;
		}
		if (!shift) {
			return 0;
		}

		int count = 0;
		int c;
		ubyte k;
		int v;
		EveRecord* pNext;
		EveRecord* pPrev;
		EveRecord* p = start;

		if (shift < 0) {
			for (; p; p = p.next) {
				if (p.clock >= clock) {
					break;
				}
			}
			while (p) {
				if (p.unitNumber == unitNumber) {
					c = p.clock + shift;
					k = p.kind;
					v = p.value;
					pNext = p.next;

					recordCut(p);
					if (c >= 0) {
						recordAdd(c, unitNumber, k, v);
					}
					count++;

					p = pNext;
				} else {
					p = p.next;
				}
			}
		} else if (shift > 0) {
			while (p.next) {
				p = p.next;
			}
			while (p) {
				if (p.clock < clock) {
					break;
				}

				if (p.unitNumber == unitNumber) {
					c = p.clock + shift;
					k = p.kind;
					v = p.value;
					pPrev = p.prev;

					recordCut(p);
					recordAdd(c, unitNumber, k, v);
					count++;

					p = pPrev;
				} else {
					p = p.prev;
				}
			}
		}
		return count;
	}

	int recordValueSet(int clock1, int clock2, ubyte unitNumber, ubyte kind, int value) nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;

		for (EveRecord* p = start; p; p = p.next) {
			if (p.unitNumber == unitNumber && p.kind == kind && p.clock >= clock1 && p.clock < clock2) {
				p.value = value;
				count++;
			}
		}

		return count;
	}

	int recordValueChange(int clock1, int clock2, ubyte unitNumber, ubyte kind, int value) nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;

		int max, min;

		switch (kind) {
		case EventKind.none:
			max = 0;
			min = 0;
			break;
		case EventKind.on:
			max = 120;
			min = 120;
			break;
		case EventKind.key:
			max = 0xbfff;
			min = 0;
			break;
		case EventKind.panVolume:
			max = 0x80;
			min = 0;
			break;
		case EventKind.panTime:
			max = 0x80;
			min = 0;
			break;
		case EventKind.velocity:
			max = 0x80;
			min = 0;
			break;
		case EventKind.volume:
			max = 0x80;
			min = 0;
			break;
		default:
			max = 0;
			min = 0;
		}

		for (EveRecord* p = start; p; p = p.next) {
			if (p.unitNumber == unitNumber && p.kind == kind && p.clock >= clock1) {
				if (clock2 == -1 || p.clock < clock2) {
					p.value += value;
					if (p.value < min) {
						p.value = min;
					}
					if (p.value > max) {
						p.value = max;
					}
					count++;
				}
			}
		}

		return count;
	}

	int recordValueOmit(ubyte kind, int value) nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;

		for (EveRecord* p = start; p; p = p.next) {
			if (p.kind == kind) {
				if (p.value == value) {
					recordCut(p);
					count++;
				} else if (p.value > value) {
					p.value--;
					count++;
				}
			}
		}
		return count;
	}

	int recordValueReplace(ubyte kind, int oldValue, int newValue) nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;

		if (oldValue == newValue) {
			return 0;
		}
		if (oldValue < newValue) {
			for (EveRecord* p = start; p; p = p.next) {
				if (p.kind == kind) {
					if (p.value == oldValue) {
						p.value = newValue;
						count++;
					} else if (p.value > oldValue && p.value <= newValue) {
						p.value--;
						count++;
					}
				}
			}
		} else {
			for (EveRecord* p = start; p; p = p.next) {
				if (p.kind == kind) {
					if (p.value == oldValue) {
						p.value = newValue;
						count++;
					} else if (p.value < oldValue && p.value >= newValue) {
						p.value++;
						count++;
					}
				}
			}
		}

		return count;
	}

	int recordDelete(int clock1, int clock2, ubyte unitNumber, ubyte kind) nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;

		for (EveRecord* p = start; p; p = p.next) {
			if (p.clock != clock1 && p.clock >= clock2) {
				break;
			}
			if (p.clock >= clock1 && p.unitNumber == unitNumber && p.kind == kind) {
				recordCut(p);
				count++;
			}
		}

		if (evelistKindIsTail(kind)) {
			for (EveRecord* p = start; p; p = p.next) {
				if (p.clock >= clock1) {
					break;
				}
				if (p.unitNumber == unitNumber && p.kind == kind && p.clock + p.value > clock1) {
					p.value = clock1 - p.clock;
					count++;
				}
			}
		}

		return count;
	}

	int recordDelete(int clock1, int clock2, ubyte unitNumber) nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;

		for (EveRecord* p = start; p; p = p.next) {
			if (p.clock != clock1 && p.clock >= clock2) {
				break;
			}
			if (p.clock >= clock1 && p.unitNumber == unitNumber) {
				recordCut(p);
				count++;
			}
		}

		for (EveRecord* p = start; p; p = p.next) {
			if (p.clock >= clock1) {
				break;
			}
			if (p.unitNumber == unitNumber && evelistKindIsTail(p.kind) && p.clock + p.value > clock1) {
				p.value = clock1 - p.clock;
				count++;
			}
		}

		return count;
	}

	int recordUnitNumberDelete(ubyte unitNumber) nothrow @safe  // delete event has the unit-no
	{
		if (!events) {
			return 0;
		}

		int count = 0;

		for (EveRecord* p = start; p; p = p.next) {
			if (p.unitNumber == unitNumber) {
				recordCut(p);
				count++;
			} else if (p.unitNumber > unitNumber) {
				p.unitNumber--;
				count++;
			}
		}
		return count;
	}

	int recordUnitNumberSet(ubyte unitNumber) nothrow @safe  // set the unit-no
	{
		if (!events) {
			return 0;
		}

		int count = 0;
		for (EveRecord* p = start; p; p = p.next) {
			p.unitNumber = unitNumber;
			count++;
		}
		return count;
	}

	int recordUnitNumberReplace(ubyte oldUnit, ubyte newUnit) nothrow @safe  // exchange unit
	{
		if (!events) {
			return 0;
		}

		int count = 0;

		if (oldUnit == newUnit) {
			return 0;
		}
		if (oldUnit < newUnit) {
			for (EveRecord* p = start; p; p = p.next) {
				if (p.unitNumber == oldUnit) {
					p.unitNumber = newUnit;
					count++;
				} else if (p.unitNumber > oldUnit && p.unitNumber <= newUnit) {
					p.unitNumber--;
					count++;
				}
			}
		} else {
			for (EveRecord* p = start; p; p = p.next) {
				if (p.unitNumber == oldUnit) {
					p.unitNumber = newUnit;
					count++;
				} else if (p.unitNumber < oldUnit && p.unitNumber >= newUnit) {
					p.unitNumber++;
					count++;
				}
			}
		}

		return count;
	}

	int beatClockOperation(int rate) nothrow @safe {
		if (!events) {
			return 0;
		}

		int count = 0;

		for (EveRecord* p = start; p; p = p.next) {
			p.clock *= rate;
			if (evelistKindIsTail(p.kind)) {
				p.value *= rate;
			}
			count++;
		}

		return count;
	}

	// ------------
	// io
	// ------------

	void ioWrite(ref PxtnDescriptor pDoc, int rough) const @safe {
		int eveNum = getCount();
		int relativeSize = 0;
		int absolute = 0;
		int clock;
		int value;

		for (const(EveRecord)* p = getRecords(); p; p = p.next) {
			clock = p.clock - absolute;

			relativeSize += getVarIntSize(p.clock);
			relativeSize += 1;
			relativeSize += 1;
			relativeSize += getVarIntSize(p.value);

			absolute = p.clock;
		}

		int size = cast(int)(int.sizeof + relativeSize);
		pDoc.write(size);
		pDoc.write(eveNum);

		absolute = 0;

		for (const(EveRecord)* p = getRecords(); p; p = p.next) {
			clock = p.clock - absolute;

			if (evelistKindIsTail(p.kind)) {
				value = p.value / rough;
			} else {
				value = p.value;
			}

			pDoc.writeVarInt(clock / rough);
			pDoc.write(p.unitNumber);
			pDoc.write(p.kind);
			pDoc.writeVarInt(value);

			absolute = p.clock;
		}
	}

	void ioRead(ref PxtnDescriptor pDoc) @safe {
		int size = 0;
		int eveNum = 0;

		pDoc.read(size);
		pDoc.read(eveNum);

		int clock = 0;
		int absolute = 0;
		ubyte unitNumber = 0;
		ubyte kind = 0;
		int value = 0;

		for (int e = 0; e < eveNum; e++) {
			pDoc.readVarInt(clock);
			pDoc.read(unitNumber);
			pDoc.read(kind);
			pDoc.readVarInt(value);
			absolute += clock;
			clock = absolute;
			linearAdd(clock, unitNumber, kind, value);
		}
	}

	int ioReadEventNum(ref PxtnDescriptor pDoc) const @safe {
		int size = 0;
		int eveNum = 0;

		pDoc.read(size);
		pDoc.read(eveNum);

		int count = 0;
		int clock = 0;
		ubyte unitNumber = 0;
		ubyte kind = 0;
		int value = 0;

		for (int e = 0; e < eveNum; e++) {
			pDoc.readVarInt(clock);
			pDoc.read(unitNumber);
			pDoc.read(kind);
			pDoc.readVarInt(value);
			count++;
		}
		if (count != eveNum) {
			return 0;
		}

		return eveNum;
	}

	bool x4xReadStart() nothrow @safe {
		if (!events) {
			return false;
		}
		clear();
		linear = 0;
		eventRecords = null;
		return true;
	}

	void x4xReadNewKind() nothrow @safe {
		eventRecords = null;
	}

	void x4xReadAdd(int clock, ubyte unitNumber, ubyte kind, int value) nothrow @safe {
		EveRecord* pNew = null;
		EveRecord* pPrev = null;
		EveRecord* pNext = null;

		pNew = &events[linear++];

		// first.
		if (!start) {
		}  // top
		else if (clock < start.clock) {
			pNext = start;
		} else {
			EveRecord* p;

			if (eventRecords) {
				p = eventRecords;
			} else {
				p = start;
			}

			for (; p; p = p.next) {
				// 同時
				if (p.clock == clock) {
					for (; true; p = p.next) {
						if (p.clock != clock) {
							pPrev = p.prev;
							pNext = p;
							break;
						}
						if (unitNumber == p.unitNumber && kind == p.kind) {
							pPrev = p.prev;
							pNext = p.next;
							p.kind = EventKind.none;
							break;
						} // 置き換え
						if (comparePriority(kind, p.kind) < 0) {
							pPrev = p.prev;
							pNext = p;
							break;
						} // プライオリティを検査
						if (!p.next) {
							pPrev = p;
							break;
						} // 末端
					}
					break;
				} else if (p.clock > clock) {
					pPrev = p.prev;
					pNext = p;
					break;
				}  // 追い越した
				else if (!p.next) {
					pPrev = p;
					break;
				} // 末端
			}
		}
		recordSet(pNew, pPrev, pNext, clock, unitNumber, kind, value);

		eventRecords = pNew;
	}

	// write event.
	void ioUnitReadX4xEvent(ref PxtnDescriptor pDoc, bool bTailAbsolute, bool bCheckRRR) @safe {
		EventStructure evnt;
		int clock = 0;
		int value = 0;
		int absolute = 0;
		int e = 0;
		int size = 0;

		pDoc.read(size);
		pDoc.read(evnt);

		if (evnt.dataNumber != 2) {
			throw new PxtoneException("fmt unknown");
		}
		if (evnt.eventKind >= EventKind.num) {
			throw new PxtoneException("fmt unknown");
		}
		if (bCheckRRR && evnt.rrr) {
			throw new PxtoneException("fmt unknown");
		}

		absolute = 0;
		for (e = 0; e < cast(int) evnt.eventNumber; e++) {
			pDoc.readVarInt(clock);
			pDoc.readVarInt(value);
			absolute += clock;
			clock = absolute;
			x4xReadAdd(clock, cast(ubyte) evnt.unitIndex, cast(ubyte) evnt.eventKind, value);
			if (bTailAbsolute && evelistKindIsTail(evnt.eventKind)) {
				absolute += value;
			}
		}
		if (e != evnt.eventNumber) {
			throw new PxtoneException("desc broken");
		}

		x4xReadNewKind();
	}

	void ioReadX4xEventNum(ref PxtnDescriptor pDoc, out int pNum) const @safe {
		EventStructure evnt;
		int work = 0;
		int e = 0;
		int size = 0;

		pDoc.read(size);
		pDoc.read(evnt);

		// support only 2
		if (evnt.dataNumber != 2) {
			throw new PxtoneException("fmt unknown");
		}

		for (e = 0; e < cast(int) evnt.eventNumber; e++) {
			pDoc.readVarInt(work);
			pDoc.readVarInt(work);
		}
		if (e != evnt.eventNumber) {
			throw new PxtoneException("desc broken");
		}

		pNum = evnt.eventNumber;
	}
}
