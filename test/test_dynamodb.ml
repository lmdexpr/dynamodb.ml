module Item = Dynamodb.Item
module Client = Dynamodb.Client
module Value = Dynamodb.Value
module Number = Dynamodb.Number
module Projection = Dynamodb.Projection

let json = Alcotest.testable Yojson.Safe.pp Yojson.Safe.equal

let item =
  Alcotest.testable
    (fun fmt i ->
      Yojson.Safe.pp fmt
        Dynamodb.Action.Put_item.(make ~table_name:"t" ~item:i () |> yojson_of_request))
    Item.equal

let parse = Yojson.Safe.from_string

let with_stub ~(respond : action:string -> body:string -> (Yojson.Safe.t, string) result) k =
  try k ()
  with effect Dynamodb.Effects.Call { action; body }, k ->
    Effect.Deep.continue k (respond ~action ~body)

let record ~response =
  let seen = ref [] in
  let respond ~action ~body =
    seen := (action, parse body) :: !seen;
    response
  in
  seen, respond

let db = Client.make ~table:"example-table"
let alice = Item.(empty |> add "pk" (Value.String "alice") |> add "age" (Value.int 30))
let alice_key = Item.singleton "pk" (Value.String "alice")
let json_item xs = Projection.item_of_yojson_exn (`Assoc xs)
let unwrap = function Ok x -> x | Error e -> Alcotest.fail e

(* Wire envelope *)

let test_wire_encodes_every_json_kind () =
  let item =
    json_item
      [
        "s", `String "x";
        "i", `Int 1;
        "f", `Float 1.5;
        "b", `Bool true;
        "n", `Null;
        "l", `List [ `Int 1; `String "y" ];
        "m", `Assoc [ "k", `Bool false ];
      ]
  in
  Alcotest.check json "PutItem body"
    (parse
       {|{"TableName":"example-table","Item":{"b":{"BOOL":true},"f":{"N":"1.5"},"i":{"N":"1"},
          "l":{"L":[{"N":"1"},{"S":"y"}]},"m":{"M":{"k":{"BOOL":false}}},"n":{"NULL":true},"s":{"S":"x"}}}|})
    Dynamodb.Action.Put_item.(make ~table_name:"example-table" ~item () |> yojson_of_request)

let test_wire_decodes_numbers_and_sets () =
  let Dynamodb.Action.Get_item.{ item = decoded } =
    Dynamodb.Action.Get_item.response_of_yojson
      (parse
         {|{"Item":{"i":{"N":"42"},"f":{"N":"0.5"},"ss":{"SS":["a","b"]},"ns":{"NS":["1","2.5"]}}}|})
  in
  Alcotest.(check (option item))
    "decoded"
    (Some
       (Item.of_list
          [
            "i", Value.int 42;
            "f", Value.Number (Number.of_string_exn "0.5");
            "ss", Value.String_set (unwrap (Value.String_set.of_list [ "a"; "b" ]));
            ( "ns",
              Value.Number_set
                (unwrap (Value.Number_set.of_list [ Number.of_int 1; Number.of_string_exn "2.5" ]))
            );
          ]))
    decoded

let test_wire_numbers_round_trip () =
  let big = "12345678901234567890123456789012345678" in
  let third = 1.0 /. 3.0 in
  let numbers = json_item [ "big", `Intlit big; "third", `Float third; "tenth", `Float 0.1 ] in
  let wire =
    Dynamodb.Action.Put_item.(make ~table_name:"t" ~item:numbers () |> yojson_of_request)
    |> Yojson.Safe.Util.member "Item"
  in
  Alcotest.check json "encoded"
    (parse
       {|{"big":{"N":"12345678901234567890123456789012345678"},"tenth":{"N":"0.1"},"third":{"N":"0.33333333333333331"}}|})
    wire;
  let Dynamodb.Action.Get_item.{ item = decoded } =
    Dynamodb.Action.Get_item.response_of_yojson (`Assoc [ "Item", wire ])
  in
  Alcotest.(check (option item)) "decoded" (Some numbers) decoded

(* Absent optional fields must be omitted, not null. *)

let query ?limit ?scan_index_forward () =
  Dynamodb.Action.Query.(
    make ?limit ?scan_index_forward ~table_name:"example-table"
      ~key_condition_expression:"#pk = :pk"
      ~expression_attribute_names:[ "#pk", "pk" ]
      ~expression_attribute_values:(Item.singleton ":pk" (Value.String "alice"))
      ()
    |> yojson_of_request)

let test_query_omits_absent_fields () =
  Alcotest.check json "no Limit / ScanIndexForward"
    (parse
       {|{"TableName":"example-table","KeyConditionExpression":"#pk = :pk","ExpressionAttributeNames":{"#pk":"pk"},"ExpressionAttributeValues":{":pk":{"S":"alice"}}}|})
    (query ())

let test_query_emits_limit_and_direction () =
  Alcotest.check json "Limit and ScanIndexForward"
    (parse
       {|{"TableName":"example-table","KeyConditionExpression":"#pk = :pk","ExpressionAttributeNames":{"#pk":"pk"},"ExpressionAttributeValues":{":pk":{"S":"alice"}},"Limit":10,"ScanIndexForward":false}|})
    (query ~limit:10 ~scan_index_forward:false ())

(* Client helpers through the effect *)

let test_get () =
  let seen, respond =
    record ~response:(Ok (parse {|{"Item":{"pk":{"S":"alice"},"age":{"N":"30"}}}|}))
  in
  let result = with_stub ~respond @@ fun () -> Client.get db ~key:alice_key in
  Alcotest.(check (list (pair string json)))
    "request"
    [ "GetItem", parse {|{"TableName":"example-table","Key":{"pk":{"S":"alice"}}}|} ]
    !seen;
  Alcotest.(check (result (option item) reject)) "response" (Ok (Some alice)) result

let test_scan_follows_pagination () =
  let pages =
    ref
      [
        {|{"Items":[{"pk":{"S":"a"}}],"LastEvaluatedKey":{"pk":{"S":"a"}}}|};
        {|{"Items":[{"pk":{"S":"b"}}]}|};
      ]
  in
  let requests = ref [] in
  let respond ~action:_ ~body =
    requests := parse body :: !requests;
    match !pages with
    | page :: rest ->
      pages := rest;
      Ok (parse page)
    | [] -> Alcotest.fail "scanned past the last page"
  in
  let result = with_stub ~respond @@ fun () -> Client.scan db in
  Alcotest.(check (result (list item) reject))
    "all items in order"
    (Ok [ Item.singleton "pk" (Value.String "a"); Item.singleton "pk" (Value.String "b") ])
    result;
  Alcotest.(check (list json))
    "second request carries ExclusiveStartKey"
    [
      parse {|{"TableName":"example-table"}|};
      parse {|{"TableName":"example-table","ExclusiveStartKey":{"pk":{"S":"a"}}}|};
    ]
    (List.rev !requests)

let test_update_requests_all_new () =
  let seen, respond =
    record ~response:(Ok (parse {|{"Attributes":{"pk":{"S":"alice"},"age":{"N":"31"}}}|}))
  in
  let result =
    with_stub ~respond @@ fun () ->
    Client.update db ~key:alice_key ~update_expression:"SET age = :age"
      ~expression_attribute_values:(Item.singleton ":age" (Value.int 31))
  in
  Alcotest.(check (list (pair string json)))
    "request"
    [
      ( "UpdateItem",
        parse
          {|{"TableName":"example-table","Key":{"pk":{"S":"alice"}},"UpdateExpression":"SET age = :age","ExpressionAttributeValues":{":age":{"N":"31"}},"ReturnValues":"ALL_NEW"}|}
      );
    ]
    !seen;
  Alcotest.(check (result (option item) reject))
    "response"
    (Ok (Some (Item.add "age" (Value.int 31) alice)))
    result

let test_transact_write () =
  let seen, respond = record ~response:(Ok (`Assoc [])) in
  let result =
    with_stub ~respond @@ fun () ->
    Dynamodb.Transaction.(
      write
        [
          put_if_not_exists ~table_name:"example-table" ~item:alice ~primary_key:"pk";
          delete ~table_name:"example-table" ~key:(Item.singleton "pk" (Value.String "bob")) ();
        ])
  in
  Alcotest.(check (result unit reject)) "ok" (Ok ()) result;
  Alcotest.(check (list (pair string json)))
    "request"
    [
      ( "TransactWriteItems",
        parse
          {|{"TransactItems":[
              {"Put":{"TableName":"example-table","Item":{"age":{"N":"30"},"pk":{"S":"alice"}},"ConditionExpression":"attribute_not_exists(#pk)","ExpressionAttributeNames":{"#pk":"pk"}}},
              {"Delete":{"TableName":"example-table","Key":{"pk":{"S":"bob"}}}}]}|}
      );
    ]
    !seen

