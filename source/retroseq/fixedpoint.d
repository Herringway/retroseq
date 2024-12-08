///
module retroseq.fixedpoint;

union FixedPoint2(size_t size, size_t scaling) {
	import std.algorithm : among;
	import std.math : log2;
	import std.meta : AliasSeq;
	import std.traits : isFloatingPoint, isIntegral, Unsigned;
	private alias Integrals = AliasSeq!(byte, short, int, long);
	private alias UnderlyingType = Integrals[cast(size_t)log2(size / 8.0)];
	private enum scaleMultiplier = ulong(1) << scaling;
	private alias supportedOps = AliasSeq!("+", "-", "/", "*", "%", "^^");
	private UnderlyingType value; ///
	///
	this(double value) @safe pure {
		this.value = cast(UnderlyingType)(value * scaleMultiplier);
	}
	///
	this(size_t n)(FixedPoint2!n value) @safe pure {
		static if (n > size) {
			this(value.fraction << ((size - n) / 2), value.integer);
		} else {
			this(value.fraction >> ((size - n) / 2), value.integer);
		}
	}
	///
	T opCast(T)() const @safe pure if(isFloatingPoint!T) {
		return cast(T)(cast(UnderlyingType)value) / cast(double)scaleMultiplier;
	}
	///
	T opCast(T : FixedPoint2!(otherSize, otherScaling), size_t otherSize, size_t otherScaling)() const @safe pure {
		T newValue;
		static if (otherScaling > scaling) {
			newValue.value = cast(typeof(T.value))(cast(typeof(T.value))value << (otherScaling - scaling));
		} else {
			newValue.value = cast(typeof(T.value))(value >> (scaling - otherScaling));
		}
		return newValue;
	}
	///
	FixedPoint2 opBinary(string op, T)(T value) const if (op.among(supportedOps) && (isFloatingPoint!T || isIntegral!T)) {
		FixedPoint2 result;
		static if ((op == "+") || (op == "-") || (op == "%") || (op == "^^")) {
			result.value = cast(UnderlyingType)mixin("((this.value / scaleMultiplier)", op, "value) * scaleMultiplier");
		} else {
			result.value = cast(UnderlyingType)mixin("this.value", op, "value");
		}
		return result;
	}
	///
	FixedPoint2 opBinaryRight(string op, T)(T value) const if (op.among(supportedOps) && (isFloatingPoint!T || isIntegral!T)) {
		return FixedPoint2(mixin("(cast(T)this)", op, "value"));
	}
	///
	FixedPoint2 opBinary(string op, size_t otherSize, size_t otherScaling)(FixedPoint2!(otherSize, otherScaling) value) const if (op.among(supportedOps)) {
		return FixedPoint2(mixin("(cast(double)this)", op, "cast(double)value"));
	}
	///
	FixedPoint2 opUnary(string op : "-")() const {
		return FixedPoint2(-cast(double)this);
	}
	///
	int opCmp(size_t n)(FixedPoint2!n value) const @safe pure {
		return cast(UnderlyingType)value - cast(value.UnderlyingType)value.value;
	}
	///
	int opCmp(double value) const @safe pure {
		import std.math.operations : cmp;
		return cmp(cast(double)this, value);
	}
	///
	int opEquals(FixedPoint2 value) const @safe pure {
		return this.value == value.value;
	}
	///
	int opEquals(double value) const @safe pure {
		return cast(double)this == value;
	}
	///
	FixedPoint2 opAssign(double value) @safe pure {
		this.value = cast(UnderlyingType)(value * scaleMultiplier);
		return this;
	}
	///
	FixedPoint2 opOpAssign(string op)(double value) @safe pure  if (op.among(supportedOps)) {
		this.value = opBinary!op(value).value;
		return this;
	}
	///
	FixedPoint2 opOpAssign(string op)(FixedPoint2 value) @safe pure  if (op.among(supportedOps)) {
		this.value = opBinary!op(value).value;
		return this;
	}
	///
	T opCast(T)() const @safe pure if (isIntegral!T) {
		return cast(T)(value >> scaling);
	}
	///
	void toString(S)(ref S sink) const {
		import std.format : formattedWrite;
		sink.formattedWrite!"%s"(this.asDouble);
	}
}

@safe pure unittest {
	import std.math.operations : isClose;
	alias FP64 = FixedPoint2!(64, 32);
	alias FP32 = FixedPoint2!(32, 16);
	alias FP16 = FixedPoint2!(16, 8);
	FP32 sample = 2.0;
	assert(sample.value == 0x00020000);

	assert((cast(double)(FP32(2.0) / 3)).isClose(2.0 / 3.0, 1e-3, 1e-9));
	assert(cast(double)(FP32(2.0) * 3) == 6.0);
	assert(cast(double)(FP32(2.0) % 3) == 2.0);
	assert(cast(double)(FP32(2.0) ^^ 3) == 8.0);
	assert(cast(double)(FP32(2.0) + 3) == 5.0);
	assert(cast(double)(FP32(2.0) - 3) == -1.0);

	assert((cast(double)(FP32(2.0) / 3.0)).isClose(2.0 / 3.0, 1e-3, 1e-9));
	assert(cast(double)(FP32(2.0) * 3.0) == 6.0);
	assert(cast(double)(FP32(2.0) % 3.0) == 2.0);
	assert(cast(double)(FP32(2.0) ^^ 3.0) == 8.0);
	assert(cast(double)(FP32(2.0) + 3.0) == 5.0);
	assert(cast(double)(FP32(2.0) - 3.0) == -1.0);

	assert((cast(double)(FP32(2.0) / FP32(3.0))).isClose(2.0 / 3.0, 1e-3, 1e-9));
	assert(cast(double)(FP32(2.0) * FP32(3.0)) == 6.0);
	assert(cast(double)(FP32(2.0) % FP32(3.0)) == 2.0);
	assert(cast(double)(FP32(2.0) ^^ FP32(3.0)) == 8.0);
	assert(cast(double)(FP32(2.0) + FP32(3.0)) == 5.0);
	assert(cast(double)(FP32(2.0) - FP32(3.0)) == -1.0);

	sample *= 1.5;
	assert(cast(double)sample == 3.0);
	assert(cast(int)sample == 3);
	assert(cast(byte)sample == 3);
	assert(sample.value == 0x00030000);

	assert(cast(FP16)sample == FP16(3.0));
	assert(cast(FP64)sample == FP64(3.0));

	FP16 sample2 = 1.5;
	assert(sample2.value == 0x0180);
	assert(cast(double)(FP32(2.0) * sample2) == 3.0);
	assert(cast(double)(FP32(2.0) - FP16(1.5)) == 0.5);
	assert(cast(double)(FP32(2.0) + FP16(1.5)) == 3.5);

	assert(sample2 * 2.0 == 3.0);
	assert(2.0 * sample2 == 3.0);

	sample = 256.0;
	assert(cast(byte)sample == 0);
	assert(cast(short)sample == 256);
	assert(cast(long)sample == 256);

	sample = -32.0;
	assert(cast(byte)sample == -32);
	assert(cast(short)sample == -32);
	assert(cast(long)sample == -32);
}
