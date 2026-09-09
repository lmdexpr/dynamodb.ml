open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type t = {
  code : string;
  message : string option;
  cancellation_reasons : string list;
  body : string;
}

module Body = struct
  type cancellation_reason = { code : string [@key "Code"] }
  [@@deriving of_yojson] [@@yojson.allow_extra_fields]

  type t = {
    type_ : string; [@key "__type"]
    message : string option; [@key "message"] [@yojson.option]
    cancellation_reasons : cancellation_reason list; [@key "CancellationReasons"] [@default []]
  }
  [@@deriving of_yojson] [@@yojson.allow_extra_fields]
end

(* [__type] is [<namespace>#<code>]. *)
let code_of_type type_ =
  match String.rindex_opt type_ '#' with
  | Some i -> String.sub type_ (i + 1) (String.length type_ - i - 1)
  | None -> type_

let of_body body =
  match Yojson.Safe.from_string body |> Body.t_of_yojson with
  | Body.{ type_; message; cancellation_reasons } ->
    {
      code = code_of_type type_;
      message;
      cancellation_reasons = List.map (fun Body.{ code } -> code) cancellation_reasons;
      body;
    }
  | exception (Yojson.Json_error _ | Ppx_yojson_conv_lib.Yojson_conv.Of_yojson_error _) ->
    { code = ""; message = None; cancellation_reasons = []; body }

let is_conditional_check_failed { code; cancellation_reasons; _ } =
  String.equal code "ConditionalCheckFailedException"
  || String.equal code "TransactionCanceledException"
     && List.exists (String.equal "ConditionalCheckFailed") cancellation_reasons

let to_string { code; message; body; _ } =
  match code, message with
  | "", _ -> body
  | code, Some message -> code ^ ": " ^ message
  | code, None -> code
