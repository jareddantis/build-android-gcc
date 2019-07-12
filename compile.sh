#!/usr/bin/env bash
# shellcheck disable=SC1117
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2016-2018 USBhost
# Copyright (C) 2016-2017 Joe Maples
# Copyright (C) 2017-2018 Nathan Chancellor
# Copyright (C) 2019      Jared Dantis
#
# GCC cross compiler compilation script

#############
# FUNCTIONS #
#############

# Easy alias for escape codes
function echo() {
    command echo -e "${@}"
}

# Help menu function
function help_menu() {
    echo
    echo "${BOLD}OVERVIEW:${RST} Build a gcc toolchain"
    echo
    echo "${BOLD}USAGE:${RST} ${0} <options>"
    echo
    echo "${BOLD}EXAMPLE:${RST} ${0} -a arm"
    echo
    echo "${BOLD}REQUIRED PARAMETERS:${RST}"
    echo "  -a  | --arch:        Possible values: arm, arm-android, or arm64. This is the toolchain's target architecture."
    echo
    echo "${BOLD}OPTIONAL PARAMETERS:${RST}"
    echo "  -nt | --no-tmpfs:    Do not use tmpfs for building (useful if you don't have much RAM)."
    echo "  -nu | --no-update:   Do not update the downloaded components before building (useful if you have slow internet)."
    echo "  -p  | --package:     Possible values: gz or xz. Compresses toolchain after build."
    echo "  -V  | --verbose:     Make script print all output, not just errors and the ending information"
    echo
}

# Prints a formatted header to let the user know what's being done
function header() {
    [[ "${*}" =~ "--no-first-echo" ]] || echo
    # shellcheck disable=SC2034
    echo "${RED}====$(for i in $(seq ${#1}); do echo "=\c"; done)===="
    echo "==  ${1}  =="
    # shellcheck disable=SC2034
    echo "====$(for i in $(seq ${#1}); do echo "=\c"; done)====${RST}"
    [[ "${*}" =~ "--no-second-echo" ]] || echo
}

# Prints an error in bold red
function die() {
    [[ -z ${VERBOSE} ]] && exec 1>&5 2>&6
    echo ""
    echo "${RED}${1}${RST}"
    [[ "${*}" =~ "-n" ]] && echo
    [[ "${*}" =~ "-h" ]] && help_menu
    exit 1
}

# Prints a warning in bold yellow
function warn() {
    echo ""
    echo "${YLW}${1}${RST}"
    [[ "${*}" =~ "-n" ]] && echo
}

# Formats the time for the end
function format_time() {
    MINS=$(((${2} - ${1}) / 60))
    SECS=$(((${2} - ${1}) % 60))
    if [[ ${MINS} -ge 60 ]]; then
        HOURS=$((MINS / 60))
        MINS=$((MINS % 60))
    fi

    if [[ ${HOURS} -eq 1 ]]; then
        TIME_STRING+="1 HOUR, "
    elif [[ ${HOURS} -ge 2 ]]; then
        TIME_STRING+="${HOURS} HOURS, "
    fi

    if [[ ${MINS} -eq 1 ]]; then
        TIME_STRING+="1 MINUTE"
    else
        TIME_STRING+="${MINS} MINUTES"
    fi

    if [[ ${SECS} -eq 1 && -n ${HOURS} ]]; then
        TIME_STRING+=", AND 1 SECOND"
    elif [[ ${SECS} -eq 1 && -z ${HOURS} ]]; then
        TIME_STRING+=" AND 1 SECOND"
    elif [[ ${SECS} -ne 1 && -n ${HOURS} ]]; then
        TIME_STRING+=", AND ${SECS} SECONDS"
    elif [[ ${SECS} -ne 1 && -z ${HOURS} ]]; then
        TIME_STRING+=" AND ${SECS} SECONDS"
    fi

    echo "${TIME_STRING}"
}

# Check if user needs to enter sudo password or not
function check_sudo() {
    echo
    echo "Checking if sudo is available, please enter your password if a prompt appears!"
    if ! sudo -v 2>/dev/null; then
        warn "Sudo is not available! Disabling the option for tmpfs..." -n
        NO_TMPFS=true
    fi
}

