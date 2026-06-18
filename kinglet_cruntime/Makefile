# kinglet_cruntime — permanent C ABI substrate for native Kinglet binaries.
# heap/   = portable wire-format + heap objects (platform-independent).
# platform/ = OS shims (io/fs/sys) — the only platform-dependent layer.
# Produces libkinglet_rt.a, linked into every native --emit-ll binary.

CXX ?= c++
CXXFLAGS ?= -std=c++17 -O2 -I.

SRCS := kinglet_rt_main.cc $(wildcard heap/*.cc) $(wildcard platform/*.cc)
OBJS := $(SRCS:.cc=.o)
LIB := libkinglet_rt.a

all: $(LIB)

$(LIB): $(OBJS)
	ar rcs $@ $(OBJS)

%.o: %.cc
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(LIB)

.PHONY: all clean
