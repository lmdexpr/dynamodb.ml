(** [Query], one page. [limit] caps evaluated items; [scan_index_forward = false] descends. *)

type request

val make :
  ?filter_expression:string ->
  ?expression_attribute_names:(string * string) list ->
  ?limit:int ->
  ?scan_index_forward:bool ->
  table_name:string ->
  key_condition_expression:string ->
  expression_attribute_values:Item.t ->
  unit ->
  request

type response = { items : Item.t list }

include Intf.S with type request := request and type response := response
