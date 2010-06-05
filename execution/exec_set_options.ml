(*
 Owned and copyright BitBlaze, 2009-2010. All rights reserved.
 Do not copy, disclose, or distribute without explicit written
 permission.
*)

open Exec_options;;

let opt_load_base = ref 0x08048000L (* Linux user space default *)
let opt_start_addr = ref None
let opt_fuzz_start_addr = ref None
let opt_initial_eax = ref None
let opt_initial_ebx = ref None
let opt_initial_ecx = ref None
let opt_initial_edx = ref None
let opt_initial_esi = ref None
let opt_initial_edi = ref None
let opt_initial_esp = ref None
let opt_initial_ebp = ref None
let opt_initial_eflagsrest = ref None
let opt_linux_syscalls = ref false
let opt_setup_initial_proc_state = ref None
let opt_tls_base = ref None
let opt_load_extra_regions = ref []
let opt_program_name = ref None
let opt_core_file_name = ref None
let opt_use_ids_from_core = ref false
let opt_load_data = ref true
let opt_random_memory = ref false
let opt_zero_memory = ref false
let opt_store_bytes = ref []
let opt_store_shorts = ref []
let opt_store_words = ref []
let opt_store_longs = ref []
let opt_state_file = ref None
let opt_solver = ref "stp-external"
let opt_solver_check_against = ref "none"
let opt_symbolic_regs = ref false
let opt_symbolic_cstrings = ref []
let opt_symbolic_string16s = ref []
let opt_symbolic_bytes = ref []
let opt_symbolic_shorts = ref []
let opt_symbolic_words = ref []
let opt_symbolic_longs = ref []
let opt_symbolic_bytes_influence = ref []
let opt_symbolic_shorts_influence = ref []
let opt_symbolic_words_influence = ref []
let opt_symbolic_longs_influence = ref []
let opt_symbolic_regions = ref []
let opt_sink_regions = ref []
let opt_measure_expr_influence_at_strings = ref None
let opt_check_condition_at_strings = ref None
let opt_extra_condition_strings = ref []
let opt_tracepoint_strings = ref []
let opt_string_tracepoint_strings = ref []
let opt_argv = ref []

let split_string char s =
  let delim_loc = String.index s char in
  let s1 = String.sub s 0 delim_loc in
  let s2 = String.sub s (delim_loc + 1) ((String.length s) - delim_loc - 1)
  in
    (s1, s2)

let add_delimited_pair opt char s =
  let (s1, s2) = split_string char s in
    opt := ((Int64.of_string s1), (Int64.of_string s2)) :: !opt

let add_delimited_num_str_pair opt char s =
  let (s1, s2) = split_string char s in
    opt := ((Int64.of_string s1), s2) :: !opt

let add_delimited_str_num_pair opt char s =
  let (s1, s2) = split_string char s in
    opt := (s1, (Int64.of_string s2)) :: !opt

