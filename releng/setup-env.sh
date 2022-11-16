#!/usr/bin/env bash

releng_path=`dirname $0`

build_os=$($releng_path/detect-os.sh)
build_arch=$($releng_path/detect-arch.sh)
build_os_arch=$build_os-$build_arch
build_machine=$build_os_arch

if [ -n "$ROBBER_HOST" ]; then
  host_os=$(echo -n $ROBBER_HOST | cut -f1 -d"-")
  host_arch=$(echo -n $ROBBER_HOST | cut -f2 -d"-")
  host_variant=$(echo -n $ROBBER_HOST | cut -f3 -d"-")
  host_machine=$ROBBER_HOST
else
  host_os=$build_os
  host_arch=$build_arch
  host_variant=""
  host_machine=$host_os-$host_arch
fi
host_os_arch=$host_os-$host_arch

case $host_os in
  macos|ios|watchos|tvos)
    host_system=darwin
    ;;
  *)
    host_system=$host_os
    ;;
esac
case $host_arch in
  i?86)
    host_cpu_family=x86
    host_cpu=i686
    host_endian=little
    ;;
  arm)
    host_cpu_family=arm
    host_cpu=armv7
    host_endian=little
    ;;
  armbe8)
    host_cpu_family=arm
    host_cpu=armv6
    host_endian=big
    ;;
  armeabi)
    host_cpu_family=arm
    host_cpu=armv7eabi
    host_endian=little
    ;;
  armhf)
    host_cpu_family=arm
    host_cpu=armv7hf
    host_endian=little
    ;;
  arm64|arm64e|arm64eoabi)
    host_cpu_family=aarch64
    host_cpu=aarch64
    host_endian=little
    ;;
  mips)
    host_cpu_family=mips
    host_cpu=mips
    host_endian=big
    ;;
  mipsel)
    host_cpu_family=mips
    host_cpu=mips
    host_endian=little
    ;;
  mips64)
    host_cpu_family=mips64
    host_cpu=mips64
    host_endian=big
    ;;
  mips64el)
    host_cpu_family=mips64
    host_cpu=mips64
    host_endian=little
    ;;
  s390x)
    host_cpu_family=s390x
    host_cpu=s390x
    host_endian=big
    ;;
  *)
    host_cpu_family=$host_arch
    host_cpu=$host_arch
    host_endian=little
    ;;
esac
b_lundef=true

case $ROBBER_ASAN in
  yes|no)
    enable_asan=$ROBBER_ASAN
    ;;
  *)
    enable_asan=no
    ;;
esac

if which curl &>/dev/null; then
  download_command="curl --progress-bar"
elif which wget &>/dev/null; then
  download_command="wget -O - -q"
else
  echo "Please install curl or wget: required for downloading prebuilt dependencies." > /dev/stderr
  exit 1
fi

if [ -z "$ROBBER_HOST" ]; then
  echo "Assuming host is $host_machine Set ROBBER_HOST to override."
fi

if [ "$host_os" == "android" ]; then
  ndk_required=25
  if [ -n "$ANDROID_NDK_ROOT" ] && [ -e "$ANDROID_NDK_ROOT" ]; then
    if [ -f "$ANDROID_NDK_ROOT/source.properties" ]; then
      ndk_installed_version=$(grep Pkg.Revision "$ANDROID_NDK_ROOT/source.properties" | awk '{ split($NF, v, "."); print v[1]; }')
    else
      ndk_installed_version=$(cut -f1 -d" " "$ANDROID_NDK_ROOT/RELEASE.TXT")
    fi
    if [ "$ndk_installed_version" -ne "$ndk_required" ]; then
      (
        echo ""
        echo "Unsupported NDK version $ndk_installed_version. Please install NDK r$ndk_required."
        echo ""
        echo "Robber's SDK - the prebuilt dependencies snapshot - was compiled against r$ndk_required,"
        echo "and as we have observed the NDK ABI breaking over time, we ask that you install"
        echo "the exact same version."
        echo ""
        echo "However, if you'd like to take the risk and use a different NDK, you may edit"
        echo "releng/setup-env.sh and adjust the ndk_required variable. Make sure you use"
        echo "a newer NDK, and not an older one. Note that the proper solution is to rebuild"
        echo "the SDK against your NDK by running:"
        echo "  make -f Makefile.sdk.mk ROBBER_HOST=android-arm"
        echo "If you do this and it works well for you, please let us know so we can upgrade"
        echo "the upstream SDK version."
        echo ""
      ) > /dev/stderr
      exit 1
    fi
  else
    echo "ANDROID_NDK_ROOT must be set to the location of your r$ndk_required NDK." > /dev/stderr
    exit 1
  fi
fi

