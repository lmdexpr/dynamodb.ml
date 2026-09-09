(** Table-bound wrappers over {!Action}. *)

type t

val make : table:string -> t
val table : t -> string

val put :
  ?condition_expression:string ->
  ?expression_attribute_names:(string * string) list ->
  ?expression_attribute_values:Item.t ->
  t ->
  item:Item.t ->
  (unit, Error.t) result

val put_if_not_exists : t -> item:Item.t -> primary_key:string -> (unit, Error.t) result
(** Condition [attribute_not_exists(#pk)] with [#pk] bound to [primary_key]. *)

val compare_and_swap :
  t -> item:Item.t -> attribute:string -> expected:Value.t -> (unit, Error.t) result
(** Condition [#attr = :expected]. *)

val delete :
  ?condition_expression:string ->
  ?expression_attribute_names:(string * string) list ->
  ?expression_attribute_values:Item.t ->
  t ->
  key:Item.t ->
  (unit, Error.t) result

val compare_and_delete :
  t -> key:Item.t -> attribute:string -> expected:Value.t -> (unit, Error.t) result
(** Condition [#attr = :expected]. *)

val update :
  t ->
  key:Item.t ->
  update_expression:string ->
  expression_attribute_values:Item.t ->
  (Item.t option, Error.t) result
(** Returns the [ALL_NEW] attributes. *)

val get : t -> key:Item.t -> (Item.t option, Error.t) result

val query :
  ?filter_expression:string ->
  ?expression_attribute_names:(string * string) list ->
  ?limit:int ->
  ?scan_index_forward:bool ->
  t ->
  key_condition_expression:string ->
  expression_attribute_values:Item.t ->
  (Item.t list, Error.t) result
(** One page. *)

val scan : t -> (Item.t list, Error.t) result
(** All pages. *)
