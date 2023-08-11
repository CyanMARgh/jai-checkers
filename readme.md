# checkers
just checkers for four, nothing fancy

`tested on compiler version 0.1.070`

# how to build
There are 3 game interfaces available: Simp (2D for now), kscurses (TUI) and raylib (3D). For any of them, in first.jai inside the top `#run {}` block, you must specify the desired one. For example:
```
...
#run {
	set_build_options_dc(.{do_output=false});
	build(.RAYLIB);
}
...
```
# extra requirements
For building any of the versions, the Extra_Containers module is used: https://github.com/CyanMARgh/extra-containers.
Place it in your modules folder and specify the path to it in first.jai.

## SIMP
nothing extra.

## Raylib
You must have the bindings module installed:
https://github.com/CyanMARgh/raylib-jai-linux


## kscurses
You must have the module installed:
https://github.com/CyanMARgh/kscurses

because at the moment kscurses does not have windows support, this version is built only for linux.

If you can help with adding windows support, then please write: (Discord)`Sysoev_Y#3715`