if [ "$host_os" == "qnx" ]; then
  if [ ! -n "$QNX_HOST" ]; then
    echo "You need to specify QNX_HOST and QNX_TARGET"
    exit 1
  fi
fi

if [ -n "$ROBBER_ENV_NAME" ]; then
  robber_env_name_prefix=${ROBBER_ENV_NAME}-
else
  robber_env_name_prefix=
fi

pushd $releng_path/../ > /dev/null
ROBBER_ROOT=`pwd`
popd > /dev/null
ROBBER_BUILD="${ROBBER_BUILD:-$ROBBER_ROOT/build}"
ROBBER_RELENG="$ROBBER_ROOT/releng"
ROBBER_PREFIX="${ROBBER_PREFIX:-$ROBBER_BUILD/${ROBBER_ENV_NAME:-robber}-${host_machine}}"
ROBBER_TOOLROOT="$ROBBER_BUILD/${robber_env_name_prefix}toolchain-${build_machine}"
ROBBER_SDKROOT="$ROBBER_BUILD/${robber_env_name_prefix}sdk-${host_machine}"

if [ -n "$ROBBER_TOOLCHAIN_VERSION" ]; then
  toolchain_version=$ROBBER_TOOLCHAIN_VERSION
else
  toolchain_version=$(grep "robber_deps_version =" "$ROBBER_RELENG/deps.mk" | awk '{ print $NF }')
fi
if [ -n "$ROBBER_SDK_VERSION" ]; then
  sdk_version=$ROBBER_SDK_VERSION
else
  sdk_version=$(grep "robber_deps_version =" "$ROBBER_RELENG/deps.mk" | awk '{ print $NF }')
fi
if [ "$enable_asan" == "yes" ]; then
  sdk_version="$sdk_version-asan"
fi

if ! grep -Eq "^$toolchain_version\$" "$ROBBER_TOOLROOT/VERSION.txt" 2>/dev/null; then
  rm -rf "$ROBBER_TOOLROOT"
  mkdir -p "$ROBBER_TOOLROOT"

  filename=toolchain-$build_machine.tar.bz2

  local_toolchain=$ROBBER_BUILD/_$filename
  if [ -f $local_toolchain ]; then
    echo -e "Deploying local toolchain \\033[1m$(basename $local_toolchain)\\033[0m..."
    tar -C "$ROBBER_TOOLROOT" -xjf $local_toolchain || exit 1
  else
    echo -e "Downloading and deploying toolchain for \\033[1m$build_machine\\033[0m..."
    $download_command "https://build.robber.re/deps/$toolchain_version/$filename" | tar -C "$ROBBER_TOOLROOT" -xjf -
    if [ $? -ne 0 ]; then
      echo ""
      echo "Bummer. It seems we don't have a prebuilt toolchain for your system."
      echo ""
      echo "Please go ahead and build it yourself:"
      echo "$ make -f Makefile.toolchain.mk"
      echo ""
      echo "Afterwards just retry and the toolchain will get picked up automatically."
      echo ""
      exit 2
    fi
  fi

  for template in $(find $ROBBER_TOOLROOT -name "*.robber.in"); do
    target=$(echo $template | sed 's,\.robber\.in$,,')
    cp -a "$template" "$target"
    sed \
      -e "s,@ROBBER_TOOLROOT@,$ROBBER_TOOLROOT,g" \
      -e "s,@ROBBER_RELENG@,$ROBBER_RELENG,g" \
      "$template" > "$target"
  done
fi

if [ "$ROBBER_ENV_SDK" != 'none' ] && ! grep -Eq "^$sdk_version\$" "$ROBBER_SDKROOT/VERSION.txt" 2>/dev/null; then
  rm -rf "$ROBBER_SDKROOT"
  mkdir -p "$ROBBER_SDKROOT"

  filename=sdk-$host_machine.tar.bz2

  local_sdk=$ROBBER_BUILD/$filename
  if [ -f $local_sdk ]; then
    echo -e "Deploying local SDK \\033[1m$(basename $local_sdk)\\033[0m..."
    tar -C "$ROBBER_SDKROOT" -xjf $local_sdk || exit 1
  else
    echo -e "Downloading and deploying SDK for \\033[1m$host_machine\\033[0m..."
    $download_command "https://build.robber.re/deps/$sdk_version/$filename" | tar -C "$ROBBER_SDKROOT" -xjf - 2> /dev/null
    if [ $? -ne 0 ]; then
      echo ""
      echo "Bummer. It seems we don't have a prebuilt SDK for your system."
      echo ""
      echo "Please go ahead and build it yourself:"
      echo "$ make -f Makefile.sdk.mk"
      echo ""
      echo "Afterwards just retry and the SDK will get picked up automatically."
      echo ""
      exit 3
    fi
  fi

  for template in $(find $ROBBER_SDKROOT -name "*.robber.in"); do
    target=$(echo $template | sed 's,\.robber\.in$,,')
    cp -a "$template" "$target"
    sed \
      -e "s,@ROBBER_SDKROOT@,$ROBBER_SDKROOT,g" \
      -e "s,@ROBBER_RELENG@,$ROBBER_RELENG,g" \
      "$template" > "$target"
  done
