class_name DwarfAppearanceData
extends Resource

## One dwarf's rolled visual attributes (doc 41b §DwarfAppearanceData).
##
## A typed Resource so it serializes cleanly with the future save system and
## can be passed around without loose dictionaries. Values are pool ids from
## data/entities/dwarves/appearance.json — never display names.

@export var gender: String = "male"          # "male" | "female"
@export var age_tier: String = "adult"       # "young" | "adult" | "middle" | "elder"
@export var skin_tone: String = "medium"     # "pale" | "medium" | "tan" | "dark"
@export var eye_color: String = "grey"       # "grey" | "blue" | "green" | "brown" | "amber" | "red"
@export var hair_color: String = "brown"     # "black" | "dark_brown" | "brown" | "auburn" | "red" | "blonde" | "grey" | "white"
@export var hair_style: String = "short_back"   # gender-specific style id; "bald" for none (male)
@export var eyebrow_style: String = "thick_flat"  # gender-specific eyebrow id
@export var beard_style: String = ""         # male only; "" = no beard
@export var scar: String = "none"            # "none" | "cheek_slash" | "brow_notch" | "nose_bridge" | "chin_split"
