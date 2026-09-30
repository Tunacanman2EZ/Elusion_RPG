extends RefCounted
## The chat language filter: what a player who has it on sees instead of the
## worst words. Display only - the server keeps what was said, staff read it
## as said, and a report carries it whole.
##
## WHOLE WORDS, NOT PIECES OF THEM. The classic failure of a filter is the one
## that stars out "class", "assess" and a town called Scunthorpe because a
## short word sits inside a long one. A word is masked here only when the whole
## word is on the list, or is a listed word with an ordinary ending ("-ed",
## "-ing", "-head"...).
##
## WHAT IT CATCHES OF DISGUISE: letters swapped for look-alike symbols ($ for
## s, 1 for i, @ for a) and stretched words (a letter held down). What it does
## not: words split up with spaces, and other languages. It is a courtesy for
## the player who turns it on, not a wall - the wall is Report, and staff.
##
## The list is kept ROT13'd so this file does not read as a list of slurs to
## everyone who opens it. It is decoded once, on first use.

const _ENCODED := "shpx shpxre zbgureshpxre shx shd fuvg ohyyfuvg fuvgr ovgpu onfgneq" \
	+ " nffubyr nff nefr nefrubyr qvpx qvpxurnq pbpx phag chffl cvff cevpx gjng" \
	+ " jnaxre juber fyhg qbhpur qbhpuront wnpxnff qhzonff qvyqb oybjwbo unaqwbo" \
	+ " wvmm phz encr encvfg avttre avttn avttnu snttbg snt ergneq ergneqrq fcvp" \
	+ " puvax xvxr genaal qlxr jrgonpx tbbx pbba cnxv ornare xlf"

# Endings that keep a listed word listed. Short words (three letters or fewer)
# take only "s": "cum" + "in" is a spice.
const _ENDINGS := ["", "s", "es", "ed", "er", "ers", "ing", "in", "y", "ty",
	"head", "heads", "face", "faces", "hole", "holes"]
# Real words the endings would otherwise make.
const _ALLOWED := ["cocky"]
# What look-alike characters stand for.
const _LOOKALIKE := {"@": "a", "4": "a", "3": "e", "1": "i", "!": "i", "|": "i",
	"0": "o", "$": "s", "5": "s", "7": "t", "8": "b"}

static var _exact: Dictionary = {}
static var _squashed: Dictionary = {}


static func clean(text: String) -> String:
	"""`text` with each filtered word masked to its first letter and stars."""
	_load()
	var out := ""
	var i := 0
	var n := text.length()
	while i < n:
		if not _is_word_char(text[i]):
			out += text[i]
			i += 1
			continue
		var j := i
		while j < n and _is_word_char(text[j]):
			j += 1
		var word: String = text.substr(i, j - i)
		if is_filtered(word):
			var core: String = _core(word)
			out += _mask(core) + word.substr(core.length())
		else:
			out += word
		i = j
	return out


static func is_filtered(word: String) -> bool:
	_load()
	var plain: String = _plain(_core(word))
	if plain == "" or _ALLOWED.has(plain):
		return false
	if _exact.has(plain):
		return true
	# STRETCHED ONLY: a run of three or more of one letter is somebody leaning
	# on a key, and is squashed before a second look. Squashing every double
	# would turn "as" and "ass" into the same word.
	if _has_run_of_three(plain) and _squashed.has(_squash(plain)):
		return true
	return false


static func _core(word: String) -> String:
	# A word followed by "!!" is the word and some shouting: the ! only
	# stands for an i INSIDE a word, and the shouting is left on the screen.
	var core: String = word
	while core.length() > 1 and core.ends_with("!"):
		core = core.left(core.length() - 1)
	return core


static func _mask(word: String) -> String:
	return word.left(1) + "*".repeat(maxi(0, word.length() - 1))


static func _is_word_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") \
		or _LOOKALIKE.has(c)


static func _plain(word: String) -> String:
	var out := ""
	for c in word.to_lower():
		out += _LOOKALIKE.get(c, c)
	return out


static func _squash(word: String) -> String:
	var out := ""
	for c in word:
		if out == "" or out.right(1) != c:
			out += c
	return out


static func _has_run_of_three(word: String) -> bool:
	for i in range(2, word.length()):
		if word[i] == word[i - 1] and word[i] == word[i - 2]:
			return true
	return false


static func _rot13(text: String) -> String:
	var out := ""
	for c in text:
		var code: int = c.unicode_at(0)
		if code >= 97 and code <= 122:
			code = (code - 97 + 13) % 26 + 97
		elif code >= 65 and code <= 90:
			code = (code - 65 + 13) % 26 + 65
		out += String.chr(code)
	return out


static func _load() -> void:
	if not _exact.is_empty():
		return
	for base in _rot13(_ENCODED).split(" ", false):
		var endings: Array = _ENDINGS if base.length() > 3 else ["", "s"]
		for ending in endings:
			_exact[base + ending] = true
			_squashed[_squash(base + ending)] = true
