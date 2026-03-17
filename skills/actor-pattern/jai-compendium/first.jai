
#run,stallable build();

build_and_run :: (workspace_name: string, source_file: string, build_dir: string) {
    w := compiler_create_workspace(workspace_name);
    if !w {
        print("% workspace creation failed.\n", workspace_name);
        return;
    }
    opts := get_build_options(w);
    import_path: [..] string;
    array_add(*import_path, "modules");
    array_add(*import_path, ..opts.import_path);
    opts.import_path = import_path;
    set_optimization(*opts, .DEBUG);
    opts.arithmetic_overflow_check = .FATAL;
    opts.output_executable_name = workspace_name;
    opts.output_path = build_dir;
    make_directory_if_it_does_not_exist(build_dir);
    set_build_options(opts, w);
    compiler_begin_intercept(w);
    add_build_file(source_file, w);
    while true {
        message := compiler_wait_for_message();
        if message.kind == {
            case .COMPLETE;
            mc := cast(*Message_Complete) message;
            if mc.error_code != .NONE {
                exit(1);
            }
            break;
        }
    }
    compiler_end_intercept(w);
    Autorun.run_build_result_of_workspace(w);
}

build :: () {
    set_working_directory(#filepath);
    options := get_build_options();
    args := options.compile_time_command_line;
    build_dir :: "build";

    if args.count == 0 {
        // Build and run all examples.
        build_and_run("01_basic_actor",       "01_basic_actor/main.jai",       build_dir);
        build_and_run("02_request_response",  "02_request_response/main.jai",  build_dir);
        build_and_run("03_polling",           "03_polling/main.jai",           build_dir);
        build_and_run("04_actor_hierarchy",   "04_actor_hierarchy/main.jai",   build_dir);
    } else {
        for arg: args {
            if arg == {
                case "01"; build_and_run("01_basic_actor",       "01_basic_actor/main.jai",       build_dir);
                case "02"; build_and_run("02_request_response",  "02_request_response/main.jai",  build_dir);
                case "03"; build_and_run("03_polling",           "03_polling/main.jai",           build_dir);
                case "04"; build_and_run("04_actor_hierarchy",   "04_actor_hierarchy/main.jai",   build_dir);
                case;
                    compiler_report(tprint("Unknown example '%'. Valid: 01, 02, 03, 04\n", arg));
            }
        }
    }
    set_build_options_dc(.{do_output=false});
}

#import "Basic";
#import "Compiler";
#import "File";
Autorun :: #import "Autorun";