# Initial setup
function setup_variables() {
    # Start of script
    START=$(date +%s)
    BUILD_DATE=$(TZ=UTC date +%Y%m%d)

    # Set multithread and config flags per platform
    PLATFORM=$(uname)
    if [[ ${PLATFORM} = "Darwin" ]]; then
        CORES=$(sysctl -a | grep machdep.cpu | grep core_count | awk '{print $2}')
        THREADS=$(sysctl -a | grep machdep.cpu | grep thread_count | awk '{print $2}')
        MK="gmake -j$(((CORES * THREADS) / 2))"
        HOST_PLATFORM="x86_64-apple-darwin"
        CONFIGURATION=( "--with-host-libstdcxx='-static-libstdc++ -Wl,-lstdc++ -lm'" )

        # Disable tmpfs
        warn "tmpfs not available on Mac, disabling..."
        NO_TMPFS=true
    else
        THREADS="$(nproc --all)"
        MK="make -j${THREADS}"
        HOST_PLATFORM="x86_64-linux-gnu"
        CONFIGURATION=( "--with-host-libstdcxx='-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm'" )
    fi

    # Build root
    ROOT=${PWD}

    # Colors
    BOLD="\033[1m"
    RED="\033[01;31m"
    RST="\033[0m"
    YLW="\033[01;33m"

    # Binary versions
    BINUTILS="2.32"
    GCC="linaro-7.x"
    CLOOG="current"
    GMP="6.1.2"
    ISL="0.21"
    MPC="1.1.0"
    MPFR="4.0.2"

    # Configuration variables
    CONFIGURATION+=(
        "--host=${HOST_PLATFORM}"
        "--build=${HOST_PLATFORM}"
        "--with-pkgversion='${GCC}-${BUILD_DATE}'"
        "--with-gcc-version=${GCC}"
        "--with-binutils-version=${BINUTILS}"
        "--with-gmp-version=${GMP}"
        "--with-mpfr-version=${MPFR}"
        "--with-mpc-version=${MPC}"
        "--with-cloog-version=${CLOOG}"
        "--with-isl-version=${ISL}"
        "--disable-multilib"
        "--disable-werror"
        "--disable-option-checking"
        "--disable-docs"
        "--disable-shared"
        "--enable-threads"
        "--enable-ld=default"
        "--enable-graphite=yes"
    )
}

# Parse parameters
function parse_parameters() {
    while [[ ${#} -ge 1 ]]; do
        case "${1}" in
            # REQUIRED FLAGS
            "-a"|"--arch") shift && ARCH=${1} ;;

            # OPTIONAL FLAGS
            "-nt"|"--no-tmpfs") NO_TMPFS=true ;;
            "-nu"|"--no-update") NO_UPDATE=true ;;
            "-p"|"--package") shift && COMPRESSION=${1} ;;
            "-V"|"--verbose") VERBOSE=true ;;

            # HELP!
            "-h"|"--help") help_menu; exit ;;
        esac

        shift
    done

    [[ -z ${NO_TMPFS} ]] && [[ ${PLATFORM} != "Darwin" ]] && check_sudo
    [[ -z ${VERBOSE} ]] && exec 6>&2 5>&1 &>/dev/null

    # Default values
    case "${ARCH}" in
        "arm")
            TARGET="arm-eabi"
            ARCH_TYPE="arm"
            ;;
        "arm-android")
            TARGET="arm-linux-androideabi"
            ARCH_TYPE="arm"
            ;;
        "arm64")
            TARGET="aarch64-linux-android"
            ARCH_TYPE="arm64"
            ;;
        *) die "Absent or invalid arch specified!" -h ;;
    esac
}

# Unmount tmpfs
function unmount_tmpfs() {
    if [[ -z ${NO_TMPFS} ]]; then
        sudo umount -f "${ROOT}/out/build" 2>/dev/null
    fi
}

# Clean up from a previous compilation
function clean_up() {
    header "CLEANING UP"
    unmount_tmpfs
    rm -rf "${ROOT}/out"
    [[ -d "${ROOT}/out" ]] && die "Failed to remove 'out'. Please check if you have proper permissions."
    echo "Clean up successful!"
}