fi

if [ -f "$ROBBER_SDKROOT/lib/c++/libc++.a" ] && [ $host_os != watchos ]; then
  have_static_libcxx=yes
else
  have_static_libcxx=no
fi

cc=()
cxx=()
objc=()
objcxx=()

ar=()
nm=()
ranlib=()
strip=()

readelf=()
objcopy=()
objdump=()

libtool=()
install_name_tool=()
otool=()
codesign=()
lipo=()

common_flags=()
c_like_flags=()
linker_flags=()
linker_flavor=""

cxx_like_flags=()
cxx_link_flags=()

platform_properties=()

flags_to_args ()
{
  local var_name=$1
  local flags=$2
  if [ -n "$flags" ]; then
    echo "'$(echo "$flags" | sed "s/ /', '/g")'"
  else
    echo ""
  fi
}

array_to_args ()
{
  local var_name=$1
  local elements=$2
  local separator="', '"
  if shift 2; then
    printf -v $var_name %s "'$elements${@/#/$separator}'"
  else
    printf -v $var_name ""
  fi
}

read_toolchain_variable ()
{
  local result_var_name=$1
  local env_var_name=$2
  local fallback_value=$3

  if [ $host_machine == $build_machine ] && [ "$ROBBER_CROSS" == yes ]; then
    local contextual_env_var_name=${env_var_name}_FOR_BUILD
  else
    local contextual_env_var_name=${env_var_name}
  fi

  eval "$result_var_name=(${!contextual_env_var_name:-$fallback_value})"
}

mkdir -p "$ROBBER_BUILD"

