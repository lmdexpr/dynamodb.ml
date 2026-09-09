(** DynamoDB 4xx error. *)

type t = {
  code : string;  (** [__type] without namespace; [""] when the body is not parseable. *)
  message : string option;
  cancellation_reasons : string list;  (** [TransactionCanceledException]: one code per item. *)
  body : string;
}

val of_body : string -> t
val is_conditional_check_failed : t -> bool
val to_string : t -> string
