##############################################################################
# Rules
##############################################################################

.SUFFIXES: .tpl.lua .lua

COMPILE.filepp  = $(FILEPP) -kc '--fpp:' $(DFLAGS) $(IFLAGS) -I$(WEB_ROOT) -DWEB_ROOT=$(WEB_ROOT)

# rule to convert .html.in to .html
.html.in.html:
	@$(ECHO) Processing $<
	$(COMPILE.filepp) $< -o $@
	$(HTMLTIDY) $@

# rule to convert 1.in to .1 (man page)
.1.in.1:
	@$(ECHO) Processing $<
	$(COMPILE.filepp) $< -o $@

.tpl.lua.lua:
	@$(ECHO) Processing $<
	$(COMPILE.filepp) $< -o $@
	luacheck $@

# rule to convert lsm.in to .lsm
.lsm.in.lsm:
	@$(ECHO) Processing $<
	$(COMPILE.filepp) $< -o $@

##############################################################################
# End of file
##############################################################################
