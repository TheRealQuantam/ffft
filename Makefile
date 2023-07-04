.PHONY: all clean dir run

ifeq ($(BUILD_BASE_ROM),)
BUILD_BASE_ROM := $(PATCH_ROM)
endif

SRCDIR := $(CURDIR)
STEM := $(notdir $(CURDIR))
BHOPDIR := bhop
BUILDDIR := build\$(GAME_PRE)ft
CFG_NAME := $(STEM).cfg
ROM_NAME := $(GAME_PRE)ft.nes
DBG_NAME := $(GAME_PRE)ft.dbg
DELTA_NAME := $(GAME_PRE)ft.xdelta
IPS_NAME := $(GAME_PRE)ft.ips

# Assembler files, for building out the banks
ROOT_ASM_FILES := $(wildcard $(SRCDIR)/*.asm)
BHOP_ASM_FILES := $(BHOPDIR)/bhop.s
O_FILES := \
  $(patsubst $(SRCDIR)/%.asm,$(BUILDDIR)/%.o,$(ROOT_ASM_FILES)) \
  $(patsubst $(BHOPDIR)/%.s,$(BUILDDIR)/%.o,$(BHOP_ASM_FILES))

MAKE_FT_ROM := python ../makeftrom/makeftrom.py
FTCFG_NAME := $(FTCFG_PRE)ft.ftcfg
DEMO_ROM_NAME := $(GAME_PRE)ftdemo.nes
DEMO_DELTA_NAME := $(GAME_PRE)ftdemo.xdelta
DEMO_IPS_NAME := $(GAME_PRE)ftdemo.ips

ifeq ($(DEMO_CFG_NAME),)
DEMO_CFG_NAME := democfg.json5
endif

all: dir $(ROM_NAME) $(DELTA_NAME) $(IPS_NAME) $(DEMO_ROM_NAME) $(DEMO_DELTA_NAME) $(DEMO_IPS_NAME)

dir:
	-@mkdir -p $(BUILDDIR)

clean:
	-@rm -rf build
	-@rm -f $(ROM_NAME)
	-@rm -f $(DBG_NAME)

run: dir $(ROM_NAME)
	rusticnes-sdl $(ROM_NAME)

$(DELTA_NAME): $(ROM_NAME)
#	Requires xdelta3 from https://www.romhacking.net/utilities/928/ renamed to xdelta3.exe
	xdelta3 -e -9 -I 0 -f -s "$(PATCH_ROM)" $< $@
	
$(IPS_NAME): $(ROM_NAME)
#	Requires Lunar IPS 1.03 from https://fusoya.eludevisibility.org/lips/index.html
	"Lunar IPS.exe" -CreateIPS $@ "$(PATCH_ROM)" $<
	
$(ROM_NAME): $(CFG_NAME) $(O_FILES)
	ld65 -vm -m $(BUILDDIR)/map.txt -Ln $(BUILDDIR)/labels.txt --dbgfile $(DBG_NAME) -o $@ $(value LINK_OPTS) -C $^

$(BUILDDIR)/%.o: $(SRCDIR)/%.asm $(BUILD_BASE_ROM)
	@echo .define SRC_ROM "$(BUILD_BASE_ROM)" > $(BUILDDIR)/build.inc
	ca65 -g -I $(BUILDDIR) -I $(BHOPDIR)/bhop -l $@.lst -o $@ $(value COMPILE_OPTS) $<

$(BUILDDIR)/%.o: $(BHOPDIR)/%.s
	ca65 -g -l $@.lst -o $@ $(value BHOP_COMPILE_OPTS) $<

$(DEMO_ROM_NAME): $(ROM_NAME) $(FTCFG_NAME) $(DEMO_CFG_NAME)
	$(MAKE_FT_ROM) --ftcfg $(FTCFG_NAME) $(DEMO_CFG_NAME) --input-rom $(ROM_NAME) --output-rom $(DEMO_ROM_NAME) --debug
	
$(DEMO_DELTA_NAME): $(DEMO_ROM_NAME)
#	Requires xdelta3 from https://www.romhacking.net/utilities/928/ renamed to xdelta3.exe
	xdelta3 -e -9 -I 0 -f -s $(ROM_NAME) $< $@
	
$(DEMO_IPS_NAME): $(DEMO_ROM_NAME)
#	Requires Lunar IPS 1.03 from https://fusoya.eludevisibility.org/lips/index.html
#	"Lunar IPS.exe" -CreateIPS $@ $(ROM_NAME) $<
	"Lunar IPS.exe" -CreateIPS $@ $(PATCH_ROM) $<
	