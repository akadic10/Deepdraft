"""Resolve retained art-approval paths to the current production layout.

Offline audits and migration commands only; runtime resources use explicit paths.
Historical reports keep their original names and fingerprints.
"""


def current_path(value):
    value = value.replace('/faceted/', '/')
    for old, new in (
        ('assets/animals/', 'assets/models/animals/'),
        ('assets/dwarves/', 'assets/models/characters/dwarves/'),
        ('assets/models/details/', 'assets/models/rocks/'),
        ('assets/models/flora/vegetation/', 'assets/models/flora/'),
    ):
        value = value.replace(old, new)
    return value
