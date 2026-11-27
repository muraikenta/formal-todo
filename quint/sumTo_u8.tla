------------------------------- MODULE sumTo_u8 -------------------------------

EXTENDS Integers, Sequences, FiniteSets, TLC, Apalache, Variants

(*
  @type: (() => Int);
*)
sumTo_u8_sumTo_NMAX == 30

VARIABLE
  (*
    @type: Int;
  *)
  sumTo_u8_sumTo_n

VARIABLE
  (*
    @type: Int;
  *)
  sumTo_u8_sumTo_i

VARIABLE
  (*
    @type: Int;
  *)
  sumTo_u8_sumTo_total

VARIABLE
  (*
    @type: Str;
  *)
  sumTo_u8_sumTo_status

(*
  @type: (() => Bool);
*)
sumTo_u8_sumTo_SWAPPED == FALSE

(*
  @type: (() => Int);
*)
sumTo_u8_sumTo_MAX == 255

(*
  @type: ((Int) => Bool);
*)
sumTo_u8_sumTo_initWith(sumTo_u8_sumTo_k_43) ==
  sumTo_u8_sumTo_n = sumTo_u8_sumTo_k_43
    /\ sumTo_u8_sumTo_i = 0
    /\ sumTo_u8_sumTo_total = 0
    /\ sumTo_u8_sumTo_status = "running"

(*
  @type: (() => Bool);
*)
sumTo_u8_sumTo_loopStep ==
  LET (*@type: (() => Int); *) sumTo_u8_sumTo_newI == sumTo_u8_sumTo_i + 1 IN
  LET (*
    @type: (() => Int);
  *)
  sumTo_u8_sumTo_newTotal ==
    IF sumTo_u8_sumTo_SWAPPED
    THEN sumTo_u8_sumTo_total + sumTo_u8_sumTo_i
    ELSE sumTo_u8_sumTo_total + sumTo_u8_sumTo_newI
  IN
  sumTo_u8_sumTo_status = "running"
    /\ sumTo_u8_sumTo_i < sumTo_u8_sumTo_n
    /\ (IF sumTo_u8_sumTo_newTotal > sumTo_u8_sumTo_MAX
    THEN sumTo_u8_sumTo_status' := "overflow"
      /\ sumTo_u8_sumTo_n' := sumTo_u8_sumTo_n
      /\ sumTo_u8_sumTo_i' := sumTo_u8_sumTo_i
      /\ sumTo_u8_sumTo_total' := sumTo_u8_sumTo_total
    ELSE sumTo_u8_sumTo_status' := "running"
      /\ sumTo_u8_sumTo_n' := sumTo_u8_sumTo_n
      /\ sumTo_u8_sumTo_i' := sumTo_u8_sumTo_newI
      /\ sumTo_u8_sumTo_total' := sumTo_u8_sumTo_newTotal)

(*
  @type: (() => Bool);
*)
sumTo_u8_sumTo_finish ==
  sumTo_u8_sumTo_status = "running"
    /\ sumTo_u8_sumTo_i >= sumTo_u8_sumTo_n
    /\ sumTo_u8_sumTo_status' := "done"
    /\ sumTo_u8_sumTo_n' := sumTo_u8_sumTo_n
    /\ sumTo_u8_sumTo_i' := sumTo_u8_sumTo_i
    /\ sumTo_u8_sumTo_total' := sumTo_u8_sumTo_total

(*
  @type: (() => Bool);
*)
sumTo_u8_sumTo_halted ==
  sumTo_u8_sumTo_status /= "running"
    /\ sumTo_u8_sumTo_status' := sumTo_u8_sumTo_status
    /\ sumTo_u8_sumTo_n' := sumTo_u8_sumTo_n
    /\ sumTo_u8_sumTo_i' := sumTo_u8_sumTo_i
    /\ sumTo_u8_sumTo_total' := sumTo_u8_sumTo_total

(*
  @type: (() => Bool);
*)
sumTo_u8_sumTo_init ==
  \E sumTo_u8_sumTo_k \in 0 .. sumTo_u8_sumTo_NMAX:
    sumTo_u8_sumTo_initWith(sumTo_u8_sumTo_k)

(*
  @type: (() => Bool);
*)
sumTo_u8_sumTo_step ==
  sumTo_u8_sumTo_loopStep \/ sumTo_u8_sumTo_finish \/ sumTo_u8_sumTo_halted

(*
  @type: (() => Bool);
*)
q_init == sumTo_u8_sumTo_init

(*
  @type: (() => Bool);
*)
q_step == sumTo_u8_sumTo_step

================================================================================
