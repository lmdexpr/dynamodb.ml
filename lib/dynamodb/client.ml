open Result.Syntax

type t = { table : string }

let make ~table = { table }
let table { table } = table

let put ?condition_expression ?expression_attribute_names ?expression_attribute_values { table }
  ~item =
  Action.Put_item.make ?condition_expression ?expression_attribute_names
    ?expression_attribute_values ~table_name:table ~item ()
  |> Action.Put_item.perform

let put_if_not_exists t ~item ~primary_key =
  put t ~item ~condition_expression:"attribute_not_exists(#pk)"
    ~expression_attribute_names:[ "#pk", primary_key ]

let compare_and_swap t ~item ~attribute ~expected =
  put t ~item ~condition_expression:"#attr = :expected"
    ~expression_attribute_names:[ "#attr", attribute ]
    ~expression_attribute_values:(Item.singleton ":expected" expected)

let delete ?condition_expression ?expression_attribute_names ?expression_attribute_values { table }
  ~key =
  Action.Delete_item.make ?condition_expression ?expression_attribute_names
    ?expression_attribute_values ~table_name:table ~key ()
  |> Action.Delete_item.perform

let compare_and_delete t ~key ~attribute ~expected =
  delete t ~key ~condition_expression:"#attr = :expected"
    ~expression_attribute_names:[ "#attr", attribute ]
    ~expression_attribute_values:(Item.singleton ":expected" expected)

let update { table } ~key ~update_expression ~expression_attribute_values =
  let* Action.Update_item.{ attributes } =
    Action.Update_item.make ~table_name:table ~key ~update_expression ~expression_attribute_values
    |> Action.Update_item.perform
  in
  Ok attributes

let get { table } ~key =
  let* Action.Get_item.{ item } =
    Action.Get_item.make ~table_name:table ~key |> Action.Get_item.perform
  in
  Ok item

let query ?filter_expression ?expression_attribute_names ?limit ?scan_index_forward { table }
  ~key_condition_expression ~expression_attribute_values =
  let rec go acc exclusive_start_key =
    let* Action.Query.{ items; last_evaluated_key } =
      Action.Query.make ?filter_expression ?expression_attribute_names ?limit ?scan_index_forward
        ?exclusive_start_key ~table_name:table ~key_condition_expression
        ~expression_attribute_values ()
      |> Action.Query.perform
    in
    let acc = List.rev_append items acc in
    match limit, last_evaluated_key with
    | None, Some key -> go acc (Some key)
    | _ -> Ok (List.rev acc)
  in
  go [] None

let scan { table } =
  let rec go acc exclusive_start_key =
    let* Action.Scan.{ items; last_evaluated_key } =
      Action.Scan.make ?exclusive_start_key ~table_name:table () |> Action.Scan.perform
    in
    let acc = List.rev_append items acc in
    match last_evaluated_key with None -> Ok (List.rev acc) | Some key -> go acc (Some key)
  in
  go [] None
