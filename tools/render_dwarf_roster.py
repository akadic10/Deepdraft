#!/usr/bin/env python3
"""Render the actual modular GLBs, including every hair/beard/age/brow style.

Software geometry preview; use Godot for the runtime lighting/material check.
Requires numpy and Pillow. --assets defaults to the live assets/dwarves folder.
"""
import argparse
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from dwarf_roster import AGES, HAIR_MALE, HAIR_FEMALE, BEARDS, BROWS_MALE, BROWS_FEMALE
from render_dwarf_redesign import glb, sheet, ROOT, SKIN, HAIR


def assemble(folder, hair='m_short_back', beard=None, age='adult', brow='m_arched',
             skin='medium', hair_color='brown', scar=None):
    def part(name,tint=(1,1,1),mirror=False):
        return glb(folder/(name+'.glb'),tint,mirror)
    s,h=SKIN[skin],HAIR[hair_color]
    parts=[part('body/head_'+age,s),part('body/body_base'),part('body/eyes',(.25,.55,.85)),
           part('eyebrows/brows_'+brow,h)]
    for mirror in (False,True):
        parts.extend([part('body/hand',s,mirror),part('body/foot',mirror=mirror)])
    if hair: parts.append(part('hair/hair_'+hair,h))
    if beard: parts.append(part('beards/beard_'+beard,h))
    if scar: parts.append(part('scars/scar_'+scar))
    return parts


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--assets',type=Path,default=ROOT/'assets/dwarves')
    ap.add_argument('--out',type=Path,default=ROOT/'tmp/dwarf_roster/renders')
    args=ap.parse_args(); args.out.mkdir(parents=True,exist_ok=True)
    hairs=['m_'+s for s in HAIR_MALE]+['f_'+s for s in HAIR_FEMALE]
    for angle,yaw,elev in [('front',25,20),('rear',145,35)]:
        sheet(args.out/f'hair_{angle}.png',f'Complete dwarf hair roster / {angle} / 8 voxels per block',
              [(s,assemble(args.assets,hair=s),yaw,elev) for s in hairs],cols=5,size=(245,300))
    sheet(args.out/'beards.png','Complete beard roster / front and three-quarter',
          [(b,assemble(args.assets,beard=b),yaw,elev) for yaw,elev in [(0,0),(50,20)] for b in BEARDS],cols=7,size=(245,300))
    sheet(args.out/'ages_brows.png','Age tiers and brow variations / shared crown and facial slots',
          [(a,assemble(args.assets,hair=None,age=a),0,0) for a in AGES]+
          [(b,assemble(args.assets,brow='m_'+b),0,0) for b in BROWS_MALE]+
          [(b,assemble(args.assets,brow='f_'+b),0,0) for b in BROWS_FEMALE],cols=4)
    sheet(args.out/'scars.png','Portrait-only scar overlays / actual exported shallow relief',
          [(s,assemble(args.assets,hair=None,scar=s),0,0) for s in
           ['cheek_slash','brow_notch','nose_bridge','chin_split']],cols=4)
    print(args.out.resolve())


if __name__=='__main__': main()
