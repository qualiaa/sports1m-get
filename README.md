# Sports-1M Get

A tool for automatically downloading files from the
[Sports-1M](https://cs.stanford.edu/people/karpathy/deepvideo/) dataset one at a
time, and saving short random clips from them. Intended to allow you to download
Sports-1M without breaking the memory bank.

## Usage

From the repository root, run

    ./sports1m-get.sh

It respects the following environment variables (with defaults)

Variable               | Default
-----------------------|--------------------
 `SPORTS1M_DIR`        | "sports-1m-dataset"
 `OUTPUT_DIR`          | "data"
 `SECONDS_PER_CLIP`    | 2
 `N_CLIPS`             | 5
 `SCRIPTS`             | "scripts"
 `URL_LIST_DIR`        | "${SPORTS1M_DIR}/original"
 `URL_LIST_SUFFIX`     | "_partition.txt"
 `OUTPUT_VIDEO_SCALE`  | "171:128"
 `ERRFILE`             | "err.log"
 `TMPDIR`              | $(mktemp -d)
 `MAX_FILES`           | *null*

## Dependencies

* ffmpeg
* Python 3
* Perl (any version)
* [you-get](https://github.com/soimort/you-get)

## Installation

Simply clone the repository and initialise the sports-1m-dataset submodule:

    git clone https://github.com/qualiaa/sports1m-get
    cd sports1m-get
    git submodule init
    git submodule update

## Licence

`sports1m-get` is licensed under the GNU General Public Licence v3.0.
