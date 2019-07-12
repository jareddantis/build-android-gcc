# build-android-gcc

This repo contains a manifest and build script to build Android GCC toolchains for arm and arm64 on Linux and macOS.

If you're looking to build toolchains for non-Android targets, check out @nathanchance's [script,](https://github.com/nathanchance/build-tools-gcc) from which this build script originated.


## System requirements

To build a toolchain, you will need the following:

+ A decent processor and RAM
  + Intel i5 and 8GB of RAM or more is preferred
+ Free disk space
  + The source code will take a bit over 1 GB once synced, and
  + Each clean build will take up around 1 GB on macOS and around 2-3 GB on Linux.
+ Core developer packages (see instructions for [Linux](#installing-required-packages-linux) and [macOS](#installing-required-packages-macos))

In my testing, compilation is still possible, albeit painfully slow, with 4GB RAM and a:

+ Haswell i5 (base-model 2014 MacBook Air, macOS 10.14.5, full build + xz packaging: **45 minutes**)
+ Core 2 Duo P8600 (Vista-era ASUS laptop, Arch Linux, full build + xz packaging: **50 minutes**)


## Installing required packages (Linux)

+ **Arch Linux:** `sudo pacman -Sy base-devel`
  + No need to do this if you `pacstrap`ped with `base-devel`
+ **Ubuntu:**

```bash
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install --no-install-recommends flex bison ncurses-dev texinfo gcc gperf patch libtool automake g++ libncurses5-dev gawk  expat libexpat1-dev python-all-dev binutils-dev libgcc1:i386 bc libcloog-isl-dev libcap-dev autoconf libgmp-dev build-essential gcc-multilib g++-multilib pkg-config libmpc-dev libmpfr-dev autopoint gettext txt2man liblzma-dev libssl-dev libz-dev xz-utils pigz repo git
```

After installing packages, create and enter a folder in which we will do our work:
```bash
mkdir tc-build
cd tc-build
```


## Installing required packages (macOS)

Install the Xcode Command Line Tools first:
```bash
xcode-select --install
```

**If you are on macOS 10.14 or newer,** install the system headers as well:
```bash
# Replace 10.14 below with your macOS version.
open /Library/Developer/CommandLineTools/Packages/macOS_SDK_headers_for_macOS_10.14.pkg
```

Install [Homebrew](https://brew.sh), and finally install the required developer packages:
```bash
brew update
brew install repo git gnu-sed bison m4 make pigz xz
```

Create and mount a disk image for storage:
```bash
# You can change the size spec to anything you want, but I'd recommend at least 10g (10 GB).
# The disk image we will create here is sparse, which means that it will grow as necessary,
# instead of taking up 10 GB from the beginning.
hdiutil create -type SPARSE -size 10g -fs 'Case-sensitive Journaled HFS+' -volname tc-build tc-build.sparseimage

# Mount it
hdiutil attach tc-build.sparseimage

# Then cd into it
cd /Volumes/tc-build
```


## Using the script

Once you have set up your environment, run the following:

```bash
repo init -u git://github.com/jareddantis/build-android-gcc -b linaro-7.x --depth 1
repo sync
./compile.sh -h
```

The printout will show you how to run the script.


## After compilation

Once it is done building, you will have a folder with the compiled toolchain as well as either a tar.xz or tar.gz file (depending on if you passed -p or not).

If the toolchains are compressed, move them into your directory of choice and run the following commands:

For xz compression:

```bash
tar -xvf <toolchain_name>.tar.xz --strip-components=1
```

For gz compression:

```bash
tar -xvzf <toolchain_name>.tar.gz --strip-components=1
```

After that, point your cross compiler to the proper file and compile! This is
an easy shortcut for kernels (when run in the directory you extracted the
toolchain in):

```bash
# for arm64
export CROSS_COMPILE=$(pwd)/bin/aarch64-linux-gnu-

# for arm
export CROSS_COMPILE=$(pwd)/bin/arm-linux-androideabi-
```


## Pull requests/issues

If you have any issues with this script, feel free to open an issue!

Pull requests are more than welcome as well. However, there is a particular coding style that should be followed:

+ All variables are uppercased and use curly braces: ```${VARIABLE}``` instead of ```$variable```
+ Four spaces for indents
+ Double brackets and single equal sign for string comparisons in if blocks: ```if [[ ${VARIABLE} = "yes" ]]; then```

Additionally, please be sure to run your change through shellcheck.net (either copy and paste the script there or download the binary and run `shellcheck build`).


## Credits/thanks

+ [nathanchance](https://github.com/nathanchance), [frap129](https://github.com/frap129), and [MSF-Jarvis](https://github.com/MSF-Jarvis): For the original version of the `build` script
+ [jareddantis](https://github.com/jareddantis): For this version of `build` called `compile.sh`
