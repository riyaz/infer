(*
 * Copyright (c) 2015 - present Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *)

module F = Format

(** Test the generic abstract interpreter by using a simple path counting domain. Path counting is
    actually a decent stress test--if you join too much/too little, you'll over/under-count, and
    you'll diverge at loops if you don't widen *)

module PathCountDomain = struct

  type astate =
    | PathCount of int
    | Top

  let make_path_count c =
    (* guarding against overflow *)
    if c < 0
    then Top
    else PathCount c

  let bottom = make_path_count 0

  let initial = make_path_count 1

  let is_bottom = function
    | PathCount c -> c = 0
    | Top -> false

  let (<=) ~lhs ~rhs = match lhs, rhs with
    | PathCount c1, PathCount c2 -> c1 <= c2
    | _, Top -> true
    | Top, PathCount _ -> false

  let join a1 a2 = match a1, a2 with
    | PathCount c1, PathCount c2 -> make_path_count (c1 + c2)
    | Top, _ | PathCount _, Top -> Top

  let widen ~prev:_ ~next:_ ~num_iters:_ = Top

  let pp fmt = function
    | PathCount c -> F.fprintf fmt "%d" c
    | Top -> F.fprintf fmt "T"

end

module PathCountTransferFunctions = struct
  type astate = PathCountDomain.astate

  (* just propagate the current path count *)
  let exec_instr astate _ = astate
end


module TestInterpreter = AnalyzerTester.Make
    (ProcCfg.Forward)
    (Scheduler.ReversePostorder)
    (PathCountDomain)
    (PathCountTransferFunctions)

let tests =
  let open OUnit2 in
  let open AnalyzerTester.StructuredSil in
  let test_list = [
    "straightline",
    [
      invariant "1";
      invariant "1"
    ];
    "if",
    [
      invariant "1";
      If (unknown_exp, [], []);
      invariant "2";
    ];
    "if_then",
    [
      If (unknown_exp,
          [invariant "1"],
          []
         );
      invariant "2"
    ];
    "if_else",
    [
      If (unknown_exp,
          [],
          [invariant "1"]
         );
      invariant "2"
    ];
    "if_then_else",
    [
      If (unknown_exp,
          [invariant "1"],
          [invariant "1"];
         );
      invariant "2"
    ];
    "nested_if_then",
    [
      If (unknown_exp,
          [If (unknown_exp, [], []);
           invariant "2"],
          []
         );
      invariant "3"
    ];
    "nested_if_else",
    [
      If (unknown_exp,
          [],
          [If (unknown_exp, [], []);
           invariant "2"]
         );
      invariant "3"
    ];
    "nested_if_then_else",
    [
      If (unknown_exp,
          [If (unknown_exp, [], []);
           invariant "2"],
          [If (unknown_exp, [], []);
           invariant "2"]
         );
      invariant "4"
    ];
    "if_diamond",
    [
      invariant "1";
      If (unknown_exp, [], []);
      invariant "2";
      If (unknown_exp, [], []);
      invariant "4"
    ];
    "loop",
    [
      invariant "1";
      While (unknown_exp, [invariant "T"]);
      invariant "T"
    ];
    "if_in_loop",
    [
      While (unknown_exp,
             [If (unknown_exp, [], []);
              invariant "T"]
            );
      invariant "T";
    ];
    "nested_loop_visit",
    [
      invariant "1";
      While (unknown_exp,
             [invariant "T";
              While (unknown_exp,
                     [invariant "T"]);
              invariant "T"]);
      invariant "T";
    ];
  ] |> TestInterpreter.create_tests in
  "analyzer_tests_suite">:::test_list