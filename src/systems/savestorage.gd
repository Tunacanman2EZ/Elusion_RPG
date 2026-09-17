# savestorage.gd — the interface CharacterData saves and loads through.
#
# There are two implementations:
#
#   LocalStorage   an atomic file in user://. What the game shipped with.
#   ServerStorage  the Flask backend. What it is moving to.
#
# CharacterData holds one of these in `storage` and never asks which. That is
# the whole point: the swap is one line in load_for_user(), and the 29 places
# that call save_data() do not change at all.
#
# WHY A BASE CLASS AND NOT JUST DUCK TYPING
# -----------------------------------------
# GDScript has no interfaces, but it does have typed variables, and
# `var storage: SaveStorage` is what makes the editor complain when a third
# implementation forgets a method — rather than the game failing at runtime on
# whatever line first calls it, in a scene, during play.
#
# ON await
# --------
# LocalStorage.load() returns immediately. ServerStorage.load() cannot: it has
# to wait for HTTP. So load() is treated as a coroutine by every caller, and
# they all write `await storage.load()`.
#
# That is safe for BOTH: awaiting a function that is not a coroutine simply
# returns its value. So one call site serves a synchronous file read and an
# asynchronous network round trip with no branch anywhere.
#
# save() is deliberately NOT a coroutine. It is called from a debounce timer
# during gameplay and nothing waits on the result, so ServerStorage starts its
# push and returns immediately. `true` from save() means "accepted", not
# "persisted" — which was already true of the local implementation, since
# CharacterData debounces writes.
class_name SaveStorage
extends RefCounted


# TRUE when this backend is the authority on the data, rather than a file the
# player could edit.
#
# CharacterData's save signing and anti-tamper sanitising exist to defend a
# local file against being opened in a text editor. When the server owns the
# data none of that means anything — a tampered local copy is simply
# overwritten on the next load — so those passes are skipped rather than run
# against data they cannot say anything useful about.
#
# This flag is the seam along which that code eventually gets deleted.
var is_authoritative: bool = false


func save(_payload: Dictionary) -> bool:
	push_error("SaveStorage.save() called on the base class — use LocalStorage or ServerStorage.")
	return false


func load() -> Dictionary:
	push_error("SaveStorage.load() called on the base class — use LocalStorage or ServerStorage.")
	return {}


func has_unpushed() -> bool:
	"""True when this backend accepted a save it has since failed to persist.

	WHY THE INTERFACE NEEDS THIS AT ALL. save() returns "accepted", not
	"persisted" - the header above says so - and for ServerStorage the two are
	separated by an HTTP round trip that happens after save() has already
	returned true. So the only thing that knows a write did not land is the
	backend, and CharacterData has no way to ask.

	It could not ask, and that was a data-loss path. CharacterData cleared
	_save_pending before calling save(), a rejected PUT left the section dirty
	but nothing queued, and flush_save() at quit then returned early because
	nothing looked pending. The progress since the last successful push was
	gone from the server while the client still displayed it.

	FALSE ON THE BASE CLASS AND ON ANY SYNCHRONOUS BACKEND. LocalStorage's
	save() has already hit the disk by the time it returns, so there is never a
	gap for this to describe.
	"""
	return false
