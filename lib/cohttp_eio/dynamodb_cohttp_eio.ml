module Config = Config

let default_max_response_size = 16 * 1024 * 1024

let signed_headers ~now ~region ~uri ~action ~body =
  let base =
    [ "Content-Type", "application/x-amz-json-1.0"; "X-Amz-Target", "DynamoDB_20120810." ^ action ]
  in
  let credentials = Sigv4.Credentials.fetch () in
  let signed =
    Sigv4.sign ~now ~credentials ~region ~service:"dynamodb" ~http_method:"POST" ~payload:body ~uri
      base
  in
  Http.Header.of_list (base @ signed)

module Call = struct
  let run ?(max_response_size = default_max_response_size) ~now ~client
    ~config:Config.{ endpoint; region } k =
    let uri = if Uri.path endpoint = "" then Uri.with_path endpoint "/" else endpoint in
    try k ()
    with effect Dynamodb.Effects.Call { action; body }, k -> (
      (* Exceptions go to the perform site via [discontinue], not out of the handler frame. *)
      match
        let headers = signed_headers ~now ~region ~uri ~action ~body in
        let body = Cohttp_eio.Body.of_string body in
        Eio.Switch.run @@ fun sw ->
        let response, body_reader = Cohttp_eio.Client.call ~sw ~headers ~body client `POST uri in
        let status = Http.Response.status response |> Http.Status.to_int in
        let body =
          Eio.Buf_read.of_flow ~max_size:max_response_size body_reader |> Eio.Buf_read.take_all
        in
        match status with
        | _ when status < 300 -> Ok (Yojson.Safe.from_string body)
        | _ when status < 500 -> Error body
        | _ -> failwith @@ Printf.sprintf "DynamoDB request failed with status %d: %s" status body
      with
      | response -> Effect.Deep.continue k response
      | exception exn -> Effect.Deep.discontinue k exn)
end

let run ?max_response_size ~now ~client ~config k =
  Sigv4_cohttp_eio.run ~now ~client @@ fun () -> Call.run ?max_response_size ~now ~client ~config k