case $host_os in
  linux)
    if [ -n "$ROBBER_LIBC" ]; then
      robber_libc=$ROBBER_LIBC
    else
      case $host_arch in
        arm|armbe8)
          robber_libc=gnueabi
          ;;
        armhf)
          robber_libc=gnueabihf
          ;;
        mips64*)
          robber_libc=gnuabi64
          ;;
        *)
          robber_libc=gnu
          ;;
      esac
    fi

    case $host_arch in
      x86)
        common_flags+=("-m32" "-march=pentium4")
        c_like_flags+=("-mfpmath=sse" "-mstackrealign")
        toolprefix="/usr/bin/"
        ;;
      x86_64)
        common_flags+=("-m64")
        toolprefix="/usr/bin/"
        ;;
      arm)
        common_flags+=("-march=armv5t")
        toolprefix="arm-linux-$robber_libc-"

        host_cpu="armv5t"
        ;;
      armbe8)
        common_flags+=("-march=armv6" "-mbe8")
        toolprefix="armeb-linux-$robber_libc-"

        host_cpu="armv6t"
        ;;
      armhf)
        common_flags+=("-march=armv7-a")
        toolprefix="arm-linux-$robber_libc-"

        host_cpu="armv7a"
        ;;
      arm64)
        common_flags+=("-march=armv8-a")
        toolprefix="aarch64-linux-$robber_libc-"
        ;;
      mips)
        common_flags+=("-march=mips1" "-mfp32")
        toolprefix="mips-linux-$robber_libc-"

        host_cpu="mips1"
        ;;
      mipsel)
        common_flags+=("-march=mips1" "-mfp32")
        toolprefix="mipsel-linux-$robber_libc-"

        host_cpu="mips1"
        ;;
      mips64)
        common_flags+=("-march=mips64r2" "-mabi=64")
        toolprefix="mips64-linux-$robber_libc-"

        host_cpu="mips64r2"
        ;;
      mips64el)
        common_flags+=("-march=mips64r2" "-mabi=64")
        toolprefix="mips64el-linux-$robber_libc-"

        host_cpu="mips64r2"
        ;;
      s390x)
        common_flags+=("-march=z10" "-m64")
        toolprefix="s390x-linux-$robber_libc-"
        ;;
    esac

    read_toolchain_variable cc CC ${toolprefix}gcc
    read_toolchain_variable cxx CXX ${toolprefix}g++
    eval cc=($cc)
    eval cxx=($cxx)

    read_toolchain_variable ar AR ${toolprefix}ar
    read_toolchain_variable nm NM ${toolprefix}nm
    read_toolchain_variable ranlib RANLIB ${toolprefix}ranlib
    read_toolchain_variable strip STRIP ${toolprefix}strip
    strip+=("--strip-all")

    read_toolchain_variable readelf READELF ${toolprefix}readelf
    read_toolchain_variable objcopy OBJCOPY ${toolprefix}objcopy
    read_toolchain_variable objdump OBJDUMP ${toolprefix}objdump

    c_like_flags+=("-ffunction-sections" "-fdata-sections")
    linker_flags+=("-static-libgcc" "-Wl,-z,noexecstack" "-Wl,--gc-sections")

    cxx_link_flags+=("-static-libstdc++")

    read_toolchain_variable ld LD ${toolprefix}ld
    if "${ld[@]}" --version | grep -q "GNU gold"; then
      linker_flags+=("-Wl,--icf=all")
      linker_flavor=gold
    fi

    ;;
  macos|ios|watchos|tvos)
    if [ "$host_arch" == "arm64eoabi" ]; then
      export DEVELOPER_DIR="$XCODE11/Contents/Developer"
    fi

    xcrun="xcrun"
    if [ "$build_machine" == "macos-arm64" ]; then
      if xcrun --show-sdk-path 2>&1 | grep -q "compatible arch"; then
        xcrun="arch -x86_64 xcrun"
      fi
    fi

    case $host_os in
      macos)
        case $host_arch in
          arm64|arm64e)
            apple_os_minver="11.0"
            ;;
          *)
            apple_os_minver="10.9"
            ;;
        esac

        apple_sdk="macosx"
        if [ $host_arch = x86 ] && [ -n "$MACOS_X86_SDK_ROOT" ]; then
          apple_sdk_path="$MACOS_X86_SDK_ROOT"
        else
          apple_sdk_path="$($xcrun --sdk $apple_sdk --show-sdk-path)"
        fi

        ;;
      ios)
        apple_os_minver="8.0"

        case "$host_variant" in
          "")
            apple_sdk="iphoneos"
            ;;
          simulator)
            apple_sdk="iphonesimulator"
            ;;
          *)
            echo "Unsupported iOS variant: $host_variant" > /dev/stderr
            exit 1
            ;;
        esac

        if [ -z "$IOS_SDK_ROOT" ]; then
          apple_sdk_path="$($xcrun --sdk $apple_sdk --show-sdk-path)"
        else
          apple_sdk_path="$IOS_SDK_ROOT"
        fi

        ;;
      watchos)
        apple_os_minver="9.0"

        case "$host_variant" in
          "")
            apple_sdk="watchos"
            ;;
          simulator)
            apple_sdk="watchsimulator"
            ;;
          *)
            echo "Unsupported watchOS variant: $host_variant" > /dev/stderr
            exit 1
            ;;
        esac

        if [ -z "$WATCHOS_SDK_ROOT" ]; then
          apple_sdk_path="$($xcrun --sdk $apple_sdk --show-sdk-path)"
        else
          apple_sdk_path="$WATCHOS_SDK_ROOT"
        fi

        ;;
      tvos)
        apple_os_minver="13.0"

        case "$host_variant" in
          "")
            apple_sdk="appletvos"
            ;;
          simulator)
            apple_sdk="appletvsimulator"
            ;;
          *)
            echo "Unsupported tvOS variant: $host_variant" > /dev/stderr
            exit 1
            ;;
        esac

        if [ -z "$TVOS_SDK_ROOT" ]; then
          apple_sdk_path="$($xcrun --sdk $apple_sdk --show-sdk-path)"
        else
          apple_sdk_path="$TVOS_SDK_ROOT"
        fi

        ;;
    esac

    case $host_arch in
      x86)
        host_clang_arch=i386
        ;;
      arm)
        host_clang_arch=armv7
        ;;
      arm64eoabi)
        host_clang_arch=arm64e
        ;;
      *)
        host_clang_arch=$host_arch
        ;;
    esac

    cc=("$($xcrun --sdk $apple_sdk -f clang)")
    cxx=("$($xcrun --sdk $apple_sdk -f clang++)" "-stdlib=libc++")
    objc=("${cc[@]}")
    objcxx=("${cxx[@]}")

    ar=("$($xcrun --sdk $apple_sdk -f ar)")
    nm=("$($xcrun --sdk $apple_sdk -f llvm-nm)")
    ranlib=("$($xcrun --sdk $apple_sdk -f ranlib)")
    libtool=("$($xcrun --sdk $apple_sdk -f libtool)")
    strip=("$($xcrun --sdk $apple_sdk -f strip)" "-Sx")

    install_name_tool=("$($xcrun --sdk $apple_sdk -f install_name_tool)")
    otool=("$($xcrun --sdk $apple_sdk -f otool)")
    codesign=("$($xcrun --sdk $apple_sdk -f codesign)")
    lipo=("$($xcrun --sdk $apple_sdk -f lipo)")

    common_flags+=("-target" "$host_clang_arch-apple-$host_os$apple_os_minver${host_variant:+-$host_variant}" "-isysroot" "$apple_sdk_path")

    linker_flags+=("-Wl,-dead_strip")
    if [ $host_arch = "macos-x86" ]; then
      # Suppress linker warning about x86 being a deprecated architecture.
      linker_flags+=("-Wl,-w")
    fi

    if [ $have_static_libcxx = yes ] && [ $enable_asan = no ]; then
      cxx_like_flags+=("-nostdinc++" "-isystem$ROBBER_SDKROOT/include/c++")
      cxx_link_flags+=("-nostdlib++" "-L$ROBBER_SDKROOT/lib/c++" "-lc++" "-lc++abi")
    fi

    ;;
  android)
    android_build_os=$(echo ${build_os} | sed 's,^macos$,darwin,')
    case $build_os in
      macos)
        # NDK does not yet support Apple Silicon.
        android_build_arch=x86_64
        ;;
      linux)
        # Linux NDK only supports x86_64.
        android_build_arch=x86_64
        ;;
      *)
        android_build_arch=${build_arch}
        ;;
    esac
    android_toolroot="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/${android_build_os}-${android_build_arch}"
    host_clang_version=$(ls -1 "$android_toolroot/lib64/clang/" | grep -E "^[0-9]" | head -1)

    host_tooltriplet=""
    host_cxxlibs="c++_static c++abi"
    case $host_arch in
      x86)
        android_api=19
        android_abi="x86"
        android_target="i686-none-linux-android${android_api}"
        host_clang_arch="i386"
        host_compiler_triplet="i686-linux-android"
        host_cxxlibs="$host_cxxlibs android_support"
        common_flags+=("-march=pentium4")
        c_like_flags+=("-mfpmath=sse" "-mstackrealign")
        ;;
      x86_64)
        android_api=21
        android_abi="x86_64"
        android_target="x86_64-none-linux-android${android_api}"
        host_clang_arch="x86_64"
        host_compiler_triplet="x86_64-linux-android"
        ;;
      arm)
        android_api=19
        android_abi="armeabi-v7a"
        android_target="armv7-none-linux-androideabi${android_api}"
        host_clang_arch="arm"
        host_compiler_triplet="armv7a-linux-androideabi"
        host_tooltriplet="arm-linux-androideabi"
        host_cxxlibs="$host_cxxlibs android_support"
        common_flags+=("-march=armv7-a" "-mfloat-abi=softfp" "-mfpu=vfpv3-d16")
        linker_flags+=("-Wl,--fix-cortex-a8")
        ;;
      arm64)
        android_api=21
        android_abi="arm64-v8a"
        android_target="aarch64-none-linux-android${android_api}"
        host_clang_arch="aarch64"
        host_compiler_triplet="aarch64-linux-android"
        ;;
    esac

    if [ -z "$host_tooltriplet" ]; then
      host_tooltriplet="$host_compiler_triplet"
    fi

    elf_cleaner=$ROBBER_TOOLROOT/bin/termux-elf-cleaner

    cc_wrapper=$ROBBER_BUILD/${ROBBER_ENV_NAME:-robber}-${host_machine}-clang
    sed \
        -e "s,@driver@,${android_toolroot}/bin/clang,g" \
        -e "s,@ndkroot@,$ANDROID_NDK_ROOT,g" \
        -e "s,@toolroot@,$android_toolroot,g" \
        -e "s,@target@,$android_target,g" \
        -e "s,@tooltriplet@,$host_tooltriplet,g" \
        -e "s,@api@,$android_api,g" \
        -e "s,@abi@,$android_abi,g" \
        -e "s,@clang_version@,$host_clang_version,g" \
        -e "s,@clang_arch@,$host_clang_arch,g" \
        -e "s,@cxxlibs@,$host_cxxlibs,g" \
        -e "s,@elf_cleaner@,$elf_cleaner,g" \
        "$ROBBER_RELENG/driver-wrapper-android.sh.in" > "$cc_wrapper"
    chmod +x "$cc_wrapper"

    cxx_wrapper=$ROBBER_BUILD/${ROBBER_ENV_NAME:-robber}-${host_machine}-clang++
    sed \
        -e "s,@driver@,${android_toolroot}/bin/clang++,g" \
        -e "s,@ndkroot@,$ANDROID_NDK_ROOT,g" \
        -e "s,@toolroot@,$android_toolroot,g" \
        -e "s,@target@,$android_target,g" \
        -e "s,@tooltriplet@,$host_tooltriplet,g" \
        -e "s,@api@,$android_api,g" \
        -e "s,@abi@,$android_abi,g" \
        -e "s,@clang_version@,$host_clang_version,g" \
        -e "s,@clang_arch@,$host_clang_arch,g" \
        -e "s,@cxxlibs@,$host_cxxlibs,g" \
        -e "s,@elf_cleaner@,$elf_cleaner,g" \
        "$ROBBER_RELENG/driver-wrapper-android.sh.in" > "$cxx_wrapper"
    chmod +x "$cxx_wrapper"

    cc=("$cc_wrapper")
    cxx=("$cxx_wrapper")

    ar=("${android_toolroot}/bin/llvm-ar")
    nm=("${android_toolroot}/bin/llvm-nm")
    ranlib=("${android_toolroot}/bin/llvm-ranlib")
    strip=("${android_toolroot}/bin/llvm-strip" "--strip-all")

    readelf=("${android_toolroot}/bin/llvm-readelf")
    objcopy=("${android_toolroot}/bin/llvm-objcopy")
    objdump=("${android_toolroot}/bin/llvm-objdump")

    c_like_flags+=("-DANDROID" "-ffunction-sections" "-fdata-sections")
    linker_flags+=("-Wl,-z,relro" "-Wl,-z,noexecstack" "-Wl,--gc-sections")

    if [ $android_api -lt 24 ]; then
      cxx_like_flags+=("-D_LIBCPP_HAS_NO_OFF_T_FUNCTIONS")
    fi

    ;;
  freebsd)
    toolprefix="/usr/bin/"

    read_toolchain_variable cc CC ${toolprefix}clang
    read_toolchain_variable cxx CXX ${toolprefix}clang++

    read_toolchain_variable ar AR ${toolprefix}ar
    read_toolchain_variable nm NM ${toolprefix}nm
    read_toolchain_variable ranlib RANLIB ${toolprefix}ranlib
    read_toolchain_variable strip STRIP ${toolprefix}strip
    strip+=("--strip-all")

    read_toolchain_variable readelf READELF ${toolprefix}readelf
    read_toolchain_variable objcopy OBJCOPY ${toolprefix}objcopy

    c_like_flags+=("-ffunction-sections" "-fdata-sections")
    linker_flags+=("-Wl,--gc-sections")

    b_lundef=false

    ;;
  qnx)
    case $host_arch in
      x86)
        qnx_host=i486-pc-nto-qnx6.6.0
        qnx_sysroot=$QNX_TARGET/x86

        common_flags+=("-march=i686")
        ;;
      armeabi)
        qnx_host=arm-unknown-nto-qnx6.5.0eabi
        qnx_sysroot=$QNX_TARGET/armle-v7

        common_flags+=("-march=armv7-a" "-mno-unaligned-access")

        host_cpu="armv7"
        ;;
      arm)
        qnx_host=arm-unknown-nto-qnx6.5.0
        qnx_sysroot=$QNX_TARGET/armle

        common_flags+=("-march=armv6" "-mno-unaligned-access")

        host_cpu="armv6"
        ;;
      *)
        echo "Unsupported QNX architecture" > /dev/stderr
        exit 1
        ;;
    esac

    qnx_toolchain_dir=$QNX_HOST/usr/bin
    qnx_toolchain_prefix=$qnx_toolchain_dir/$qnx_host

    PATH="$qnx_toolchain_dir:$PATH"

    cc=("$qnx_toolchain_prefix-gcc")
    cxx=("$qnx_toolchain_prefix-g++")

    ar=("$qnx_toolchain_prefix-ar")
    nm=("$qnx_toolchain_prefix-nm")
    ranlib=("$qnx_toolchain_prefix-ranlib")
    strip=("$qnx_toolchain_prefix-strip" "--strip-all")

    readelf=("$qnx_toolchain_prefix-readelf")
    objcopy=("$qnx_toolchain_prefix-objcopy")
    objdump=("$qnx_toolchain_prefix-objdump")

    common_flags+=("--sysroot=$qnx_sysroot")
    c_like_flags+=("-ffunction-sections" "-fdata-sections")
    linker_flags+=("-static-libgcc" "-Wl,--gc-sections" "-L$(dirname $qnx_sysroot/lib/gcc/4.8.3/libstdc++.a)")

    cxx_link_flags+=("-static-libstdc++" )

    ;;
