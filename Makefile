SPCOMP ?= spcomp64
SCRIPTING := addons/sourcemod/scripting
rwildcard = $(foreach d,$(wildcard $(1)/*),$(call rwildcard,$(d),$(2)) $(filter $(2),$(d)))
sources = $(call rwildcard,$(1),%.sp)
INCS := $(call rwildcard,$(SCRIPTING)/include,%.inc)

all: $(patsubst %.sp,%.smx,$(wildcard $(SCRIPTING)/gokz-*.sp))

# A plugin also depends on the sources in its own folder and every include.
# sources hides its % from this rule, where make would read it as the stem.
.SECONDEXPANSION:
$(SCRIPTING)/%.smx: $(SCRIPTING)/%.sp $$(call sources,$(SCRIPTING)/$$*) $(INCS)
	$(SPCOMP) $< -i$(SCRIPTING)/include -o$@
