DEBUG :: true;
IPROF :: false;
IMPORT_EXTRA_PATH :: "..";

#import "Basic";
#import "Compiler";
#import "Process";
#import "File";
Iprof :: #import "Iprof";

// TODO:
// - dead pieces (?)
// - undo last step (full)
// - must_capture : enum u8 { OFF; ON; ___QUEENS___; } = .OFF;
// - board editor mode
// - autoclick, if single step aviable

#run {
	set_build_options_dc(.{do_output=false});
	build(.RAYLIB);
}

#if OS == .LINUX {
	EXECUTABLE_SUFFIX_RAW :: ".elf";
	EXECUTABLE_SUFFIX :: ".elf";
} else #if OS == .WINDOWS {
	EXECUTABLE_SUFFIX_RAW :: "";
	EXECUTABLE_SUFFIX :: ".exe";
} else {
	#run assert(false, "invalid OS");
}

build :: (outfit : enum u8 {KSCURSES; SIMP; RAYLIB; RAYLIB_MATRIX;}) {
	w := compiler_create_workspace();
	make_directory_if_it_does_not_exist("saves");
	make_directory_if_it_does_not_exist("builds");
	make_directory_if_it_does_not_exist("execs");
	if !w {
		print("Workspace createion failed!\n");
		return;
	}
	target_options := get_build_options(w);
	outfit_suffix : string;
	ifx #complete outfit == {
		case .KSCURSES; outfit_suffix = "ks";
		case .RAYLIB; outfit_suffix = "rl";
		case .SIMP; outfit_suffix = "simp";
		case .RAYLIB_MATRIX; outfit_suffix = "rl_matrix";
	}
	
	executable_name := tprint("checkers_%1%2%3", 
		outfit_suffix,
		ifx DEBUG then "_debug" else "",
		EXECUTABLE_SUFFIX_RAW
	);
	actual_executable_name := tprint("./execs/checkers_%1%2%3", 
		outfit_suffix,
		ifx DEBUG then "_debug" else "",
		EXECUTABLE_SUFFIX
	);
	{
		using target_options;
		text_output_flags = 0;

		set_optimization(*target_options, ifx DEBUG then .DEBUG else .VERY_OPTIMIZED, !DEBUG);
		backend = .X64;
		#if DEBUG {
		} else {
			emit_debug_info = .NONE;
		}

		output_path = "execs";
		import_path = .[import_path[0], IMPORT_EXTRA_PATH];
		output_executable_name = executable_name;
	}
	set_build_options(target_options, w);

	#if IPROF {
		iprof_flags : Intercept_Flags;
		iprof := Iprof.get_plugin();
		defer Iprof.finish(iprof);
		Iprof.before_intercept(iprof, *iprof_flags);
		iprof.workspace = w;
	}
	compiler_begin_intercept(w);
	#if IPROF {
		Iprof.add_source(iprof);
	}

	add_build_file(tprint("src/%2_version.jai", #filepath, outfit_suffix), w);
	#if OS == .WINDOWS add_build_string("#run (#import \"Windows_Resources\").disable_runtime_console();", w);
	add_build_string(tprint("DEBUG :: %;\n", DEBUG), w);

	while 1 {
		message := compiler_wait_for_message();
		#if IPROF {
			Iprof.message(iprof, message);
		}
		if message.kind == {
			case .COMPLETE;
			break;
			case .ERROR;
			return;
		}
	}
	compiler_end_intercept(w);

	#if OS == .LINUX {
		run_command("ln", "-s", "-f", actual_executable_name, "main.elf");
	}

	#if !DEBUG if outfit == .RAYLIB {
		pack_rl(actual_executable_name, tprint("checkers%", EXECUTABLE_SUFFIX));
	}
}

pack_rl :: (executable_name : string, new_name : string) {
	run_command("mv", executable_name, new_name);
	args := string.[
		"tar",
		"-czvf",
		"./builds/checkers.tar.gz",
		"--transform",
		"s|^|archive/|",
		new_name,
		"res",
		"saves"
	];
	run_command(..args, capture_and_return_output = true);
	run_command("mv", new_name, executable_name);
}
