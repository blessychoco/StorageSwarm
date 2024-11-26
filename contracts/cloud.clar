;; StorageSwarm: Enhanced Decentralized Encrypted Cloud Storage Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant MIN-STORAGE-FEE u500) ;; Minimum storage fee
(define-constant MAX-STORAGE-FEE u5000) ;; Maximum storage fee
(define-constant storage-fee-per-mb u10) ;; Fee calculation per MB
(define-constant max-file-size u1048576) ;; 1 GB max file size
(define-constant initial-reputation u100)
(define-constant max-reputation u1000)
(define-constant reward-increment u10)
(define-constant penalty-decrement u5)
(define-constant min-replicas u3)
(define-constant max-replicas u10)

;; Error Constants (More Descriptive)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-FILE-TOO-LARGE (err u101))
(define-constant ERR-INSUFFICIENT-FEE (err u102))
(define-constant ERR-FILE-EXISTS (err u103))
(define-constant ERR-INVALID-INPUT (err u104))
(define-constant ERR-FILE-NOT-FOUND (err u105))
(define-constant ERR-PROVIDER-NOT-REGISTERED (err u106))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u107))
(define-constant ERR-REPLICA-LIMIT-REACHED (err u108))

;; Storage file metadata structure (Enhanced)
(define-map storage-files 
  { 
    file-id: (buff 32),
    owner: principal 
  }
  {
    file-size: uint,
    encryption-key: (buff 64),
    stored-timestamp: uint,
    total-replicas: uint,
    replica-providers: (list 10 principal)
  }
)

;; Enhanced storage providers tracking
(define-map storage-providers 
  principal 
  {
    total-storage: uint,
    successful-storage-ops: uint,
    failed-storage-ops: uint,
    reputation-score: uint,
    last-active-block: uint
  }
)

;; Helper function to cap reputation score
(define-private (cap-reputation-score (current-score uint))
  (if (> current-score max-reputation)
    max-reputation
    current-score)
)

;; Helper function to floor reputation score
(define-private (floor-reputation-score (current-score uint))
  (if (< current-score u0)
    u0
    current-score)
)

;; Input validation functions with more comprehensive checks
(define-private (is-valid-file-id (file-id (buff 32)))
  (and 
    (> (len file-id) u0)  ;; Non-empty
    (<= (len file-id) u32)  ;; Max length check
  )
)

(define-private (is-valid-encryption-key (key (buff 64)))
  (and 
    (> (len key) u0)  ;; Non-empty
    (<= (len key) u64)  ;; Max length check
  )
)

;; Enhanced provider registration with stake requirement
(define-public (register-storage-provider (initial-stake uint))
  (begin
    ;; Require minimum stake to register
    (asserts! (>= initial-stake u1000) ERR-INSUFFICIENT-REPUTATION)
    
    ;; Check if provider is already registered
    (asserts! 
      (is-none (map-get? storage-providers tx-sender)) 
      ERR-UNAUTHORIZED
    )
    
    ;; Transfer initial stake to contract
    (try! (stx-transfer? initial-stake tx-sender (as-contract tx-sender)))
    
    (map-set storage-providers 
      tx-sender 
      {
        total-storage: u0,
        successful-storage-ops: u0,
        failed-storage-ops: u0,
        reputation-score: initial-reputation,
        last-active-block: block-height
      }
    )
    (ok true)
  )
)

;; Enhanced reward and penalty mechanism
(define-public (update-provider-reputation 
  (provider principal) 
  (file-id (buff 32))
  (was-successful bool)
)
  (begin
    ;; Validate inputs
    (asserts! (is-valid-file-id file-id) ERR-INVALID-INPUT)
    
    ;; Ensure provider is registered
    (let ((current-provider-stats 
            (unwrap! 
              (map-get? storage-providers provider) 
              ERR-PROVIDER-NOT-REGISTERED
            )))
      
      ;; Update provider stats based on performance
      (map-set storage-providers 
        provider
        (if was-successful
          ;; Successful operation
          (merge current-provider-stats {
            successful-storage-ops: (+ (get successful-storage-ops current-provider-stats) u1),
            reputation-score: (cap-reputation-score 
              (+ (get reputation-score current-provider-stats) reward-increment)
            ),
            last-active-block: block-height
          })
          ;; Failed operation
          (merge current-provider-stats {
            failed-storage-ops: (+ (get failed-storage-ops current-provider-stats) u1),
            reputation-score: (floor-reputation-score 
              (- (get reputation-score current-provider-stats) penalty-decrement)
            ),
            last-active-block: block-height
          })
        )
      )
      
      (ok true)
    )
  )
)


;; Enhanced file retrieval with provider verification
(define-read-only (get-file-metadata (file-id (buff 32)))
  (begin
    (asserts! (is-valid-file-id file-id) none)
    (map-get? storage-files { file-id: file-id, owner: tx-sender })
  )
)

;; Provider stake withdrawal with reputation-based restrictions
(define-public (withdraw-provider-stake (amount uint))
  (let ((provider tx-sender)
        (provider-stats (unwrap! 
          (map-get? storage-providers provider) 
          ERR-PROVIDER-NOT-REGISTERED
        )))
    ;; Ensure provider has sufficient reputation to withdraw
    (asserts! 
      (>= (get reputation-score provider-stats) u500) 
      ERR-INSUFFICIENT-REPUTATION
    )
    
    ;; Transfer stake back to provider
    (as-contract (stx-transfer? amount (as-contract tx-sender) provider))
  )
)

;; Bonus: Comprehensive provider reputation check
(define-read-only (get-provider-full-stats (provider principal))
  (map-get? storage-providers provider)
)