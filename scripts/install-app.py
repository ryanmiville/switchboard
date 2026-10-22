"""Verify a staged app, then replace the whole installed bundle atomically on macOS."""

import ctypes
import os
import pathlib
import subprocess
import sys
import tempfile


def verify(app):
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app)],
        check=True,
    )


def exchange(first, second):
    # Darwin's RENAME_SWAP exchanges directories on the same volume in one operation.
    rename = ctypes.CDLL(None, use_errno=True).renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(os.fsencode(first), os.fsencode(second), 0x00000002) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(second))


def install(source, destination):
    source = source.resolve(strict=True)
    destination = destination.absolute()
    if not source.is_dir() or source == destination.resolve():
        raise ValueError("Choose an app bundle and a separate installation destination.")
    if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
        raise ValueError("The installation destination must be a directory, not a file or symlink.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".switchboard-install-", dir=destination.parent) as folder:
        staged = pathlib.Path(folder) / destination.name
        subprocess.run(["/usr/bin/ditto", str(source), str(staged)], check=True)
        verify(staged)
        replacing = destination.exists()
        if replacing:
            exchange(staged, destination)
        else:
            staged.rename(destination)
        try:
            verify(destination)
        except BaseException:
            if replacing:
                exchange(staged, destination)
            else:
                destination.rename(staged)
            raise
    print(f"Installed and verified: {destination}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: install-app.py SOURCE.app DESTINATION.app")
    install(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
