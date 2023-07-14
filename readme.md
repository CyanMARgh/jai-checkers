# checkers
just checkers for four, nothing fancy
`tested on compiler version 0.1.070`

# how to build
There are 3 GUI versions available: Simp (2D for now), kscurses (TUI) and raylib (3D). For any of them, in first.jai inside the top `#run {}` block, you must specify the desired one. For example:
```
...
#run {
	set_build_options_dc(.{do_output=false});
	build(.RAYLIB);
}
...
```
# extra requirements
## SIMP
nothing needed.

## Raylib
You must have the bindings module installed:
https://github.com/CyanMARgh/raylib-jai-linux
The path to it is specified in rl_version.jai.

Now it is being built for windows and linux, but since there are plans to add a GUI with raygui (which currently only has linux support), for the time being the version will only be available for linux.

## kscurses
You must have the module installed:
https://github.com/CyanMARgh/kscurses
The path to it is specified in ks_version.jai.

because at the moment kscurses does not have windows support, this version is built only for linux.

If you can help with adding windows support, then please write: (Discord)`Sysoev_Y#3715`
