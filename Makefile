# Build the card image and the packages from source. See build.md.
#
#   make             everything that is out of date, up to the card image
#   make -j3         the same, with U-Boot, the kernel and the FPGA design built together
#   make test        also boot the image in QEMU and check it
#   make u-boot | kernel | fpga | packages | image
#                    one task, and whatever it needs that is out of date
#   make example     the example design built on the base (fpga/example)
#   make release VERSION=v0.2
#                    the files of a release, in out/release-v0.2/
#   make NOFPGA=1    leave out the FPGA design: no Quartus needed; the image for stage 1
#
# A task is run again only when something it is made from has changed: its own files in this
# repository, or the output of a task it uses. Two things are outside the repository:
#   - The kernel's source is a branch that moves. Each run asks where the branch is, usually
#     a second's work, and the kernel is rebuilt when it has moved. With no answer within a
#     minute, the kernel already built is kept.
#   - Altera's Makefile for the FPGA design does not notice changed sources. When a file
#     under fpga/ is newer than the last build, the build tree is deleted and made again.
# To force a task, delete its output: rm -rf out/kernel, for instance.
#
# Each task's output goes to a file in work/logs/, and a line is printed as it starts and
# finishes. A task that fails prints the end of its log.

SHELL := /bin/sh
.DELETE_ON_ERROR:
.PHONY: all u-boot kernel fpga packages image test example release FORCE
all: image

# run LETTER COMMAND: run a task with its output in a log
define run
@mkdir -p work/logs; \
echo "$$(date +%T) Task $(1) started: $(2) (log: work/logs/$(1).log)"; \
if $(2) > work/logs/$(1).log 2>&1; then \
    echo "$$(date +%T) Task $(1) finished"; \
else \
    echo "$$(date +%T) Task $(1) FAILED. The end of work/logs/$(1).log:"; \
    tail -n 25 work/logs/$(1).log | sed 's/^/    /'; exit 1; \
fi
endef

# The files a task is made from: everything in its directory but its page.
src = $(shell find $(1) -type f ! -name README.md 2>/dev/null)

# ---- Task B: U-Boot, with TF-A
UBOOT := out/u-boot/u-boot.itb
SPL := out/u-boot/u-boot-spl-dtb.hex
u-boot: $(UBOOT)
$(UBOOT): $(call src,u-boot)
	$(call run,B,u-boot/build.sh)
	@touch $(UBOOT) $(SPL)
$(SPL): $(UBOOT) ;

# ---- Task K: the kernel
# work/kernel-head holds the commit the branch is at; it changes only when the branch moves.
KERNEL := out/kernel/.built
kernel: $(KERNEL)
work/kernel-head: FORCE
	@mkdir -p work; h=$$(kernel/build.sh --head); \
	if [ -n "$$h" ] && [ "$$h" != "$$(cat $@ 2>/dev/null)" ]; then echo "$$h" > $@; fi; \
	[ -f $@ ] || echo unknown > $@
$(KERNEL): $(call src,kernel) work/kernel-head
	$(call run,K,kernel/build.sh)
	@touch $@

# ---- Task F: the FPGA design
ifndef NOFPGA
FPGA := out/fpga/base/fpga.rbf
FPGA_SRC := $(filter-out fpga/example/%,$(call src,fpga))
fpga: $(FPGA)
# A changed source: start the design again from clean.
work/fpga/base.sources: $(FPGA_SRC)
	@rm -rf work/fpga/base; mkdir -p work/fpga; touch $@
$(FPGA): work/fpga/base.sources $(SPL)
	$(call run,F,fpga/build.sh)
	@touch $@
example: out/fpga/example/fpga.rbf
work/fpga/example.sources: $(FPGA_SRC) $(call src,fpga/example)
	@rm -rf work/fpga/example; mkdir -p work/fpga; touch $@
out/fpga/example/fpga.rbf: work/fpga/example.sources $(SPL)
	$(call run,example,fpga/build.sh fpga/example)
	@touch $@
IMAGE := out/sdimage/de25-nano.img
else
FPGA :=
fpga: ; @echo "NOFPGA is set: the FPGA design is left out"
IMAGE := out/sdimage/de25-nano-nofpga.img
endif

# ---- Task P: the packages
PACKAGES := out/packages/.built
packages: $(PACKAGES)
$(PACKAGES): $(call src,packages) fpga/BOOT_NAME LICENSE $(UBOOT) $(FPGA)
	$(call run,P,packages/build.sh)
	@touch $@

# ---- Task I: the card image
image: $(IMAGE)
$(IMAGE): $(filter-out sdimage/qemu-test.sh sdimage/qemu/%,$(call src,sdimage)) packages/boot/boot.cmd $(KERNEL) $(PACKAGES) $(UBOOT)
	$(call run,I,sdimage/build.sh)
	@touch $@

# ---- The test of the image in QEMU
TESTED := out/sdimage/.tested
test: $(TESTED)
$(TESTED): $(IMAGE) sdimage/qemu-test.sh $(call src,sdimage/qemu)
	$(call run,T,sdimage/qemu-test.sh $(IMAGE))
	@touch $@

# ---- The files of a release
release: $(TESTED)
	@[ -n "$(VERSION)" ] || { echo "make release VERSION=v0.2" >&2; exit 1; }
	$(call run,R,packages/release.sh $(VERSION))
	@ls -l out/release-$(VERSION)
