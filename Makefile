.PHONY: test test-lua lint fmt fmt-check

test: test-lua

test-lua:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/spec { minimal_init = 'tests/minimal_init.lua' }"

# Auto-format Lua sources in place.
fmt:
	stylua lua tests

# Verify Lua sources are already stylua-clean (CI uses this).
fmt-check:
	stylua --check lua tests

# Static analysis. Picks up .luacheckrc.
lint:
	luacheck lua tests
