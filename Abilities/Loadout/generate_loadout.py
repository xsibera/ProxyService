"""Builds the Loadout package (ReplicatedStorage.Loadout: the module and its Remote):

  python3 generate_loadout.py    -> build/Loadout.rbxmx
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "Shared"))
import rbxbuild as B  # noqa: E402


def loadout_folder():
    return B.folder("Loadout", [
        B.module("Loadout", os.path.join(HERE, "src", "Loadout.luau")),
        B.item("RemoteEvent", "Remote"),
    ])


def build():
    folder = loadout_folder()
    B.write([folder], os.path.join(HERE, "build", "Loadout.rbxmx"))
    return folder


if __name__ == "__main__":
    build()
