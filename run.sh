ROOT=$(pwd)
if [ $DEBUG ]; then
 qemu-system-aarch64 \
        -machine virt \
        -cpu cortex-a53 \
        -m 512M \
        -kernel $ROOT/root/Image \
	-gdb tcp::1234 \
	-S \
	-nographic
else
 qemu-system-aarch64 \
        -machine virt \
        -cpu cortex-a53 \
        -m 512M \
        -kernel $ROOT/root/Image \
	-nographic
fi
