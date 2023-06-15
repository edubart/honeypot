CXX := g++
CXXFLAGS := \
	-std=c++20 \
	-O1 \
	-g \
	-fno-exceptions \
	-fno-strict-aliasing \
	-fno-strict-overflow \
	-fno-delete-null-pointer-checks \
	-fstack-protector-strong \
	-fstack-clash-protection \
	-fPIE \
	-D_FORTIFY_SOURCE=2 \
	-Wall \
	-Wextra \
	-Wpedantic
CXXWARNFLAGS := \
	-Wformat -Wformat=2 -Wformat-security -Wformat-signedness \
	-Wcast-qual -Wcast-align=strict \
	-Wconversion -Wsign-conversion -Warith-conversion \
	-Wsign-compare \
	-Wstack-protector \
	-Wtrampolines -Walloca -Wvla \
	-Warray-bounds=2 \
	-Wshift-overflow=2 -Wstringop-overflow=4 -Wstrict-overflow=4 -Wformat-overflow=2 \
	-Wlogical-op \
	-Wduplicated-cond -Wduplicated-branches \
	-Wshadow \
	-Wswitch-default \
	-Wswitch-enum
INCS := -I/opt/riscv/kernel/work/linux-headers/include
LDFLAGS := -pie -Wl,-O1,--sort-common,-z,relro,-z,now,--as-needed

.PHONY: clean

dapp: honeypot2.cpp
	$(CXX) $(CXXFLAGS) $(CXXWARNFLAGS) $(INCS) $(LDFLAGS) -o $@ $^

analyze: honeypot2.cpp
	clang-tidy honeypot2.cpp -- $(CXXFLAGS) $(INCS) -I.
	$(CXX) $(CXXFLAGS) $(INCS) -fanalyzer $^

clean:
	@rm -rf dapp
