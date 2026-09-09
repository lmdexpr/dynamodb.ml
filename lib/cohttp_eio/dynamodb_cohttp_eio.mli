(** Handles [Dynamodb.Effects.Call] with cohttp-eio: endpoint from {!Config}, SigV4 signature, POST.
*)

module Config = Config

val run :
  ?max_response_size:int ->
  now:(unit -> float) ->
  client:Cohttp_eio.Client.t ->
  config:Config.t ->
  (unit -> 'a) ->
  'a
(** Installs the [sigv4-cohttp-eio] credentials chain and {!Call.run}. [now] returns the UTC epoch.
    [max_response_size] defaults to 16 MiB. Transport failures, missing credentials, oversized
    responses and 5xx responses raise at the perform site. *)

module Call : sig
  val run :
    ?max_response_size:int ->
    now:(unit -> float) ->
    client:Cohttp_eio.Client.t ->
    config:Config.t ->
    (unit -> 'a) ->
    'a
  (** The request handler alone. *)
end
