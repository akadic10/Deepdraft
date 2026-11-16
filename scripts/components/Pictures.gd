extends RefCounted

## Where a thing's picture is kept. A picture carries the last part of its id (doc 13, "Naming
## ids and files"): `base:item:pine_log` is `pine_log.png` among the items and
## `base:furniture:bench` is `bench.png` among the furniture. This is the only script that names
## the two folders; everything else asks here, the tools that draw the pictures included. It
## names no autoload, so tools and tests can preload it:
## `const Pictures = preload("res://scripts/components/Pictures.gd")`.

const ITEMS := "res://assets/ui/items/"
const FURNITURE := "res://assets/ui/furniture/"


## The last part of an id: "pine_log" for "base:item:pine_log".
static func last_part(id: String) -> String:
	return id.get_slice(":", id.get_slice_count(":") - 1)


## The file an id's picture is kept in, in either folder: "pine_log.png".
static func file_name(id: String) -> String:
	return last_part(id) + ".png"


## An item's own picture. The path comes back whether or not the file is there.
static func item(id: String) -> String:
	return ITEMS + file_name(id)


## A piece of furniture's picture, from its key or from its packed item's. The path comes back
## whether or not the file is there.
static func furniture(id: String) -> String:
	return FURNITURE + file_name(id)


## The picture of goods that may be a packed piece: the item's own, or else the furniture's of
## the same last part. The furniture path comes back when neither file is there.
static func of(id: String) -> String:
	var path := item(id)
	return path if ResourceLoader.exists(path) else furniture(id)