# Setup source folders and build folders
function setup_env() {
    [[ -z "$(command -v pigz)" ]] && die "pigz not found in your $PATH. Please install it first."

    if [[ ${PLATFORM} = "Darwin" ]]; then
        # Require GNU make, sed, bison, m4
        [[ -z "$(command -v gmake)" ]] && die "GNU Make not found in your $PATH. Please install it first."
        [[ ! -d /usr/local/opt/gnu-sed ]] && die "Please install gnu-sed with Homebrew first."
        [[ ! -d /usr/local/opt/bison ]] && die "Please install bison with Homebrew first."
        [[ ! -d /usr/local/opt/m4 ]] && die "Please install m4 with Homebrew first."
        export PATH="/usr/local/opt/gnu-sed/libexec/gnubin:/usr/local/opt/bison/bin:/usr/local/opt/m4/bin:${INSTALL}/bin:${PATH}"
    fi

    # Prepare sysroot
    INSTALL=${ROOT}/out/${TARGET}-${GCC}
    SYSROOT=${INSTALL}/arch-${ARCH_TYPE}
    mkdir -p "${INSTALL}" "${ROOT}/out/build"
    cp -Rf "${ROOT}/sysroot/arch-${ARCH_TYPE}" "${INSTALL}"
    CONFIGURATION+=(
        "--target=${TARGET}"
        "--prefix=${INSTALL}"
        "--with-sysroot=${SYSROOT}"
        "--with-gxx-include-dir=${SYSROOT}/c++"
    )

    # Prepare tmpfs
    if [[ -z ${NO_TMPFS} ]]; then
        sudo mount -t tmpfs -o rw none "${ROOT}/out/build"
    fi
}

# Download tarballs and update isl/osl
function download_sources() {
    if [[ -z ${NO_UPDATE} ]]; then
        [[ -z "$(command -v aria2c)" ]] && die "aria2c not found in your $PATH. Please install it first."
        [[ ! -d ${ROOT}/sources ]] && mkdir "${ROOT}/sources"
        cd "${ROOT}/sources" || die "Failed to create sources directory!"

        (
            cd "${ROOT}/cloog/cloog-${CLOOG}" || die "CLooG directory does not exist!"
            ./get_submodules.sh
        )

        if [[ ! -f mpfr-${MPFR}.tar.xz ]]; then
            header "DOWNLOADING MPFR"
            aria2c -x15 https://www.mpfr.org/mpfr-current/mpfr-${MPFR}.tar.xz
        fi

        if [[ ! -f gmp-${GMP}.tar.xz ]]; then
            header "DOWNLOADING GMP"
            aria2c -x15 https://ftp.gnu.org/gnu/gmp/gmp-${GMP}.tar.xz
        fi

        if [[ ! -f mpc-${MPC}.tar.gz ]]; then
            header "DOWNLOADING MPC"
            aria2c -x15 https://ftp.gnu.org/gnu/mpc/mpc-${MPC}.tar.gz
        fi
    else
        [[ ! -d ${ROOT}/sources ]] && die "Source directory does not exist, please run without '-nu'/'--no-update'."
        [[ ! -f ${ROOT}/isl/isl-${ISL}/autogen.sh ]] && die "CLooG submodules haven't been synced, please run without '-nu'/'--no-update'."
        [[ ! -f ${ROOT}/sources/mpfr-${MPFR}.tar.xz ]] && die "MPFR tarball does not exist, please run without '-nu'/'--no-update'."
        [[ ! -f ${ROOT}/sources/gmp-${GMP}.tar.xz ]] && die "GMP tarball does not exist, please run without '-nu'/'--no-update'."
        [[ ! -f ${ROOT}/sources/mpc-${MPC}.tar.gz ]] && die "MPC tarball does not exist, please run without '-nu'/'--no-update'."
    fi
}

function extract() {
    case "${1}" in
        *.gz) UNPACK=pigz ;;
        *.xz) UNPACK=xz ;;
    esac
    [[ ! -d ${ROOT}/${2} ]] && mkdir -p "${ROOT}/${2}"
    ${UNPACK} -d < "${1}" | tar -xC "${ROOT}/${2}" --strip-components=1
}

# Extract tarballs to their proper locations
function extract_sources() {
    if [[ -z ${NO_UPDATE} ]]; then
        header "EXTRACTING DOWNLOADED TARBALLS"

        extract mpfr-${MPFR}.tar.xz mpfr/mpfr-${MPFR}
        extract gmp-${GMP}.tar.xz gmp/gmp-${GMP}
        extract mpc-${MPC}.tar.gz mpc/mpc-${MPC}
    fi
}

