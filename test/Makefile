simple.hex: simple
	xxd simple > simple.hex

simple: simple.o
	ld -arch arm64 \
	   -e _main \
	   -lSystem \
	   -syslibroot `xcrun --show-sdk-path` \
	   -o simple simple.o

simple.o: simple.s
	as -arch arm64 -o simple.o simple.s
