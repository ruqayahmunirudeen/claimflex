;; --------------------------------------------------
;; Contract: claimdrop-plus-extended
;; --------------------------------------------------

;; === Constants ===
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_CLAIMED (err u101))
(define-constant ERR_NOT_ELIGIBLE (err u102))
(define-constant ERR_INSUFFICIENT_BALANCE (err u103))
(define-constant ERR_CLAIM_DEADLINE_PASSED (err u104))
(define-constant ERR_ALREADY_RECLAIMED (err u106))
(define-constant ERR_CLAIM_PAUSED (err u107))
(define-constant ERR_BELOW_MIN_THRESHOLD (err u108))

;; === Admin Control ===
(define-data-var contract-owner principal tx-sender)

;; === Claimable STX Map ===
(define-map claimable-stx principal uint)

;; === Claim Status Map ===
(define-map has-claimed principal bool)

;; === Track Totals ===
(define-data-var total-assigned uint u0)
(define-data-var total-claimed uint u0)

;; === Claim Deadline ===
(define-data-var claim-deadline (optional uint) none)

;; === Claim Pause Status ===
(define-data-var claim-paused bool false)

;; === Minimum Claimable Amount ===
(define-data-var min-claim-amount uint u1)

;; === Admin: Assign airdrop to one user ===
(define-public (set-claimable (user principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (map-set claimable-stx user amount)
    (var-set total-assigned (+ (var-get total-assigned) amount))
    (ok true)
  )
)

;; === Batch Assignment Helper ===
(define-private (batch-assign-helper (user-amt (tuple (user principal) (amt uint))) (acc bool))
  (let ((user (get user user-amt))
        (amt (get amt user-amt)))
    (begin
      (map-set claimable-stx user amt)
      (var-set total-assigned (+ (var-get total-assigned) amt))
      acc)))

;; === Admin: Batch Assign ===
(define-public (batch-assign (users-amounts (list 50 (tuple (user principal) (amt uint)))))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (fold batch-assign-helper users-amounts true)
    (ok true)))

;; === User: Claim STX ===
(define-public (claim)
  (let (
        (amount (default-to u0 (map-get? claimable-stx tx-sender)))
        (already-claimed (default-to false (map-get? has-claimed tx-sender)))
        (deadline (var-get claim-deadline))
        ;; use global block-height directly, no need to bind
        (min-threshold (var-get min-claim-amount)))
    (begin
      (asserts! (is-eq (var-get claim-paused) false) ERR_CLAIM_PAUSED)
      (asserts! (is-eq already-claimed false) ERR_ALREADY_CLAIMED)
      (asserts! (> amount u0) ERR_NOT_ELIGIBLE)
      (asserts! (>= amount min-threshold) ERR_BELOW_MIN_THRESHOLD)
      (match deadline
        deadline-value
        (asserts! (<= stacks-block-height deadline-value) ERR_CLAIM_DEADLINE_PASSED)
        true)
      (try! (stx-transfer? amount (as-contract tx-sender) tx-sender))
      (map-set has-claimed tx-sender true)
      (map-delete claimable-stx tx-sender)
      (var-set total-claimed (+ (var-get total-claimed) amount))
      (print {event: "claim", user: tx-sender, amount: amount})
      (ok amount))))

;; === Admin: Reclaim unclaimed STX ===
(define-public (reclaim-unclaimed (user principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (let ((amount (default-to u0 (map-get? claimable-stx user)))
          (claimed (default-to false (map-get? has-claimed user))))
      (if (is-eq claimed false)
          (begin
            (map-delete claimable-stx user)
            (var-set total-assigned (- (var-get total-assigned) amount))
            (ok amount))
          ERR_ALREADY_RECLAIMED))))

;; === Admin: Reclaim All Expired Claims ===
(define-private (reclaim-expired-helper (user principal) (acc bool))
  (let (
        (amount (default-to u0 (map-get? claimable-stx user)))
        (claimed (default-to false (map-get? has-claimed user))))
    (if (and (not claimed) (> amount u0))
        (begin
          (map-delete claimable-stx user)
          (var-set total-assigned (- (var-get total-assigned) amount))
          acc)
        acc)))

(define-public (reclaim-expired (users (list 100 principal)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (match (var-get claim-deadline)
      deadline
      (begin
        (asserts! (< deadline stacks-block-height) ERR_CLAIM_DEADLINE_PASSED)
        (fold reclaim-expired-helper users true)
        (ok true))
      (err u500) ;; fallback if deadline is none
    )))

;; === Admin: Set claim deadline ===
(define-public (set-claim-deadline (block uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set claim-deadline (some block))
    (ok true)))

;; === Admin: Withdraw unused STX ===
(define-public (withdraw-unused (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (try! (stx-transfer? amount (as-contract tx-sender) recipient))
    (ok true)))

;; === Admin: Transfer Ownership ===
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)))

;; === Admin: Pause or Unpause Claiming ===
(define-public (set-claim-paused (status bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set claim-paused status)
    (ok true)))

;; === Admin: Set Minimum Threshold ===
(define-public (set-min-claim (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
    (var-set min-claim-amount amount)
    (ok true)))

;; === Read-Only: Check eligibility ===
(define-read-only (check-eligibility (user principal))
  (let ((amount (default-to u0 (map-get? claimable-stx user)))
        (claimed (default-to false (map-get? has-claimed user))))
    (ok (and (> amount u0) (not claimed)))))

;; === Read-Only: Has user claimed? ===
(define-read-only (has-user-claimed (user principal))
  (ok (default-to false (map-get? has-claimed user))))

;; === Read-Only: Get owner ===
(define-read-only (get-owner)
  (ok (var-get contract-owner)))

;; === Read-Only: Get deadline ===
(define-read-only (get-deadline)
  (ok (var-get claim-deadline)))

;; === Read-Only: Get total assigned ===
(define-read-only (get-total-assigned)
  (ok (var-get total-assigned)))

;; === Read-Only: Get total claimed ===
(define-read-only (get-total-claimed)
  (ok (var-get total-claimed)))

;; === Read-Only: Get claimable amount ===
(define-read-only (get-claimable (user principal))
  (ok (default-to u0 (map-get? claimable-stx user))))