esac

case $host_os_arch in
  linux-armhf|ios-arm|android-arm)
    c_like_flags+=("-mthumb")
    ;;
esac

if [ "$ROBBER_ENV_SDK" != 'none' ]; then
  c_like_flags+=("-include" "$ROBBER_ROOT/build/robber-version.h")
fi

if [ -n "$ROBBER_EXTRA_LDFLAGS" ]; then
  linker_flags+=("$ROBBER_EXTRA_LDFLAGS")
fi

vala_api_version=$(ls -1 "$ROBBER_TOOLROOT/share" | grep "vala-" | cut -f2 -d"-")
valac=("$ROBBER_TOOLROOT/bin/valac-$vala_api_version" "--target-glib=2.56")
valac+=("--vapidir=$ROBBER_PREFIX/share/vala/vapi")
if [ "$ROBBER_ENV_SDK" != 'none' ]; then
  valac+=("--vapidir=$ROBBER_SDKROOT/share/vala/vapi")
fi
valac+=("--vapidir=$ROBBER_TOOLROOT/share/vala-$vala_api_version/vapi")

pkg_config_wrapper=$ROBBER_BUILD/${ROBBER_ENV_NAME:-robber}-${host_machine}-pkg-config
case $host_os in
  freebsd)
    libdatadir=libdata
    ;;
  *)
    libdatadir=lib
    ;;
