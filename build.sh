#!/usr/bin/env bash
# ============================================================
# Start kernel build script
# ============================================================
set -e

# ----- Config: adjust these to match your setup -----
KERNEL_DIR="$(pwd)"          # assumes this script runs from inside the kernel source tree

# If the "out" folder already exists, assume the toolchain and setup have already been configured.
# previously performed -> skip all setup steps and build directly
# (incremental build, out/not deleted so that the build is faster).
if [ -d "$KERNEL_DIR/out" ]; then
  SKIP_SETUP=1
  echo "==> 'out' folder detected, skipping setup stage (timezone/deps/toolchain)"
else
  SKIP_SETUP=0
fi

if [ "$SKIP_SETUP" -eq 0 ]; then
  # ===== ⏰ Prepare timezone =====
  echo "==> Setting timezone to Asia/Delhi"
  sudo rm -f /etc/localtime
  sudo ln -s /usr/share/zoneinfo/Asia/Delhi /etc/localtime

  # ===== 📦 Install Dependencies =====
  echo "==> Installing dependencies"
  sudo apt update -y
  sudo apt install -y bc cpio flex bison aptitude git python-is-python3 tar aria2 perl wget curl lz4 libssl-dev

  # ===== 🔧 Clone Toolchains =====
  echo "==> Cloning toolchains"
  if [ -f "$KERNEL_DIR/clang/bin/clang" ]; then
    echo "Clang toolchain already exists, skipping..."
  else
    mkdir -p clang && cd clang
    curl -LO "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman"
    chmod a+x antman
    ./antman -S
    ./antman --patch=glibc
    cd "$KERNEL_DIR"
  fi

  if [ -d "$KERNEL_DIR/gcc64" ]; then
    echo "gcc64 toolchain already exists, skipping..."
  else
    git clone https://github.com/greenforce-project/gcc-arm64 -b main --depth=1 gcc64
  fi

  if [ -d "$KERNEL_DIR/gcc32" ]; then
    echo "gcc32 toolchain already exists, skipping..."
  else
    git clone https://github.com/greenforce-project/gcc-arm -b main --depth=1 gcc32
  fi

else
  echo "==> The setup step is skipped. Ensure that the \`clang/\`, \`gcc64/\`, and \`gcc32/\` folders are complete from the previous build."
fi

# ===== ⚙️ Setup Environment =====
echo "==> Setting up environment variables"
export BUILD_TIME="$(TZ=Asia/Jakarta date '+%d%m%Y-%H%M')"
export CLANG_PATH="$KERNEL_DIR/clang"
export GCC64_PATH="$KERNEL_DIR/gcc64"
export GCC32_PATH="$KERNEL_DIR/gcc32"

# ===== 📅 Set BUILD DATE =====
export BUILD_DATE="\"$(TZ=Asia/Delhi date '+%b %d %Y')\""

# ===== 🛠️ Build Kernel =====
echo "==> Building kernel"
export ARCH=arm64
export PATH="$CLANG_PATH/bin:$GCC64_PATH/bin:$GCC32_PATH/bin:$PATH"
export KBUILD_BUILD_USER=NRanjan-17
export KBUILD_BUILD_HOST=MiniBox
export KBUILD_COMPILER_STRING="$CLANG_PATH/clang"
export CFLAGS_EXTRA="-DBUILD_DATE=$BUILD_DATE"

# defconfig hanya perlu dijalankan sekali (saat out/ belum ada).
# Kalau out/ sudah ada, make akan otomatis melakukan incremental build
# berdasarkan .config yang sudah tersimpan di dalamnya.
if [ "$SKIP_SETUP" -eq 0 ]; then
  make O=out ARCH=arm64 mido_defconfig
fi

make -j"$(nproc --all)" O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang \
  CLANG_TRIPLE="$CLANG_PATH/aarch64-linux-gnu-" \
  CROSS_COMPILE="$GCC64_PATH/bin/aarch64-elf-" \
  CROSS_COMPILE_ARM32="$GCC32_PATH/bin/arm-none-eabi-"

# ===== Clone AnyKernel3 =====
echo "==> Packaging with AnyKernel3"
if [ -d "$KERNEL_DIR/AnyKernel" ]; then
  echo "AnyKernel folder already exists, updating..."
  rm -rf "$KERNEL_DIR/AnyKernel"
fi
git clone https://github.com/mido-nxt/Anykernel3.git -b 4.9 AnyKernel
cp out/arch/arm64/boot/Image.gz-dtb AnyKernel/

# ===== Zip kernel =====
cd AnyKernel
ZIP_NAME="HYPERKERNEL${GIT_REF_NAME}-${BUILD_TIME}.zip"
zip -r "../${ZIP_NAME}" *
cd "$KERNEL_DIR"

echo "==> Done. Flashable zip is in $KERNEL_DIR/${ZIP_NAME}"

# ===== ☁️ Upload ke Gofile (tanpa login/token) =====
echo "==> Uploading ${ZIP_NAME} to Gofile..."

# Ambil server upload terbaik yang direkomendasikan Gofile
GOFILE_SERVER="$(curl -s https://api.gofile.io/servers | grep -o '"name":"[a-zA-Z0-9]*"' | head -n1 | cut -d'"' -f4)"

if [ -z "$GOFILE_SERVER" ]; then
  echo "!! Failed to retrieve Gofile server; upload cancelled."
else
  UPLOAD_RESPONSE="$(curl -s -F "file=@${ZIP_NAME}" "https://${GOFILE_SERVER}.gofile.io/uploadFile")"
  echo "$UPLOAD_RESPONSE"

  DOWNLOAD_PAGE="$(echo "$UPLOAD_RESPONSE" | grep -o '"downloadPage":"[^"]*"' | cut -d'"' -f4 | sed 's/\\//\//g')"

  if [ -n "$DOWNLOAD_PAGE" ]; then
    echo "==> Upload successful! Download link: $DOWNLOAD_PAGE"
  else
    echo "!! Upload failed or the Gofile response format has changed; check UPLOAD_RESPONSE above."
  fi
fi
