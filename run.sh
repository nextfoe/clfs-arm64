ROOT=$(pwd)
qemu-system-aarch64 \
        -machine virt \
        -cpu cortex-a53 \
        -m 512M \
        -kernel $ROOT/root/Image \
	-nographic
