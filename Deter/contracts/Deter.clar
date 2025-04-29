;; EnergyFlow - Decentralized Energy Trading Smart Contract

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-enough-balance (err u101))
(define-constant err-transfer-failed (err u102))
(define-constant err-invalid-price (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-invalid-fee (err u105))
(define-constant err-refund-failed (err u106))
(define-constant err-same-user (err u107))
(define-constant err-pool-limit-exceeded (err u108))
(define-constant err-invalid-pool-limit (err u109))

;; Define data variables
(define-data-var watt-price uint u100) ;; Price per kWh in microstacks (1 STX = 1,000,000 microstacks)
(define-data-var max-watt-per-user uint u10000) ;; Maximum energy a user can add (in kWh)
(define-data-var service-fee-rate uint u5) ;; Commission rate in percentage (e.g., 5 means 5%)
(define-data-var buyback-rate uint u90) ;; Refund rate in percentage (e.g., 90 means 90% of current price)
(define-data-var watt-pool-limit uint u1000000) ;; Global energy pool limit (in kWh)
(define-data-var current-watt-pool uint u0) ;; Current total energy in the system (in kWh)

;; Define data maps
(define-map user-watt-balance principal uint)
(define-map user-stx-balance principal uint)
(define-map watt-listing {user: principal} {amount: uint, price: uint})

;; Private functions

;; Calculate service fee
(define-private (calculate-service-fee (amount uint))
  (/ (* amount (var-get service-fee-rate)) u100))

;; Calculate buyback amount
(define-private (calculate-buyback (amount uint))
  (/ (* amount (var-get watt-price) (var-get buyback-rate)) u100))

;; Update watt pool
(define-private (update-watt-pool (amount int))
  (let (
    (current-pool (var-get current-watt-pool))
    (new-pool (if (< amount 0)
                     (if (>= current-pool (to-uint (- 0 amount)))
                         (- current-pool (to-uint (- 0 amount)))
                         u0)
                     (+ current-pool (to-uint amount))))
  )
    (asserts! (<= new-pool (var-get watt-pool-limit)) err-pool-limit-exceeded)
    (var-set current-watt-pool new-pool)
    (ok true)))

;; Public functions

;; Set watt price (only contract owner)
(define-public (set-watt-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-price u0) err-invalid-price) ;; Ensure price is greater than 0
    (var-set watt-price new-price)
    (ok true)))

;; Set service fee rate (only contract owner)
(define-public (set-service-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u100) err-invalid-fee) ;; Ensure rate is not more than 100%
    (var-set service-fee-rate new-rate)
    (ok true)))

;; Set buyback rate (only contract owner)
(define-public (set-buyback-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u100) err-invalid-fee) ;; Ensure rate is not more than 100%
    (var-set buyback-rate new-rate)
    (ok true)))

;; Set watt pool limit (only contract owner)
(define-public (set-watt-pool-limit (new-limit uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (>= new-limit (var-get current-watt-pool)) err-invalid-pool-limit)
    (var-set watt-pool-limit new-limit)
    (ok true)))

;; List watts for sale
(define-public (list-watts-for-sale (amount uint) (price uint))
  (let (
    (current-balance (default-to u0 (map-get? user-watt-balance tx-sender)))
    (current-listed (get amount (default-to {amount: u0, price: u0} (map-get? watt-listing {user: tx-sender}))))
    (new-listed (+ amount current-listed))
  )
    (asserts! (> amount u0) err-invalid-amount) ;; Ensure amount is greater than 0
    (asserts! (> price u0) err-invalid-price) ;; Ensure price is greater than 0
    (asserts! (>= current-balance new-listed) err-not-enough-balance)
    (try! (update-watt-pool (to-int amount)))
    (map-set watt-listing {user: tx-sender} {amount: new-listed, price: price})
    (ok true)))

;; Delist watts from sale
(define-public (delist-watts (amount uint))
  (let (
    (current-listed (get amount (default-to {amount: u0, price: u0} (map-get? watt-listing {user: tx-sender}))))
  )
    (asserts! (>= current-listed amount) err-not-enough-balance)
    (try! (update-watt-pool (to-int (- amount))))
    (map-set watt-listing {user: tx-sender} 
             {amount: (- current-listed amount), 
              price: (get price (default-to {amount: u0, price: u0} (map-get? watt-listing {user: tx-sender})))})
    (ok true)))