esac
pkg_config="$ROBBER_TOOLROOT/bin/pkg-config"
pkg_config_flags="--static"
pkg_config_path="$ROBBER_PREFIX/$libdatadir/pkgconfig"
if [ "$ROBBER_ENV_NAME" == 'robber_gir' ]; then
  pkg_config_path="$(pkg-config --variable pc_path pkg-config):$pkg_config_path"
  pkg_config_flags=""
fi
if [ "$ROBBER_ENV_SDK" != 'none' ]; then
  pkg_config_flags=" $pkg_config_flags --define-variable=robber_sdk_prefix=$ROBBER_SDKROOT"
  pkg_config_path="$pkg_config_path:$ROBBER_SDKROOT/$libdatadir/pkgconfig"
fi
(
  echo "#!/bin/sh"
  echo "export PKG_CONFIG_PATH=\"$pkg_config_path\""
  echo "exec \"$pkg_config\" $pkg_config_flags \"\$@\""
) > "$pkg_config_wrapper"
chmod 755 "$pkg_config_wrapper"

env_rc=${ROBBER_BUILD}/${ROBBER_ENV_NAME:-robber}-env-${host_machine}.rc

qemu=""
if [ $host_machine != $build_machine ] && [ -n "$ROBBER_QEMU_SYSROOT" ]; then
  case $host_arch in
    arm|armeabi|armhf)
      qemu=qemu-arm
      ;;
    armbe8)
      qemu=qemu-armeb
      ;;
    arm64)
      qemu=qemu-aarch64
      ;;
    *)
      qemu=qemu-$host_arch
      ;;
  esac
