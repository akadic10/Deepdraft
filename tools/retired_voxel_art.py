"""Guard retained historical builders from recreating obsolete production art.

Their geometry helpers remain importable for historical source inspection.
Use the production generators listed in docs/60_asset_creation/63_shared_art_standard.md.
"""

def stop():
    raise SystemExit('This voxel-art command is retired. Use generate_tree_pilot.py, '
                     'generate_surface_vegetation.py, generate_ground_stones.py, '
                     'generate_dwarf_faceted.py, generate_wildlife_faceted.py, '
                     'generate_furniture_faceted.py, generate_fire_faceted.py or generate_items_faceted.py. '
                     'Historical comparisons are retained in the dated art reports.')
