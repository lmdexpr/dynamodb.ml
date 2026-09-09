(lang dune 3.23)

(implicit_transitive_deps false)

(generate_opam_files true)

(name dynamodb)

(source
 (github lmdexpr/dynamodb.ml))

(license MIT)

(authors "Yuki Tajiri")

(maintainers "Yuki Tajiri")

;; sigv4 / sigv4-cohttp-eio are not yet published to the opam repository; pin them ; straight from the upstream repo.
(pin
 (url
  "git+https://github.com/lmdexpr/sigv4.ml.git#9a2e7247de94b9023e41f0217e8b9bc7eb14b926")
 (package
  (name sigv4)
  (version "dev")))

(pin
 (url
  "git+https://github.com/lmdexpr/sigv4.ml.git#9a2e7247de94b9023e41f0217e8b9bc7eb14b926")
 (package
  (name sigv4-cohttp-eio)
  (version "dev")))

(package
 (name dynamodb)
 (synopsis "DynamoDB JSON 1.0 protocol: requests, responses, errors")
 (description
  "Request encoding, response decoding and error parsing for PutItem, GetItem,\nDeleteItem, UpdateItem, Query, Scan and TransactWriteItems. Items carry every\nDynamoDB attribute type; numbers are exact decimals. HTTP goes through the\neffect Dynamodb.Effects.Call; see dynamodb-cohttp-eio for a handler.")
 (depends
  (ocaml
   (>= 5.3.0))
  dune
  yojson
  base64
  ppx_yojson_conv
  (alcotest :with-test)))

(package
 (name dynamodb-cohttp-eio)
 (synopsis "Cohttp-eio handler for dynamodb: endpoint, SigV4 signing, HTTP")
 (description
  "Handles Dynamodb.Effects.Call with a cohttp-eio client, signing requests with\nsigv4 and resolving credentials with sigv4-cohttp-eio.")
 (depends
  (ocaml
   (>= 5.3.0))
  dune
  (dynamodb
   (= :version))
  sigv4
  sigv4-cohttp-eio
  eio
  cohttp-eio
  uri
  http
  yojson
  (eio_main :with-test)))
