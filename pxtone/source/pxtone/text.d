///
module pxtone.text;
// '12/03/03

import std.exception;

import pxtone.descriptor;

///
struct PxtnText {
	private const(char)[] pCommentBuf; ///
	private const(char)[] pNameBuf; ///

	///
	public void setCommentBuf(const(char)[] comment) nothrow @safe {
		if (comment.length == 0) {
			pCommentBuf = null;
		}
		pCommentBuf = comment;
	}

	///
	public const(char)[] getCommentBuf() const nothrow @safe {
		return pCommentBuf;
	}

	///
	public bool isCommentBuf() const nothrow @safe {
		return pCommentBuf != null;
	}

	///
	public void setNameBuf(const(char)[] name) nothrow @safe {
		if (name.length == 0) {
			pNameBuf = null;
		}
		pNameBuf = name;
	}

	///
	public const(char)[] getNameBuf() const nothrow @safe {
		return pNameBuf;
	}

	///
	public bool isNameBuf() const nothrow @safe {
		return pNameBuf != null;
	}
}