(* Errors *)

let error =
  Alcotest.testable (fun fmt e -> Format.pp_print_string fmt (Dynamodb.Error.to_string e)) ( = )

let test_conditional_check_failed () =
  let body =
    {|{"__type":"com.amazonaws.dynamodb.v20120810#ConditionalCheckFailedException","message":"The conditional request failed"}|}
  in
  let result =
    with_stub ~respond:(fun ~action:_ ~body:_ -> Error body) @@ fun () ->
    Client.put_if_not_exists db ~item:alice ~primary_key:"pk"
  in
  match result with
  | Error e ->
    Alcotest.(check bool) "recognized" true (Dynamodb.Error.is_conditional_check_failed e);
    Alcotest.(check string) "code" "ConditionalCheckFailedException" e.code;
    Alcotest.(check (option string)) "message" (Some "The conditional request failed") e.message
  | Ok () -> Alcotest.fail "expected an error"

let test_transaction_cancelled_by_condition () =
  let e =
    Dynamodb.Error.of_body
      {|{"__type":"com.amazonaws.dynamodb.v20120810#TransactionCanceledException","CancellationReasons":[{"Code":"None"},{"Code":"ConditionalCheckFailed","Message":"The conditional request failed"}]}|}
  in
  Alcotest.(check bool) "recognized" true (Dynamodb.Error.is_conditional_check_failed e);
  Alcotest.(check (list string))
    "reasons"
    [ "None"; "ConditionalCheckFailed" ]
    e.cancellation_reasons

