"""Entry point for `python -m motecloud_cli`."""

import sys
from motecloud_cli._core import main

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
