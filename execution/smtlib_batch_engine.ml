(*
  Based on stp_external_engine.ml, which bears the following notice:
  Copyright (C) BitBlaze, 2009-2011, and copyright (C) 2010 Ensighta
  Security Inc.  All rights reserved.
*)

module V = Vine;;

open Exec_exceptions;;
open Exec_options;;
open Query_engine;;
open Solvers_common;;
open Smt_lib2;;

let parse_counterex e_s_t line =
  match parse_ce e_s_t line with
    | No_CE_here -> None
    | End_of_CE -> None
    | Assignment(s, i) -> Some (s, i)

class smtlib_batch_engine e_s_t fname = object(self)
  inherit query_engine

  val mutable chan = None
  val mutable visitor = None
  val mutable temp_dir = None
  val mutable filenum = 0
  val mutable curr_fname = fname

  method private get_temp_dir =
    match temp_dir with
      | Some t -> t
      | None ->
	  let t = create_temp_dir "fuzzball-tmp" in
	    temp_dir <- Some t;
	    t

  method private get_fresh_fname =
    let dir = self#get_temp_dir in
      filenum <- filenum + 1;
      curr_fname <- pick_fresh_fname dir fname filenum;
      if !opt_trace_solver then
	Printf.printf "Creating SMTLIB2 file: %s.smt2\n" curr_fname;
      curr_fname

  method private chan =
    match chan with
      | Some c -> c
      | None -> failwith "Missing output channel in smtlib_batch_engine"

  method private visitor =
    match visitor with
      | Some v -> v
      | None -> failwith "Missing visitor in smtlib_batch_engine"

  val mutable free_vars = []
  val mutable eqns = []
  val mutable conds = []

  method start_query =
    ()

  method add_free_var var =
    free_vars <- var :: free_vars

  method private real_add_free_var var =
    self#visitor#declare_var var

  method add_temp_var var =
    ()

  method assert_eq var rhs =
    eqns <- (var, rhs) :: eqns;

  method add_condition e =
    conds <- e :: conds

  val mutable ctx_stack = []

  method push =
    ctx_stack <- (free_vars, eqns, conds) :: ctx_stack

  method pop =
    match ctx_stack with
      | (free_vars', eqns', conds') :: rest ->
	  free_vars <- free_vars';
	  eqns <- eqns';
	  conds <- conds';
	  ctx_stack <- rest
      | [] -> failwith "Context underflow in smtlib_batch_engine#pop"

  method private real_assert_eq (var, rhs) =
    try
      self#visitor#declare_var_value var rhs
    with
      | V.TypeError(err) ->
	  Printf.printf "Typecheck failure on %s: %s\n"
	    (V.exp_to_string rhs) err;
	  failwith "Typecheck failure in assert_eq"

  method private real_prepare =
    let fname = self#get_fresh_fname in
      chan <- Some(open_out (fname ^ ".smt2"));
      visitor <- Some(new Smt_lib2.vine_smtlib_print_visitor
			(output_string self#chan));
      output_string self#chan
	"(set-logic QF_BV)\n(set-info :smt-lib-version 2.0)\n\n";
      List.iter self#real_add_free_var (List.rev free_vars);
      List.iter self#real_assert_eq (List.rev eqns);

  method query qe =
    self#real_prepare;
    output_string self#chan "\n";
    let conj = List.fold_left
      (fun es e -> V.BinOp(V.BITAND, e, es)) qe (List.rev conds)
    in
      (let visitor = (self#visitor :> V.vine_visitor) in
       let rec loop = function
	 | V.BinOp(V.BITAND, e1, e2) ->
	     loop e1;
	     (* output_string self#chan "\n"; *)
	     loop e2
	 | e ->
	     output_string self#chan "(assert ";
	     ignore(V.exp_accept visitor e);
	     output_string self#chan ")\n"
       in
	 loop conj);
    output_string self#chan "\n(check-sat)\n";
    output_string self#chan "(exit)\n";
    close_out self#chan;
    chan <- None;
    let timeout_opt = match (e_s_t, !opt_solver_timeout) with
      | ((STP_SMTLIB2|STP_CVC), Some s) ->
	  "-g " ^ (string_of_int s) ^ " "
      | (CVC4, Some s) ->
	  "--tlimit-per " ^ (string_of_int s) ^ "000 "
      | (BOOLECTOR, Some s) ->
	  "-t " ^ (string_of_int s) ^ " "
      | (_, None) -> ""
    in
    let base_opt = match e_s_t with
      | STP_SMTLIB2 -> " --SMTLIB2 -p "
      | STP_CVC -> " -p " (* shouldn't really be here *)
      | CVC4 -> " --lang smt -m --dump-models "
      | BOOLECTOR -> " -m "
    in
    let cmd = !opt_solver_path ^ base_opt ^ timeout_opt ^ curr_fname
      ^ ".smt2 >" ^ curr_fname ^ ".smt2.out" in
      if !opt_trace_solver then
	Printf.printf "Solver command: %s\n" cmd;
      flush stdout;
      let rcode = Sys.command cmd in
      let results = open_in (curr_fname ^ ".smt2.out") in
	if rcode <> 0 && rcode <> 10 && rcode <> 20 then
	  (* 10 and 20 are used by Boolector for sat/unsat *)
	  (Printf.printf "Solver died with result code %d\n" rcode;
	   (match rcode with
	      | 127 ->
		  if !opt_solver_path = "stp" then
		    Printf.printf
		      "Perhaps you should set the -solver-path option?\n"
		  else if String.contains !opt_solver_path '/' &&
		    not (Sys.file_exists !opt_solver_path)
		  then
		    Printf.printf "The file %s does not appear to exist\n"
		      !opt_solver_path
	      | 131 -> raise (Signal "QUIT")
	      | _ -> ());
	   ignore(Sys.command ("cat " ^ curr_fname ^ ".smt2.out"));
	   (None, []))
	else
	  let result_s = input_line results in
	  let first_assert = (String.sub result_s 0 3) = "ASS" in
	  let result = match result_s with
	    | "unsat" -> Some true
	    | "Timed Out." -> Printf.printf "Solver timeout\n"; None
	    | "sat" -> Some false
	    | _ when first_assert -> Some false
	    | _ -> failwith "Unexpected first output line"
	  in
	  let first_assign = if first_assert then
	    [(match parse_counterex e_s_t result_s with
		| Some ce -> ce | None -> failwith "Unexpected parse failure")]
	  else
	    [] in
	  let ce = map_lines (parse_counterex e_s_t) results in
	    close_in results;
	    (result, first_assign @ ce)

  method after_query save_results =
    if save_results then
      Printf.printf "Solver query and results are in %s.smt2 and %s.smt2.out\n"
	curr_fname curr_fname
    else if not !opt_save_solver_files then
      (Sys.remove (curr_fname ^ ".smt2");
       Sys.remove (curr_fname ^ ".smt2.out"))

  method reset =
    visitor <- None;
    free_vars <- [];
    eqns <- [];
    conds <- []
end