let test_unparseable_error_keeps_body () =
  let e = Dynamodb.Error.of_body "<html>gateway</html>" in
  Alcotest.check error "raw body"
    { code = ""; message = None; cancellation_reasons = []; body = "<html>gateway</html>" }
    e;
  Alcotest.(check bool) "not conditional" false (Dynamodb.Error.is_conditional_check_failed e)

let () =
  Alcotest.run "dynamodb"
    [
      ( "wire",
        [
          Alcotest.test_case "encodes every JSON kind" `Quick test_wire_encodes_every_json_kind;
          Alcotest.test_case "decodes numbers and sets" `Quick test_wire_decodes_numbers_and_sets;
          Alcotest.test_case "numbers round-trip" `Quick test_wire_numbers_round_trip;
        ] );
      ( "query",
        [
          Alcotest.test_case "omits absent fields" `Quick test_query_omits_absent_fields;
          Alcotest.test_case "emits limit and direction" `Quick test_query_emits_limit_and_direction;
        ] );
      ( "client",
        [
          Alcotest.test_case "get" `Quick test_get;
          Alcotest.test_case "scan follows pagination" `Quick test_scan_follows_pagination;
          Alcotest.test_case "update requests ALL_NEW" `Quick test_update_requests_all_new;
          Alcotest.test_case "transact write" `Quick test_transact_write;
        ] );
      ( "error",
        [
          Alcotest.test_case "conditional check failed" `Quick test_conditional_check_failed;
          Alcotest.test_case "transaction cancelled by condition" `Quick
            test_transaction_cancelled_by_condition;
          Alcotest.test_case "unparseable body" `Quick test_unparseable_error_keeps_body;
        ] );
    ]