fi

env_path_sdk=""
if [ "$ROBBER_ENV_SDK" != 'none' ]; then
  native_dir="$ROBBER_SDKROOT/bin/$build_machine"

  candidates=("$native_dir")
  case $build_machine in
    linux-x86_64)
      candidates+=("$ROBBER_SDKROOT/bin/linux-x86")
      ;;
    macos-arm64)
      candidates+=("$ROBBER_SDKROOT/bin/macos-arm64e")
      candidates+=("$ROBBER_SDKROOT/bin/macos-x86_64")
      ;;
    macos-arm64e)
      candidates+=("$ROBBER_SDKROOT/bin/macos-arm64")
      candidates+=("$ROBBER_SDKROOT/bin/macos-x86_64")
      ;;
  esac

  for candidate in "${candidates[@]}"; do
    if [ -d "$candidate" ]; then
      env_path_sdk="$candidate"
      break
    fi
  done

  if [ -z "$env_path_sdk" ] && [ -n "$qemu" ]; then
    v8_mksnapshot="$ROBBER_SDKROOT/bin/${host_os_arch}/v8-mksnapshot-${host_os_arch}"
    if [ -f "$v8_mksnapshot" ]; then
      mkdir -p "$native_dir"
      wrapper_script="$native_dir/v8-mksnapshot-${host_os_arch}"
      (
        echo "#!/bin/sh"
        echo "\"$qemu\" -L \"$ROBBER_QEMU_SYSROOT\" \"$v8_mksnapshot\" \"\$@\""
      ) > "$wrapper_script"
      chmod +x "$wrapper_script"
      env_path_sdk="$native_dir"
    fi
  fi
fi

(
  echo "export PATH=\"${env_path_sdk:+"$env_path_sdk:"}${ROBBER_TOOLROOT}/bin:\$PATH\""
) > $env_rc

machine_file=${ROBBER_BUILD}/${ROBBER_ENV_NAME:-robber}-${host_machine}.txt

array_to_args raw_cc "${cc[@]}"
array_to_args raw_cxx "${cxx[@]}"
array_to_args raw_objc "${objc[@]}"
array_to_args raw_objcxx "${objcxx[@]}"
array_to_args raw_valac "${valac[@]}"

array_to_args raw_ar "${ar[@]}"
array_to_args raw_nm "${nm[@]}"
array_to_args raw_ranlib "${ranlib[@]}"
array_to_args raw_libtool "${libtool[@]}"
array_to_args raw_strip "${strip[@]}"

