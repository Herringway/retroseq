module pxtone.text;
// '12/03/03

import std.exception;

import pxtone.descriptor;

private void _read4_malloc(ref char[] pp, ref pxtnDescriptor p_doc) @safe {
	int p_buf_size;
	p_doc.r(p_buf_size);
	enforce(p_buf_size >= 0, "Invalid string size");

	pp = new char[](p_buf_size);

	if (p_buf_size) {
		p_doc.r(pp[0 .. p_buf_size]);
	}
}

private void _write4(const char[] p, ref pxtnDescriptor p_doc) @safe {
	p_doc.w_asfile(cast(int)p.length);
	p_doc.w_asfile(p);
}

struct pxtnText {
private:
	char[] _p_comment_buf;

	char[] _p_name_buf;

public:
	bool set_comment_buf(scope const(char)[] comment) nothrow @safe {
		_p_comment_buf = null;
		if (comment.length == 0) {
			return true;
		}
		_p_comment_buf = comment.dup;
		return true;
	}

	const(char)[] get_comment_buf() const nothrow @safe {
		return _p_comment_buf;
	}

	bool is_comment_buf() const nothrow @safe {
		return _p_comment_buf != null;
	}

	bool set_name_buf(scope const(char)[] name) nothrow @safe {
		_p_name_buf = null;
		if (name.length == 0) {
			return true;
		}
		_p_name_buf = name.dup;
		return true;
	}

	const(char)[] get_name_buf() const nothrow @safe {
		return _p_name_buf;
	}

	bool is_name_buf() const nothrow @safe {
		return _p_name_buf != null;
	}

	void Comment_r(ref pxtnDescriptor p_doc) @safe {
		_read4_malloc(_p_comment_buf, p_doc);
	}

	bool Comment_w(ref pxtnDescriptor p_doc) @safe {
		if (!_p_comment_buf) {
			return false;
		}
		_write4(_p_comment_buf, p_doc);
		return true;
	}

	void Name_r(ref pxtnDescriptor p_doc) @safe {
		_read4_malloc(_p_name_buf, p_doc);
	}

	bool Name_w(ref pxtnDescriptor p_doc) @safe {
		if (!_p_name_buf) {
			return false;
		}
		_write4(_p_name_buf, p_doc);
		return true;
	}
}
