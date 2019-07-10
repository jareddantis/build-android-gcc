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

# Initial setup
function setup_variables() {
    # Start of script
    START=$(date +%s)
    BUILD_DATE=$(TZ=UTC date +%Y%m%d)

    # Check if running on macOS
    PLATFORM=$(uname)
    [[ ${PLATFORM} != "Darwin" ]] && die "This script is for macOS only."

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
    CONFIGURATION=(
        "--host=x86_64-apple-darwin"
        "--build=x86_64-apple-darwin"
        "--with-pkgversion='${GCC}-${BUILD_DATE}'"
        "--with-gcc-version=${GCC}"
        "--with-binutils-version=${BINUTILS}"
        "--with-gmp-version=${GMP}"
        "--with-mpfr-version=${MPFR}"
        "--with-mpc-version=${MPC}"
        "--with-cloog-version=${CLOOG}"
        "--with-isl-version=${ISL}"
        "--without-gdb"
        "--disable-multilib"
        "--disable-werror"
        "--disable-option-checking"
        "--disable-docs"
        "--disable-shared"
        "--enable-threads"
        "--enable-ld=default"
        "--with-host-libstdcxx='-static-libstdc++ -Wl,-lstdc++ -lm'"
    )
    CORES=$(sysctl -a | grep machdep.cpu | grep core_count | awk '{print $2}')
    THREADS=$(sysctl -a | grep machdep.cpu | grep thread_count | awk '{print $2}')
    JOBS="-j$(((CORES * THREADS) / 2))"
}

# Parse parameters
function parse_parameters() {
    while [[ ${#} -ge 1 ]]; do
        case "${1}" in
            # REQUIRED FLAGS
            "-a"|"--arch") shift && ARCH=${1} ;;

            # OPTIONAL FLAGS
            "-nu"|"--no-update") NO_UPDATE=true ;;
            "-p"|"--package") shift && COMPRESSION=${1} ;;
            "-V"|"--verbose") VERBOSE=true ;;

            # HELP!
            "-h"|"--help") help_menu; exit ;;
        esac

        shift
    done

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

# Setup source folders and build folders
function setup_env() {
    # Require GNU make, sed, bison, m4
    [[ -z "$(command -v gmake)" ]] && die "GNU Make not found in your $PATH. Please install it first."
    [[ ! -d /usr/local/opt/gnu-sed ]] && die "Please install gnu-sed with Homebrew first."
    [[ ! -d /usr/local/opt/bison ]] && die "Please install bison with Homebrew first."
    [[ ! -d /usr/local/opt/m4 ]] && die "Please install m4 with Homebrew first."

    INSTALL=${ROOT}/out/${TARGET}
    SYSROOT=${ROOT}/sysroot/arch-${ARCH_TYPE}
    CONFIGURATION+=(
        "--target=${TARGET}"
        "--prefix=${INSTALL}"
        "--with-sysroot=${SYSROOT}"
        "--with-gxx-include-dir=${SYSROOT}/c++"
    )

    export PATH="/usr/local/opt/gnu-sed/libexec/gnubin:/usr/local/opt/bison/bin:/usr/local/opt/m4/bin:${INSTALL}/bin:${PATH}"
    mkdir -p "${INSTALL}" "${ROOT}/out/build"
}

# Clean up from a previous compilation
function clean_up() {
    header "CLEANING UP"
    rm -rf "${ROOT}/out/build"
    [[ -d "${ROOT}/out/build" ]] && die "Failed to remove 'out/build'. Please check if you have proper permissions."
    echo "Clean up successful!"
}

function download_sources() {
    if [[ -z ${NO_UPDATE} ]]; then
        [[ ! -d ${ROOT}/sources ]] && mkdir "${ROOT}/sources"
        cd "${ROOT}/sources" || die "Failed to create sources directory!"

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
        [[ ! -f ${ROOT}/sources/mpfr-${MPFR}.tar.xz ]] && die "MPFR tarball does not exist, please run without '-nu'/'--no-update'."
        [[ ! -f ${ROOT}/sources/gmp-${GMP}.tar.xz ]] && die "GMP tarball does not exist, please run without '-nu'/'--no-update'."
        [[ ! -f ${ROOT}/sources/mpc-${MPC}.tar.gz ]] && die "MPC tarball does not exist, please run without '-nu'/'--no-update'."
    fi
}

function extract() {
    if [[ -d ${ROOT}/${2} ]]; then
        echo "${2}/ already exists, skipping..."
    else
        case "${1}" in
            *.gz) UNPACK=gzip ;;
            *.xz) UNPACK=xz ;;
        esac
        mkdir -p "${ROOT}/${2}"
        ${UNPACK} -d < "${1}" | tar -xC "${ROOT}/${2}" --strip-components=1
    fi
}

# Extract tarballs to their proper locations
function extract_sources() {
    header "EXTRACTING DOWNLOADED TARBALLS"

    extract mpfr-${MPFR}.tar.xz mpfr/mpfr-${MPFR}
    extract gmp-${GMP}.tar.xz gmp/gmp-${GMP}
    extract mpc-${MPC}.tar.gz mpc/mpc-${MPC}
}

# Update git repos
function update_repos() {
    if [[ -z ${NO_UPDATE} ]]; then
        header "UPDATING SOURCES"
        (
            cd "${ROOT}/cloog/cloog-${CLOOG}" || die "CLooG directory does not exist!"
            ./get_submodules.sh
            git -C isl checkout isl-${ISL}
        )
    fi
}

# Build toolchain
function build_tc() {
    header "BUILDING TOOLCHAIN"
    cd "${ROOT}/out/build" || die "Build folder does not exist!"

    if [[ ${TARGET} = "arm-eabi" ]]; then
        "${ROOT}/build/configure" "${CONFIGURATION[@]}" --program-transform-name='s&^&arm-eabi-&'
    else
        "${ROOT}/build/configure" "${CONFIGURATION[@]}"
    fi

    gmake ${JOBS} || die "Error while building toolchain!" -n
    gmake install ${JOBS} || die "Error while building toolchain!" -n
}

# Package toolchain
function package_tc() {
    if [[ -n ${COMPRESSION} ]]; then
        PACKAGE="${ROOT}/out/${TARGET}-${GCC}-${BUILD_DATE}.tar.${COMPRESSION}"

        header "PACKAGING TOOLCHAIN"

        echo "Target file: out/${PACKAGE}"

        case "${COMPRESSION}" in
            "gz")
                echo "Packaging with GZIP..."
                GZ_OPT=-9 tar -c --use-compress-program=gzip -f "${PACKAGE}" "${INSTALL}" ;;
            "xz")
                echo "Packaging with XZ..."
                XZ_OPT=-9 tar -c --use-compress-program=xz -f "${PACKAGE}" "${INSTALL}" ;;
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

trap 'die "Manually aborted!" -n' SIGINT SIGTERM
setup_variables
parse_parameters "${@}"
setup_env
clean_up
download_sources
extract_sources
update_repos
build_tc
package_tc
ending_info
