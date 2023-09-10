# checkers
just checkers for four, nothing fancy

`tested on compiler version 0.1.074`

# how to build
There are 3 game interfaces available: Simp (2D for now), kscurses (TUI) and raylib (3D).

For building any of the versions, you must have the module installed: https://github.com/CyanMARgh/extra-containers.

For raylib version you must have the bindings module installed: https://github.com/CyanMARgh/raylib-jai-universal.

For TUI version you must have the module installed: https://github.com/CyanMARgh/kscurses

To build any version, in first.jai inside the top `#run {}` block, you must specify the desired one. For example:

```
...
#run {
	set_build_options_dc(.{do_output=false});
	build(.RAYLIB);
}
...
```

At the moment the game has been tested on Ubuntu 22 and Windows 10. If you can help with testing/building for other OS, then write me in discord: `sysoev_y#0000`.