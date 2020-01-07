all:
	/Volumes/Development/Development/pony/ponyc/build/release/ponyc -d -o ./build/ ./flow
	time ./build/flow

test:
	/Volumes/Development/Development/pony/ponyc/build/release/ponyc -V=0 -d -o ./build/ ./flow
	./build/flow