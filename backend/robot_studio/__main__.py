"""``python -m robot_studio`` entry used by PyInstaller and console runs."""

import multiprocessing

from robot_studio.main import main

if __name__ == "__main__":
    multiprocessing.freeze_support()
    main()
