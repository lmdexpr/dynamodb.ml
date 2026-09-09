# dynamodb.ml

OCaml client for the [Amazon DynamoDB HTTP API][api] (JSON 1.0 protocol).

- `dynamodb`: request encoding, response decoding, error parsing. Items carry every DynamoDB attribute type; numbers are exact decimals.
  HTTP goes through the effect `Dynamodb.Effects.Call`. Depends on `yojson`, `base64` and `ppx_yojson_conv`.
- `dynamodb-cohttp-eio`: handles that effect with [cohttp-eio][cohttp-eio], signing with [sigv4][sigv4].

Supported: `PutItem`, `GetItem`, `DeleteItem`, `UpdateItem` (`ReturnValues = ALL_NEW`), `Query` (all pages without `limit`, one page with `limit`), `Scan` (all pages), `TransactWriteItems` (`Put` / `Delete`).
Not supported: `BatchGetItem`, `BatchWriteItem`, `IndexName`, `ConsistentRead`, `ProjectionExpression`, other `ReturnValues`, and `Update` / `ConditionCheck` transact items.

[api]: https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/Welcome.html
[sigv4]: https://github.com/lmdexpr/sigv4.ml
[cohttp-eio]: https://github.com/mirage/ocaml-cohttp

## Install

Not on the opam repository yet.

```sh
opam pin add dynamodb https://github.com/lmdexpr/dynamodb.ml.git
opam pin add dynamodb-cohttp-eio https://github.com/lmdexpr/dynamodb.ml.git
```

## Usage

```ocaml
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type user = { pk : string; name : string } [@@deriving yojson]

let () =
  Eio_main.run @@ fun env ->
  let client = Cohttp_eio.Client.make ~https:None env#net in
  let now () = Eio.Time.now env#clock in
  let config = Dynamodb_cohttp_eio.Config.local () in
  Dynamodb_cohttp_eio.run ~now ~client ~config @@ fun () ->
  let db = Dynamodb.Client.make ~table:"users" in
  let item = yojson_of_user { pk = "alice"; name = "Alice" } |> Dynamodb.Projection.item_of_yojson_exn in
  match Dynamodb.Client.put db ~item with
  | Error e -> prerr_endline (Dynamodb.Error.to_string e)
  | Ok () -> (
    match Dynamodb.Client.get db ~key:(Dynamodb.Item.singleton "pk" (Dynamodb.Value.String "alice")) with
    | Ok (Some item) -> print_endline (Dynamodb.Projection.yojson_of_item_exn item |> user_of_yojson).name
    | Ok None -> print_endline "not found"
    | Error e -> prerr_endline (Dynamodb.Error.to_string e))
```

- `Config.local ()` targets `http://127.0.0.1:8000`; `Config.aws ~region` targets the regional endpoint over HTTPS, which needs an `~https` TLS wrapper on the cohttp-eio client.
- Credentials come from `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` or the ECS container endpoint (`sigv4-cohttp-eio`).
- Every `Client` function returns `(_, Dynamodb.Error.t) result`. `Error.is_conditional_check_failed` recognizes failed conditions, including cancelled transactions.
- Expressions (`condition_expression`, `key_condition_expression`, ...) are raw strings. Pass values through `expression_attribute_values`, never by string concatenation.
- `Dynamodb.Action.<Name>.(make ... |> perform)` is the layer under `Client`.
  `Dynamodb.Transaction.write` takes items built with `Transaction.put` / `Transaction.delete`.

Handling the effect yourself, e.g. in tests:

```ocaml
let with_stub ~respond k =
  try k ()
  with effect Dynamodb.Effects.Call { action; body }, k ->
    Effect.Deep.continue k (respond ~action ~body)
```

`respond` returns `Ok json` for a 2xx body or `Error body` for a 4xx body.

## Values and JSON

`Item.t` maps names to `Value.t`: `String`, `Number`, `Binary` (raw bytes), `Bool`, `Null`, `List`, `Map`, `String_set`, `Number_set`, `Binary_set`. Reading an item and writing it back preserves attribute types and decimal digits.

`Number.t` is an exact decimal: 38 significant digits, adjusted exponent -130 to 125. `Number.of_string`, `of_float` and `to_int` return `result`; `to_float` may round. Set constructors reject empty sets and duplicates (`1` and `1.0` are duplicates).

`Projection` converts to and from ordinary JSON, e.g. for `[@@deriving yojson]` records. `Projection.item_of_yojson` reads objects, arrays, strings and numbers as `Map`, `List`, `String` and `Number`. `Projection.yojson_of_item` takes a policy for each thing JSON cannot represent:

| Option | Default | Alternatives |
| --- | --- | --- |
| `numbers` | `Float`: fractions round to floats, integers stay `Int` / `Intlit` | `Exact`: reject fractions; `String`: decimal strings |
| `sets` | `Reject` | `Lists` |
| `binary` | `Reject` | `Base64` |

Errors carry a path such as `$["events"][0]`; `_exn` variants raise `Projection.Conversion_error`. Malformed wire values in a response raise `Ppx_yojson_conv_lib.Yojson_conv.Of_yojson_error` with the same kind of path.

## Development

```sh
opam switch create . 5.5.1 --no-install -y
opam install dune -y
dune build
dune runtest
dune fmt
```

## License

[MIT](./LICENSE)
