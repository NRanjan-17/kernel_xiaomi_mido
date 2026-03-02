#!/bin/bash
set -euo pipefail

# Put the correct file name here (must exist in arch/arm64/configs/)
DEFCONFIG="mido_defconfig"

export ARCH=arm64
export SUBARCH=arm64

mkdir -p out

# Generate .config from defconfig
make -j"$(nproc --all)" O=out "${DEFCONFIG}"

# Convert current .config -> minimal defconfig
make -j"$(nproc --all)" O=out savedefconfig

# Replace the repo defconfig with regenerated one
cp -af out/defconfig "arch/arm64/configs/${DEFCONFIG}"

git add "arch/arm64/configs/${DEFCONFIG}"
git commit -m "arm64: configs: ${DEFCONFIG}: regenerate"
echo -e "\nSuccessfully regenerated defconfig at ${DEFCONFIG}"