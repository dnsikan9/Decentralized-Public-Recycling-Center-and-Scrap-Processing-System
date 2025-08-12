;; Recycling Facility Licensing Contract
;; Manages permits and licenses for recycling operations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-FACILITY-EXISTS (err u101))
(define-constant ERR-FACILITY-NOT-FOUND (err u102))
(define-constant ERR-INVALID-MATERIAL-TYPE (err u103))
(define-constant ERR-LICENSE-EXPIRED (err u104))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u105))

;; Data Variables
(define-data-var next-facility-id uint u1)
(define-data-var licensing-fee uint u1000000) ;; 1 STX in microSTX

;; Data Maps
(define-map facilities
  { facility-id: uint }
  {
    owner: principal,
    name: (string-ascii 100),
    location: (string-ascii 200),
    material-types: (list 10 (string-ascii 20)),
    license-expiry: uint,
    is-active: bool,
    compliance-score: uint
  }
)

(define-map facility-by-owner
  { owner: principal }
  { facility-id: uint }
)

(define-map material-processing-capacity
  { facility-id: uint, material-type: (string-ascii 20) }
  { daily-capacity: uint, current-load: uint }
)

;; Public Functions

;; Register a new recycling facility
(define-public (register-facility
  (name (string-ascii 100))
  (location (string-ascii 200))
  (material-types (list 10 (string-ascii 20))))
  (let
    (
      (facility-id (var-get next-facility-id))
      (expiry-block (+ block-height u52560)) ;; ~1 year in blocks
    )
    (asserts! (is-valid-material-types material-types) ERR-INVALID-MATERIAL-TYPE)
    (asserts! (is-none (map-get? facility-by-owner { owner: tx-sender })) ERR-FACILITY-EXISTS)

    ;; Transfer licensing fee
    (try! (stx-transfer? (var-get licensing-fee) tx-sender CONTRACT-OWNER))

    ;; Store facility data
    (map-set facilities
      { facility-id: facility-id }
      {
        owner: tx-sender,
        name: name,
        location: location,
        material-types: material-types,
        license-expiry: expiry-block,
        is-active: true,
        compliance-score: u100
      }
    )

    (map-set facility-by-owner
      { owner: tx-sender }
      { facility-id: facility-id }
    )

    ;; Initialize processing capacities
    (try! (initialize-capacities facility-id material-types))

    ;; Increment facility ID counter
    (var-set next-facility-id (+ facility-id u1))

    (ok facility-id)
  )
)

;; Renew facility license
(define-public (renew-license (facility-id uint))
  (let
    (
      (facility (unwrap! (map-get? facilities { facility-id: facility-id }) ERR-FACILITY-NOT-FOUND))
      (new-expiry (+ block-height u52560))
    )
    (asserts! (is-eq (get owner facility) tx-sender) ERR-NOT-AUTHORIZED)

    ;; Transfer renewal fee
    (try! (stx-transfer? (var-get licensing-fee) tx-sender CONTRACT-OWNER))

    ;; Update license expiry
    (map-set facilities
      { facility-id: facility-id }
      (merge facility { license-expiry: new-expiry })
    )

    (ok new-expiry)
  )
)

;; Update facility compliance score
(define-public (update-compliance-score (facility-id uint) (new-score uint))
  (let
    (
      (facility (unwrap! (map-get? facilities { facility-id: facility-id }) ERR-FACILITY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-score u100) ERR-INVALID-MATERIAL-TYPE)

    (map-set facilities
      { facility-id: facility-id }
      (merge facility { compliance-score: new-score })
    )

    (ok new-score)
  )
)

;; Set processing capacity for a material type
(define-public (set-processing-capacity
  (facility-id uint)
  (material-type (string-ascii 20))
  (daily-capacity uint))
  (let
    (
      (facility (unwrap! (map-get? facilities { facility-id: facility-id }) ERR-FACILITY-NOT-FOUND))
    )
    (asserts! (is-eq (get owner facility) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-material-type material-type) ERR-INVALID-MATERIAL-TYPE)

    (map-set material-processing-capacity
      { facility-id: facility-id, material-type: material-type }
      { daily-capacity: daily-capacity, current-load: u0 }
    )

    (ok daily-capacity)
  )
)

;; Read-only Functions

;; Get facility details
(define-read-only (get-facility (facility-id uint))
  (map-get? facilities { facility-id: facility-id })
)

;; Get facility by owner
(define-read-only (get-facility-by-owner (owner principal))
  (map-get? facility-by-owner { owner: owner })
)

;; Check if facility license is valid
(define-read-only (is-license-valid (facility-id uint))
  (match (map-get? facilities { facility-id: facility-id })
    facility (and
               (get is-active facility)
               (> (get license-expiry facility) block-height))
    false
  )
)

;; Get processing capacity
(define-read-only (get-processing-capacity (facility-id uint) (material-type (string-ascii 20)))
  (map-get? material-processing-capacity { facility-id: facility-id, material-type: material-type })
)

;; Private Functions

;; Validate material types
(define-private (is-valid-material-types (material-types (list 10 (string-ascii 20))))
  (let
    (
      (valid-types (list "metal" "plastic" "paper" "glass" "electronics"))
    )
    (fold check-material-type material-types true)
  )
)

;; Check individual material type
(define-private (check-material-type (material-type (string-ascii 20)) (acc bool))
  (and acc (is-valid-material-type material-type))
)

;; Validate single material type
(define-private (is-valid-material-type (material-type (string-ascii 20)))
  (or
    (is-eq material-type "metal")
    (is-eq material-type "plastic")
    (is-eq material-type "paper")
    (is-eq material-type "glass")
    (is-eq material-type "electronics")
  )
)

;; Initialize processing capacities for all material types
(define-private (initialize-capacities (facility-id uint) (material-types (list 10 (string-ascii 20))))
  (fold initialize-single-capacity material-types (ok true))
)

;; Initialize capacity for single material type
(define-private (initialize-single-capacity (material-type (string-ascii 20)) (acc (response bool uint)))
  (match acc
    success (begin
              (map-set material-processing-capacity
                { facility-id: (var-get next-facility-id), material-type: material-type }
                { daily-capacity: u1000, current-load: u0 }
              )
              (ok true)
            )
    error acc
  )
)