let cmdline_opts =
  [
    ("-start-addr", Arg.String
       (fun s -> opt_start_addr := Some(Int64.of_string s)),
     "addr Code address to start executing");
    ("-fuzz-start-addr", Arg.String
       (fun s -> opt_fuzz_start_addr := Some(Int64.of_string s)),
     "addr Code address to start fuzzing");
    ("-fuzz-end-addr", Arg.String
       (fun s -> opt_fuzz_end_addrs :=
	  (Int64.of_string s) :: !opt_fuzz_end_addrs),
     "addr Code address to finish fuzzing, may be repeated");
    ("-disqualify-addr", Arg.String
       (fun s -> opt_disqualify_addrs :=
	  (Int64.of_string s) :: !opt_disqualify_addrs),
     "addr As above, but also remove from influence");
    ("-core", Arg.String (fun s -> opt_core_file_name := Some s),
     "corefile Load memory state from an ELF core dump");
    ("-pid", Arg.String
       (fun s -> opt_pid := (Int32.to_int (Int32.of_string s))),
     "pid Use regs from specified LWP when loading from core");
    ("-use-ids-from-core", Arg.Set(opt_use_ids_from_core),
     " Simulate getpid(), etc., using values from core file");
    ("-initial-eax", Arg.String
       (fun s -> opt_initial_eax := Some(Int64.of_string s)),
     "word Concrete initial value for %eax register");
    ("-initial-ebx", Arg.String
       (fun s -> opt_initial_ebx := Some(Int64.of_string s)),
     "word Concrete initial value for %ebx register");
    ("-initial-ecx", Arg.String
       (fun s -> opt_initial_ecx := Some(Int64.of_string s)),
     "word Concrete initial value for %ecx register");
    ("-initial-edx", Arg.String
       (fun s -> opt_initial_edx := Some(Int64.of_string s)),
     "word Concrete initial value for %edx register");
    ("-initial-esi", Arg.String
       (fun s -> opt_initial_esi := Some(Int64.of_string s)),
     "word Concrete initial value for %esi register");
    ("-initial-edi", Arg.String
       (fun s -> opt_initial_edi := Some(Int64.of_string s)),
     "word Concrete initial value for %edi register");
    ("-initial-esp", Arg.String
       (fun s -> opt_initial_esp := Some(Int64.of_string s)),
     "word Concrete initial value for %esp (stack pointer)");
    ("-initial-ebp", Arg.String
       (fun s -> opt_initial_ebp := Some(Int64.of_string s)),
     "word Concrete initial value for %ebp (frame pointer)");
    ("-initial-eflagsrest", Arg.String
       (fun s -> opt_initial_eflagsrest := Some(Int64.of_string s)),
     "word Concrete value for %eflags, less [CPAZSO]F");
    ("-iteration-limit", Arg.String
       (fun s -> opt_iteration_limit := Int64.of_string s),
     "N Stop path if a loop iterates more than N times");
    ("-path-depth-limit", Arg.String
       (fun s -> opt_path_depth_limit := Int64.of_string s),
     "N Stop path after N bits of symbolic branching");
    ("-query-branch-limit", Arg.Set_int opt_query_branch_limit,
     "N Try at most N possibilities per branch");
    ("-num-paths", Arg.String
       (fun s -> opt_num_paths := Some (Int64.of_string s)),
     "N Stop after N different paths");
    ("-load-base", Arg.String
       (fun s -> opt_load_base := Int64.of_string s),
     "addr Base address for program image");
    ("-load-region", Arg.String
       (add_delimited_pair opt_load_extra_regions '+'),
     "base+size Load an additional region from program image");
    ("-load-data", Arg.Bool(fun b -> opt_load_data := b),
     "bool Load data segments from a binary?"); 
    ("-setup-initial-proc-state",
     Arg.Bool(fun b -> opt_setup_initial_proc_state := Some b),
     "bool Setup initial process state (argv, etc.)?"); 
    ("-env", Arg.String
       (fun s ->
	  let (k, v) = split_string '=' s in
	    Hashtbl.replace opt_extra_env k v),
     "name=val Set environment variable for program");
    ("-symbolic-region", Arg.String
       (add_delimited_pair opt_symbolic_regions '+'),
     "base+size Memory region of unknown structure");
    ("-symbolic-cstring", Arg.String
       (add_delimited_pair opt_symbolic_cstrings '+'),
     "base+size Make a C string with given size, concrete \\0");
    ("-skip-call-addr", Arg.String
       (add_delimited_pair opt_skip_call_addr '='),
     "addr=retval Replace the call instruction at address 'addr' with a nop, and place 'retval' in EAX (return value)");
    ("-skip-call-addr-symbol", Arg.String
       (add_delimited_num_str_pair opt_skip_call_addr_symbol '='),
     "addr=symname As above, but return a fresh symbol");
    ("-symbolic-string16", Arg.String
       (add_delimited_pair opt_symbolic_string16s '+'),
     "base+16s As above, but with 16-bit characters");
    ("-symbolic-regs", Arg.Set(opt_symbolic_regs),
     " Give symbolic values to registers");
    ("-symbolic-byte", Arg.String
       (add_delimited_num_str_pair opt_symbolic_bytes '='),
     "addr=var Make a memory byte symbolic");
    ("-symbolic-byte-influence", Arg.String
       (add_delimited_num_str_pair opt_symbolic_bytes_influence '='),
     "addr=var As above, but also use for -periodic-influence");
    ("-symbolic-short", Arg.String
       (add_delimited_num_str_pair opt_symbolic_shorts '='),
     "addr=var Make a 16-bit memory valule symbolic");
    ("-symbolic-short-influence", Arg.String
       (add_delimited_num_str_pair opt_symbolic_shorts_influence '='),
     "addr=var As above, but also use for -periodic-influence");
    ("-symbolic-word", Arg.String
       (add_delimited_num_str_pair opt_symbolic_words '='),
     "addr=var Make a memory word symbolic");
    ("-symbolic-word-influence", Arg.String
       (add_delimited_num_str_pair opt_symbolic_words_influence '='),
     "addr=var As above, but also use for -periodic-influence");
    ("-symbolic-long", Arg.String
       (add_delimited_num_str_pair opt_symbolic_longs '='),
     "addr=var Make a 64-bit memory valule symbolic");
    ("-symbolic-long-influence", Arg.String
       (add_delimited_num_str_pair opt_symbolic_longs_influence '='),
     "addr=var As above, but also use for -periodic-influence");
    ("-sink-region", Arg.String
       (add_delimited_str_num_pair opt_sink_regions '+'),
     "var+size Range-check but ignore writes to a region");
    ("-random-memory", Arg.Set(opt_random_memory),
     " Use random values for uninit. memory reads");
    ("-zero-memory", Arg.Set(opt_zero_memory),
     " Use zero values for uninit. memory reads");
    ("-check-for-null", Arg.Set(opt_check_for_null),
     " Check whether dereferenced values can be null");
    ("-measure-influence-derefs", Arg.Set(opt_measure_influence_derefs),
     " Measure influence on uses of sym. pointer values");
    ("-measure-influence-reploops", Arg.Set(opt_measure_influence_reploops),
     " Measure influence on %ecx at rep-prefixed instructions");
    ("-measure-influence-syscall-args", Arg.Set(opt_measure_influence_syscall_args),
     " Measure influence on uses of sym. system call args.");
    ("-measure-deref-influence-at", Arg.String
       (fun s -> opt_measure_deref_influence_at :=
	  Some (Int64.of_string s)),
     "eip Measure influence of pointer at given code address");
    ("-multipath-influence-only", Arg.Set(opt_multipath_influence_only),
     " Skip single-path influence measurements");
    ("-stop-at-measurement", Arg.Set(opt_stop_at_measurement),
     " Stop paths after an '-at' influence measurement");
    ("-measure-expr-influence-at", Arg.String
       (fun s -> let (eip_s, expr_s) = split_string ':' s in
	  opt_measure_expr_influence_at_strings :=
	    Some (eip_s, expr_s)),
     "eip:expr Measure influence of value at given code address");
    ("-periodic-influence", Arg.String
       (fun s ->
	  let k = int_of_string s in
	    opt_periodic_influence := Some k;
	    next_periodic_influence := k),
     "k Check influence every K bits of branching");
    ("-influence-bound", Arg.Set_float(opt_influence_bound),
     "float Stop path when influence is <= this value");
    ("-concretize-divisors", Arg.Set(opt_concretize_divisors),
     " Choose concrete values for divisors in /, %");
    ("-state", Arg.String
       (fun s -> opt_state_file := Some s),
     "file Load memory state from TEMU state file");
    ("-store-byte", Arg.String
       (add_delimited_pair opt_store_bytes '='),
     "addr=val Set the byte at address to a concrete value");
    ("-store-short", Arg.String
       (add_delimited_pair opt_store_shorts '='),
     "addr=val Set 16-bit location to a concrete value");
    ("-store-word", Arg.String
       (add_delimited_pair opt_store_words '='),
     "addr=val Set a memory word to a concrete value");
    ("-store-word", Arg.String
       (add_delimited_pair opt_store_longs '='),
     "addr=val Set 64-bit location to a concrete value");
    ("-solver", Arg.Set_string(opt_solver),
     "solver stpvc (internal) or stp-external (cf. -stp-path)");
    ("-solver-check-against", Arg.Set_string(opt_solver_check_against),
     "solver Compare solver results with the given one");
    ("-stp-path", Arg.Set_string(opt_stp_path),
     "path Location of external STP binary");
    ("-save-solver-files", Arg.Set(opt_save_solver_files),
     " Retain STP input and output files");
    ("-solver-slow-time", Arg.Set_float(opt_solver_slow_time),
     "secs Save queries that take longer than SECS");
    ("-solver-timeout", Arg.String
       (fun s -> opt_solver_timeout := Some (int_of_string s)),
     "secs Run each query for at most SECS seconds");
    ("-tls-base", Arg.String
       (fun s -> opt_tls_base := Some (Int64.of_string s)),
     "addr Use a Linux TLS (%gs) segment at the given address");
    ("-linux-syscalls", Arg.Set(opt_linux_syscalls),
     " Simulate Linux system calls on the real system");
    ("-trace-assigns", Arg.Set(opt_trace_assigns),
     " Print satisfying assignments");
    ("-trace-assigns-string", Arg.Set(opt_trace_assigns_string),
     " Print satisfying assignments as a string");
    ("-trace-basic",
     (Arg.Unit
	(fun () ->
	   opt_trace_binary_paths := true;
	   opt_trace_decisions := true;
	   opt_trace_iterations := true;
	   opt_trace_setup := true;
	   opt_trace_stopping := true;
	   opt_trace_sym_addrs := true;
	   opt_coverage_stats := true;
	   opt_time_stats := true)),
     " Enable several common trace and stats options");
    ("-trace-binary-paths", Arg.Set(opt_trace_binary_paths),
     " Print decision paths as bit strings");
    ("-trace-binary-paths-delimited",
     Arg.Set(opt_trace_binary_paths_delimited),
     " As above, but with '-'s separating queries");
    ("-trace-binary-paths-bracketed",
     Arg.Set(opt_trace_binary_paths_bracketed),
     " As above, but with []s around multibit queries");
    ("-trace-conditions", Arg.Set(opt_trace_conditions),
     " Print branch conditions");
    ("-trace-decisions", Arg.Set(opt_trace_decisions),
     " Print symbolic branch choices");
    ("-trace-decision-tree", Arg.Set(opt_trace_decision_tree),
     " Print internal decision tree operations");
    ("-trace-detailed",
     (Arg.Unit
	(fun () ->
	   opt_trace_insns := true;
	   opt_trace_loads := true;
	   opt_trace_stores := true;
	   opt_trace_temps := true;
	   opt_trace_syscalls := true)),
     " Enable several verbose tracing options");
    ("-trace-detailed-range", Arg.String
       (add_delimited_pair opt_trace_detailed_ranges '-'),
     "eip1-eip2 As above, but only for an eip range");
    ("-trace-eip", Arg.Set(opt_trace_eip),
     " Print PC of each insn executed");
    ("-trace-insns", Arg.Set(opt_trace_insns),
     " Print assembly-level instructions");
    ("-trace-ir", Arg.Set(opt_trace_ir),
     " Print Vine IR before executing it");
    ("-trace-orig-ir", Arg.Set(opt_trace_orig_ir),
     " Print Vine IR as produced by Asmir");
    ("-trace-iterations", Arg.Set(opt_trace_iterations),
     " Print iteration count");
    ("-trace-loads", Arg.Set(opt_trace_loads),
     " Print each memory load");
    ("-trace-stores", Arg.Set(opt_trace_stores),
     " Print each memory store");
    ("-trace-randomness", Arg.Set(opt_trace_randomness),
     " Print operation of PRNG 'random' choices");
    ("-trace-regions", Arg.Set(opt_trace_regions),
     " Print symbolic memory regions");
    ("-trace-setup", Arg.Set(opt_trace_setup),
     " Print progress of program loading");
    ("-trace-solver", Arg.Set(opt_trace_solver),
     " Print calls to decision procedure");
    ("-trace-stopping", Arg.Set(opt_trace_stopping),
     " Print why paths terminate");
    ("-trace-sym-addrs", Arg.Set(opt_trace_sym_addrs),
     " Print symbolic address values");
    ("-trace-sym-addr-details", Arg.Set(opt_trace_sym_addr_details),
     " Print even more about symbolic address values");
    ("-trace-syscalls", Arg.Set(opt_trace_syscalls),
     " Print systems calls (like strace)");
    ("-trace-temps", Arg.Set(opt_trace_temps),
     " Print intermediate formulas");
    ("-use-tags", Arg.Set(opt_use_tags),
     " Track data flow with numeric tags");
    ("-coverage-stats", Arg.Set(opt_coverage_stats),
     " Print pseudo-BB coverage statistics");
    ("-gc-stats", Arg.Set(opt_gc_stats),
     " Print memory usage statistics");
    ("-solver-stats", Arg.Set(opt_solver_stats),
     " Print solver statistics");
    ("-time-stats", Arg.Set(opt_time_stats),
     " Print running time statistics");
    ("-print-callrets", Arg.Set(opt_print_callrets),
     " Print call and ret instructions executed. Can be used with ./getbacktrace.pl to generate the backtrace at any point.");
    (* This flag is misspelled, and will be renamed in the future. *)
    ("-no-fail-on-huer", Arg.Clear(opt_fail_offset_heuristic),
     " Do not fail when a heuristic (e.g. offset optimization) fails.");
    ("-offset-strategy", Arg.String
       (fun s -> opt_offset_strategy := offset_strategy_of_string s),
     "strategy Strategy for offset concretization: uniform, biased-small");
    ("-nonfatal-solver", Arg.Set(opt_nonfatal_solver),
     " Keep going even if the solver fails/crashes");
    ("-follow-path", Arg.Set_string(opt_follow_path),
     "string String of 0's and 1's signifying the specific path decisions to make.");
    ("-watch-expr", Arg.String
       (fun s -> opt_watch_expr_str := Some s),
     "expr Print Vine expression on each instruction");
    ("-tracepoint", Arg.String
       (fun s -> add_delimited_num_str_pair opt_tracepoint_strings
	  ':' s),
     "eip:expr Print scalar expression on given EIP");
    ("-tracepoint-string", Arg.String
       (fun s -> add_delimited_num_str_pair opt_string_tracepoint_strings
	  ':' s),
     "eip:expr Print string expression on given EIP");
    ("-check-condition-at", Arg.String
       (fun s -> let (eip_s, expr_s) = split_string ':' s in
	  opt_check_condition_at_strings :=
	    Some (eip_s, expr_s)),
     "eip:expr Check boolean assertion at address");
    ("-extra-condition", Arg.String
       (fun s -> opt_extra_condition_strings :=
	  s :: !opt_extra_condition_strings),
     "cond Add an extra constraint for solving");
    ("-random-seed", Arg.Set_int opt_random_seed,
     "N Use given seed for path choice");
    ("--", Arg.Rest(fun s -> opt_argv := !opt_argv @ [s]),
     " Pass any remaining arguments to the program");
  ]