# Build CLooG, isl, osl for graphite
function build_graphite() {
    export GMP_DIR="${ROOT}/gmp/gmp-${GMP}"
    CLOOG_DIR="${ROOT}/cloog/cloog-${CLOOG}"
    CLOOG_PREFIX="${SYSROOT}/usr"

    header "BUILDING CLOOG"
    cd "${CLOOG_DIR}" || "CLooG source folder does not exist!"
    git reset --hard
    git apply "${ROOT}/build/scripts/cloog-no-doc.patch"
    git -C isl checkout isl-${ISL} || die "Failed to checkout 'isl-${ISL}' at ${CLOOG_DIR}/isl."

    [[ ! -f ./configure ]] && ./autogen.sh
    mkdir -p "${ROOT}/out/build/cloog-current"
    cd "${ROOT}/out/build/cloog-current" || die "Build folder does not exist!"
    "${CLOOG_DIR}/configure" --prefix="${CLOOG_PREFIX}" --with-isl=bundled --with-osl=bundled --with-gmp=system
    ${MK} || die "Error while building CLooG!" -n
    ${MK} install || die "Error while building CLooG!" -n
}

# Build toolchain
function build_tc() {
    header "BUILDING TOOLCHAIN"
    cd "${ROOT}/out/build" || die "Build folder does not exist!"

    export LD_LIBRARY_PATH="${SYSROOT}/usr/lib"
    case "${ARCH}" in
        "arm") "${ROOT}/build/configure" "${CONFIGURATION[@]}" --program-transform-name='s&^&arm-eabi-&' ;;
        "arm-android") "${ROOT}/build/configure" "${CONFIGURATION[@]}" --program-transform-name='s&^&arm-linux-androideabi-&' ;;
        "arm64") "${ROOT}/build/configure" "${CONFIGURATION[@]}" --program-transform-name='s&^&aarch64-linux-android-&' ;;
        *) "${ROOT}/build/configure" "${CONFIGURATION[@]}" ;;
    esac

    ${MK} || die "Error while building toolchain!" -n
    ${MK} install || die "Error while building toolchain!" -n
}

# Package toolchain
function package_tc() {
    if [[ -n ${COMPRESSION} ]]; then
        PACKAGE="${ROOT}/out/${TARGET}-${GCC}-${BUILD_DATE}.tar.${COMPRESSION}"

        header "PACKAGING TOOLCHAIN"
        echo "Target file: ${PACKAGE}"

        case "${COMPRESSION}" in
            "gz")
                echo "Packaging with gzip..."
                GZ_OPT=-9 tar -cf "${PACKAGE}" --use-compress-program=pigz \
                    -C "${ROOT}/out" --exclude="*.DS_Store" "${TARGET}-${GCC}" ;;
            "xz")
                echo "Packaging with xz..."
                XZ_OPT="-9 --threads=${THREADS}" tar -cf "${PACKAGE}" --use-compress-program=xz \
                    -C "${ROOT}/out" --exclude="*.DS_Store" "${TARGET}-${GCC}" ;;
            *)
                die "Invalid compression specified, skipping..." ;;
        esac
    fi
}

# Ending information
function ending_info() {
    END=$(date +%s)
    COMPILED_GCC=${INSTALL}/bin/${TARGET}-gcc

    [[ -z ${VERBOSE} ]] && exec 1>&5 2>&6
    if [[ -e ${COMPILED_GCC} ]]; then
        header "BUILD SUCCESSFUL" ${VERBOSE:-"--no-first-echo"}
        echo "${BOLD}Script duration:${RST} $(format_time "${START}" "${END}")"
        echo "${BOLD}GCC version:${RST} $(${COMPILED_GCC} --version | head -n 1)"

        if [[ -n ${COMPRESSION} ]] && [[ -e ${PACKAGE} ]]; then
            echo "${BOLD}File location:${RST} ${PACKAGE}"
            echo "${BOLD}File size:${RST} $(du -h "${PACKAGE}" | awk '{print $1}')"
        else
            echo "${BOLD}Toolchain location:${RST} ${INSTALL}"
        fi
    else
        header "BUILD FAILED"
    fi

    # Alert to script end
    echo "\a"
}

trap 'unmount_tmpfs; die "Manually aborted!" -n' SIGINT SIGTERM
trap 'unmount_tmpfs' EXIT
setup_variables
parse_parameters "${@}"
clean_up
setup_env
download_sources
extract_sources
build_graphite
build_tc
package_tc
ending_info
