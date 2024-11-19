module pxtone.text;
// '12/03/03

import std.exception;

import pxtone.descriptor;

struct pxtnText {
	private const(char)[] _p_comment_buf;
	private const(char)[] _p_name_buf;

	public void set_comment_buf(const(char)[] comment) nothrow @safe {
		if (comment.length == 0) {
			_p_comment_buf = null;
		}
		_p_comment_buf = comment;
	}

	public const(char)[] get_comment_buf() const nothrow @safe {
		return _p_comment_buf;
	}

	public bool is_comment_buf() const nothrow @safe {
		return _p_comment_buf != null;
	}

	public void set_name_buf(const(char)[] name) nothrow @safe {
		if (name.length == 0) {
			_p_name_buf = null;
		}
		_p_name_buf = name;
	}

	public const(char)[] get_name_buf() const nothrow @safe {
		return _p_name_buf;
	}

	public bool is_name_buf() const nothrow @safe {
		return _p_name_buf != null;
	}
}