array_to_args raw_readelf "${readelf[@]}"
array_to_args raw_objcopy "${objcopy[@]}"
array_to_args raw_objdump "${objdump[@]}"

array_to_args raw_install_name_tool "${install_name_tool[@]}"
array_to_args raw_otool "${otool[@]}"
array_to_args raw_codesign "${codesign[@]}"
array_to_args raw_lipo "${lipo[@]}"

array_to_args raw_common_flags "${common_flags[@]}"
array_to_args raw_c_like_flags "${c_like_flags[@]}"
array_to_args raw_linker_flags "${linker_flags[@]}"

array_to_args raw_cxx_like_flags "${cxx_like_flags[@]}"
array_to_args raw_cxx_link_flags "${cxx_link_flags[@]}"

(
  echo "[constants]"
  echo "common_flags = [$raw_common_flags]"
  echo "c_like_flags = [$raw_c_like_flags]"
  echo "linker_flags = [$raw_linker_flags]"
  echo "cxx_like_flags = [$raw_cxx_like_flags]"
  echo "cxx_link_flags = [$raw_cxx_link_flags]"
  echo ""
  echo "[binaries]"
  echo "c = [$raw_cc] + common_flags"
  echo "cpp = [$raw_cxx] + common_flags"
  if [ -n "$raw_objc" ]; then
    echo "objc = [$raw_objc] + common_flags"
  fi
  if [ -n "$raw_objcxx" ]; then
    echo "objcpp = [$raw_objcxx] + common_flags"
  fi
  if [ -n "$linker_flavor" ]; then
    echo "c_ld = '$linker_flavor'"
    echo "cpp_ld = '$linker_flavor'"
    [ -n "$objc" ] && echo "objc_ld = '$linker_flavor'"
    [ -n "$objcxx" ] && echo "objcpp_ld = '$linker_flavor'"
  fi
  echo "vala = [$raw_valac]"

  echo "ar = [$raw_ar]"
  echo "nm = [$raw_nm]"
  echo "ranlib = [$raw_ranlib]"
  echo "strip = [$raw_strip]"

  if [ -n "$raw_readelf" ]; then
    echo "readelf = [$raw_readelf]"
  fi
  if [ -n "$raw_objcopy" ]; then
    echo "objcopy = [$raw_objcopy]"
  fi
  if [ -n "$raw_objdump" ]; then
    echo "objdump = [$raw_objdump]"
  fi

  if [ -n "$raw_libtool" ]; then
    echo "libtool = [$raw_libtool]"
  fi
  if [ -n "$raw_install_name_tool" ]; then
    echo "install_name_tool = [$raw_install_name_tool]"
  fi
  if [ -n "$raw_otool" ]; then
    echo "otool = [$raw_otool]"
  fi
  if [ -n "$raw_codesign" ]; then
    echo "codesign = [$raw_codesign]"
  fi
  if [ -n "$raw_lipo" ]; then
    echo "lipo = [$raw_lipo]"
  fi

  echo "pkgconfig = '$pkg_config_wrapper'"
  if [ -n "$qemu" ]; then
    echo "exe_wrapper = ['$qemu', '-L', '$ROBBER_QEMU_SYSROOT']"
  fi
  echo ""
  echo "[built-in options]"
  echo "c_args = c_like_flags"
  echo "cpp_args = c_like_flags + cxx_like_flags"
  if [ -n "$objc" ]; then
    echo "objc_args = c_like_flags"
  fi
  if [ -n "$objcxx" ]; then
    echo "objcpp_args = c_like_flags + cxx_like_flags"
  fi
  echo "c_link_args = linker_flags"
  echo "cpp_link_args = linker_flags + cxx_link_flags"
  if [ -n "$objc" ]; then
    echo "objc_link_args = linker_flags"
  fi
  if [ -n "$objcxx" ]; then
    echo "objcpp_link_args = linker_flags + cxx_link_flags"
  fi
  echo "b_lundef = $b_lundef"
  if [ $enable_asan = yes ]; then
    echo "b_sanitize = 'address'"
  fi
  echo ""
  echo "[properties]"
  if [ $host_os != $build_os ]; then
    echo "needs_exe_wrapper = true"
    echo ""
  fi
  if [ ${#platform_properties[@]} -gt 0 ]; then
    echo ""
    for prop in "${platform_properties[@]}"; do
      echo "$prop"
    done
  fi
  echo ""
  echo "[host_machine]"
  echo "system = '$host_system'"
  echo "cpu_family = '$host_cpu_family'"
  echo "cpu = '$host_cpu'"
  echo "endian = '$host_endian'"
) > $machine_file