let trace_replay_cmdline_opts =
  [
    (* Would you ever not want this set in tracereplay?
    ("-concrete-path", Arg.Set(opt_concrete_path),
     " Execute only according to concrete values"); *)
    ("-solve-path-conditions", Arg.Set(opt_solve_path_conditions),
     " Solve conditions along -concrete path");
    ("-check-write-operands", Arg.Set(opt_check_write_operands),
     " Compare insn outputs against trace");
    ("-trace-registers", Arg.Set(opt_trace_registers),
     " Print register contents");
    ("-trace-segments", Arg.Set(opt_trace_segments),
     " Print messages about non-default segments");
    ("-trace-taint", Arg.Set(opt_trace_taint),
     " Print messages about tainted values");
  ]

let set_program_name s =
  match !opt_program_name with 
    | None -> opt_program_name := Some s
    | _ -> failwith "Multiple non-option args not allowed"

let state_start_addr = ref None

let apply_cmdline_opts
    (fm :
     < add_special_handler : Fragment_machine.special_handler -> 'a;
       get_short_var : Fragment_machine.register_name -> int;
       get_word_var : Fragment_machine.register_name -> int64;
       get_word_var_concretize : (Fragment_machine.register_name
				  -> bool -> string -> int64);
       load_byte_concretize : int64 -> bool -> string -> int;
       load_short_concretize : int64 -> bool -> string -> int;
       load_word_conc : int64 -> int64;
       load_word_concretize : int64 -> bool -> string -> int64;
       load_x86_user_regs : Temu_state.userRegs -> unit;
       make_x86_regs_symbolic : unit;
       make_x86_regs_zero : unit;
       on_missing_random : unit;
       on_missing_symbol : unit;
       on_missing_zero : unit;
       print_x86_regs : unit;
       read_buf : int64 -> int -> char array;
       read_cstr : int64 -> string;
       set_query_engine : Query_engine.query_engine -> unit;
       set_short_var : Fragment_machine.register_name -> int -> unit;
       set_word_var : Fragment_machine.register_name -> int64 -> unit;
       store_byte_conc : int64 -> int -> unit;
       store_byte_idx : int64 -> int -> int -> unit;
       store_cstr : int64 -> int64 -> string -> unit;
       store_long_conc : int64 -> int64 -> unit;
       store_page_conc : int64 -> string -> unit;
       store_short_conc : int64 -> int -> unit;
       store_str : int64 -> int64 -> string -> unit;
       store_word_conc : int64 -> int64 -> unit;
       watchpoint : unit;
       zero_fill : int64 -> int -> unit; .. >)
    dl =
  if !opt_random_memory then
    fm#on_missing_random
  else if !opt_zero_memory then
    fm#on_missing_zero
  else
    fm#on_missing_symbol;
  (match !opt_watch_expr_str with
     | Some s -> opt_watch_expr :=
	 Some (Vine_parser.parse_exp_from_string dl s)
     | None -> ());
  (match !opt_measure_expr_influence_at_strings with
     | Some (eip_s, expr_s) ->
	 opt_measure_expr_influence_at :=
	   Some ((Int64.of_string eip_s),
		 (Vine_parser.parse_exp_from_string dl expr_s))
     | None -> ());
  (match !opt_check_condition_at_strings with
     | Some (eip_s, expr_s) ->
	 opt_check_condition_at :=
	   Some ((Int64.of_string eip_s),
		 (Vine_parser.parse_exp_from_string dl expr_s))
     | None -> ());
  opt_tracepoints := List.map
    (fun (eip, s) ->
       (eip, s, (Vine_parser.parse_exp_from_string dl s)))
    !opt_tracepoint_strings;
  opt_string_tracepoints := List.map
	(fun (eip, s) ->
	   (eip, s, (Vine_parser.parse_exp_from_string dl s)))
	!opt_string_tracepoint_strings;
  if !opt_symbolic_regs then
    fm#make_x86_regs_symbolic
  else
    fm#make_x86_regs_zero;
  (match !opt_program_name with
     | Some name ->
	 let do_setup = match !opt_setup_initial_proc_state with
	   | Some b -> b
	   | None ->
	       if !opt_start_addr <> None then
		 false
	       else if !opt_argv <> [] then
		 true
	       else
		 failwith ("Can't decide whether to "^
			     "-setup-initial-proc-state")
	 in
	   state_start_addr := Some
	     (Linux_loader.load_dynamic_program
		(fm :> Linux_loader.needed_fm) name
		!opt_load_base !opt_load_data do_setup
		!opt_load_extra_regions !opt_argv)
     | _ -> ());
  (match !opt_core_file_name with
     | Some name -> 
	 state_start_addr :=
	   Some (Linux_loader.load_core
		   (fm :> Linux_loader.needed_fm) name)
     | None -> ());
  (let checking_solver = match !opt_solver_check_against with
     | "none" -> None
     | "stpvc" -> Some (new Stpvc_engine.stpvc_engine
			:> Query_engine.query_engine)
     | "stp-external" -> Some (new Stp_external_engine.stp_external_engine
				 "fuzz-check")
     | _ -> failwith "Unknown solver for -solver-check-against" in
   let main_solver = match !opt_solver with
     | "stpvc" -> ((new Stpvc_engine.stpvc_engine)
		   :> Query_engine.query_engine)
     | "stp-external" -> new Stp_external_engine.stp_external_engine "fuzz"
     | _ -> failwith "Unknown -solver" in
   let qe =
     match checking_solver with
       | None -> main_solver
       | Some cs -> new Query_engine.parallel_check_engine main_solver cs
   in
     fm#set_query_engine qe);
  if !opt_linux_syscalls then
    let lsh = new Linux_syscalls.linux_special_handler fm in
      if !opt_use_ids_from_core then
	lsh#set_proc_identities !Linux_loader.proc_identities;
      fm#add_special_handler (lsh :> Fragment_machine.special_handler)
  else
    fm#add_special_handler
      ((new Special_handlers.linux_special_nonhandler fm)
       :> Fragment_machine.special_handler);
  fm#add_special_handler
    ((new Special_handlers.trap_special_nonhandler fm)
     :> Fragment_machine.special_handler);
  fm#add_special_handler
    ((new Special_handlers.cpuid_special_handler fm)
     :> Fragment_machine.special_handler);
  (match !opt_state_file with
     | Some s -> state_start_addr := Some
	 (State_loader.load_mem_state fm s)
     | None -> ());
  (match !opt_tls_base with
     | Some base -> Linux_loader.setup_tls_segment
	 (fm :> Linux_loader.needed_fm) 0x60000000L base
     | None -> ());
  (match !opt_initial_eax with
     | Some v -> fm#set_word_var Fragment_machine.R_EAX v
	 | None -> ());
  (match !opt_initial_ebx with
     | Some v -> fm#set_word_var Fragment_machine.R_EBX v
     | None -> ());
  (match !opt_initial_ecx with
     | Some v -> fm#set_word_var Fragment_machine.R_ECX v
     | None -> ());
  (match !opt_initial_edx with
     | Some v -> fm#set_word_var Fragment_machine.R_EDX v
     | None -> ());
  (match !opt_initial_esi with
     | Some v -> fm#set_word_var Fragment_machine.R_ESI v
     | None -> ());
  (match !opt_initial_edi with
     | Some v -> fm#set_word_var Fragment_machine.R_EDI v
     | None -> ());
  (match !opt_initial_esp with
     | Some v -> fm#set_word_var Fragment_machine.R_ESP v
     | None -> ());
  (match !opt_initial_ebp with
     | Some v -> fm#set_word_var Fragment_machine.R_EBP v
     | None -> ());
  (match !opt_initial_eflagsrest with
     | Some v -> fm#set_word_var Fragment_machine.EFLAGSREST v
     | None -> ());
  List.iter (fun (addr,v) -> fm#store_byte_conc addr 
	       (Int64.to_int v)) !opt_store_bytes;
  List.iter (fun (addr,v) -> fm#store_short_conc addr
	       (Int64.to_int v)) !opt_store_shorts;
  List.iter (fun (addr,v) -> fm#store_word_conc addr v) !opt_store_words;
  List.iter (fun (addr,v) -> fm#store_long_conc addr v) !opt_store_longs;
  ()

let make_symbolic_init 
    (fm:
     < make_sink_region : string -> int64 -> unit;
       make_symbolic_region : int64 -> int -> unit;
       parse_symbolic_expr : string -> Vine.exp;
       store_symbolic_byte : int64 -> string -> unit;
       store_symbolic_byte_influence : int64 -> string -> unit;
       store_symbolic_cstr : int64 -> int -> unit;
       store_symbolic_long : int64 -> string -> unit;
       store_symbolic_long_influence : int64 -> string -> unit;
       store_symbolic_short : int64 -> string -> unit;
       store_symbolic_short_influence : int64 -> string -> unit;
       store_symbolic_wcstr : int64 -> int -> unit;
       store_symbolic_word : int64 -> string -> unit;
       store_symbolic_word_influence : int64 -> string -> unit; .. >)
     =
  (fun () ->
     let new_max i =
       max_input_string_length :=
	 max (!max_input_string_length) (Int64.to_int i)
     in
       List.iter (fun (base, len) ->
		    new_max len;
		    fm#make_symbolic_region base (Int64.to_int len))
	 !opt_symbolic_regions;
       List.iter (fun (base, len) ->
		    new_max len;
		    fm#store_symbolic_cstr base (Int64.to_int len))
	 !opt_symbolic_cstrings;
       List.iter (fun (base, len) ->
		    new_max (Int64.mul 2L len);
		    fm#store_symbolic_wcstr base (Int64.to_int len))
	 !opt_symbolic_string16s;
       List.iter (fun (addr, varname) ->
		    fm#store_symbolic_byte addr varname)
	 !opt_symbolic_bytes;
       List.iter (fun (addr, varname) ->
		    fm#store_symbolic_byte_influence addr varname)
	 !opt_symbolic_bytes_influence;
       List.iter (fun (addr, varname) ->
		    fm#store_symbolic_short addr varname)
	 !opt_symbolic_shorts;
       List.iter (fun (addr, varname) ->
		    fm#store_symbolic_short_influence addr varname)
	 !opt_symbolic_shorts_influence;
       List.iter (fun (addr, varname) ->
		    fm#store_symbolic_word addr varname)
	 !opt_symbolic_words;
       List.iter (fun (addr, varname) ->
		    fm#store_symbolic_word_influence addr varname)
	 !opt_symbolic_words_influence;
       List.iter (fun (addr, varname) ->
		    fm#store_symbolic_long addr varname)
	 !opt_symbolic_longs;
       List.iter (fun (addr, varname) ->
		    fm#store_symbolic_long_influence addr varname)
	 !opt_symbolic_longs_influence;
       List.iter (fun (varname, size) ->
		    fm#make_sink_region varname size)
	 !opt_sink_regions;
       opt_extra_conditions :=
	 List.map (fun s -> fm#parse_symbolic_expr s)
	   !opt_extra_condition_strings)

let decide_start_addrs () =
  let (start_addr, fuzz_start) = match
    (!opt_start_addr, !opt_fuzz_start_addr,
     !state_start_addr) with
      | (None,     None,      None) ->
	  failwith "Missing starting address"
      | (None,     None,      Some ssa) -> (ssa,  ssa)
      | (None,     Some ofsa, Some ssa) -> (ssa,  ofsa)
      | (None,     Some ofsa, None    ) -> (ofsa, ofsa)
      | (Some osa, Some ofsa, _       ) -> (osa,  ofsa)
      | (Some osa, None,      _       ) -> (osa,  osa)
  in
    if !opt_trace_setup then
      Printf.printf "%s 0x%08Lx, fuzz start 0x%08Lx\n"
	"Starting address" start_addr fuzz_start;
    (start_addr, fuzz_start)