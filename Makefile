CXX := g++
CXXFLAGS := \
	-std=c++17 \
	-O1 \
	-fno-exceptions \
	-fno-rtti \
	-fno-strict-aliasing \
	-fno-strict-overflow \
	-fstack-protector-strong \
	-fstack-clash-protection \
	-D_FORTIFY_SOURCE=2 \
	-Wall \
	-Wextra \
	-Wpedantic \
	-Wformat -Werror=format-security
INCS := -I/opt/riscv/kernel/work/linux-headers/include
LDFLAGS := -Wl,-O1,--sort-common,-z,relro,-z,now,--as-needed

.PHONY: clean

dapp: honeypot.cpp
	$(CXX) $(CXXFLAGS) $(CXXWARNFLAGS) $(INCS) $(LDFLAGS) -o $@ $^

analyze: honeypot.cpp
	clang-tidy honeypot.cpp -- $(CXXFLAGS) $(INCS)
	$(CXX) $(CXXFLAGS) $(INCS) -fanalyzer $^

clean:
	@rm -rf dapp