;; Buy watts from user
(define-public (buy-watts-from-user (seller principal) (amount uint))
  (let (
    (listing-data (default-to {amount: u0, price: u0} (map-get? watt-listing {user: seller})))
    (watt-cost (* amount (get price listing-data)))
    (service-fee (calculate-service-fee watt-cost))
    (total-cost (+ watt-cost service-fee))
    (seller-watts (default-to u0 (map-get? user-watt-balance seller)))
    (buyer-balance (default-to u0 (map-get? user-stx-balance tx-sender)))
    (seller-balance (default-to u0 (map-get? user-stx-balance seller)))
    (owner-balance (default-to u0 (map-get? user-stx-balance contract-owner)))
  )
    (asserts! (not (is-eq tx-sender seller)) err-same-user)
    (asserts! (> amount u0) err-invalid-amount) ;; Ensure amount is greater than 0
    (asserts! (>= (get amount listing-data) amount) err-not-enough-balance)
    (asserts! (>= seller-watts amount) err-not-enough-balance)
    (asserts! (>= buyer-balance total-cost) err-not-enough-balance)
    
    ;; Update seller's watt balance and listing amount
    (map-set user-watt-balance seller (- seller-watts amount))
    (map-set watt-listing {user: seller} 
             {amount: (- (get amount listing-data) amount), price: (get price listing-data)})
    
    ;; Update buyer's STX and watt balance
    (map-set user-stx-balance tx-sender (- buyer-balance total-cost))
    (map-set user-watt-balance tx-sender (+ (default-to u0 (map-get? user-watt-balance tx-sender)) amount))
    
    ;; Update seller's and contract owner's STX balance
    (map-set user-stx-balance seller (+ seller-balance watt-cost))
    (map-set user-stx-balance contract-owner (+ owner-balance service-fee))
    
    (ok true)))

;; Sell watts back to the system
(define-public (sell-watts-back (amount uint))
  (let (
    (user-watts (default-to u0 (map-get? user-watt-balance tx-sender)))
    (buyback-amount (calculate-buyback amount))
    (contract-stx-balance (default-to u0 (map-get? user-stx-balance contract-owner)))
  )
    (asserts! (> amount u0) err-invalid-amount) ;; Ensure amount is greater than 0
    (asserts! (>= user-watts amount) err-not-enough-balance)
    (asserts! (>= contract-stx-balance buyback-amount) err-refund-failed)
    
    ;; Update user's watt balance
    (map-set user-watt-balance tx-sender (- user-watts amount))
    
    ;; Update user's and contract's STX balance
    (map-set user-stx-balance tx-sender (+ (default-to u0 (map-get? user-stx-balance tx-sender)) buyback-amount))
    (map-set user-stx-balance contract-owner (- contract-stx-balance buyback-amount))
    
    ;; Add sold watts back to contract owner's balance
    (map-set user-watt-balance contract-owner (+ (default-to u0 (map-get? user-watt-balance contract-owner)) amount))
    
    ;; Update watt pool
    (try! (update-watt-pool (to-int (- amount))))
    
    (ok true)))

;; Read-only functions

;; Get current watt price
(define-read-only (get-watt-price)
  (ok (var-get watt-price)))

;; Get current service fee rate
(define-read-only (get-service-fee-rate)
  (ok (var-get service-fee-rate)))

;; Get current buyback rate
(define-read-only (get-buyback-rate)
  (ok (var-get buyback-rate)))

;; Get user's watt balance
(define-read-only (get-watt-balance (user principal))
  (ok (default-to u0 (map-get? user-watt-balance user))))

;; Get user's STX balance
(define-read-only (get-stx-balance (user principal))
  (ok (default-to u0 (map-get? user-stx-balance user))))

;; Get watts listed for sale by user
(define-read-only (get-watt-listing (user principal))
  (ok (default-to {amount: u0, price: u0} (map-get? watt-listing {user: user}))))

;; Get maximum watts per user
(define-read-only (get-max-watt-per-user)
  (ok (var-get max-watt-per-user)))

;; Get current watt pool
(define-read-only (get-current-watt-pool)
  (ok (var-get current-watt-pool)))

;; Get watt pool limit
(define-read-only (get-watt-pool-limit)
  (ok (var-get watt-pool-limit)))

;; Set maximum watts per user (only contract owner)
(define-public (set-max-watt-per-user (new-max uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-max u0) err-invalid-amount) ;; Ensure new max is greater than 0
    (var-set max-watt-per-user new-max)
    (ok true)))