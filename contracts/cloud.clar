;; StorageSwarm: Decentralized Encrypted Cloud Storage Contract

(define-constant contract-owner tx-sender)
(define-constant storage-fee u1000) ;; Satoshis per storage unit
(define-constant max-file-size u104857600) ;; 100 MB max file size
(define-constant initial-reputation u100)
(define-constant reward-increment u10)

;; Storage file metadata structure
(define-map storage-files 
  { 
    file-id: (buff 32),  ;; Unique file identifier (SHA-256 hash)
    owner: principal 
  }
  {
    file-size: uint,
    encryption-key: (buff 64),
    stored-timestamp: uint,
    total-replicas: uint
  }
)

;; Mapping to track storage providers and their reputation
(define-map storage-providers 
  principal 
  {
    total-storage: uint,
    successful-storage-ops: uint,
    reputation-score: uint
  }
)

;; Error constants
(define-constant err-unauthorized (err u100))
(define-constant err-file-too-large (err u101))
(define-constant err-insufficient-fee (err u102))
(define-constant err-file-exists (err u103))
(define-constant err-invalid-input (err u104))
(define-constant err-file-not-found (err u105))
(define-constant err-provider-not-registered (err u106))

;; Input validation functions
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

;; Check if a storage provider is registered
(define-private (is-registered-provider (provider principal))
  (is-some (map-get? storage-providers provider))
)

;; Upload a file to the decentralized storage network
(define-public (upload-file 
  (file-id (buff 32)) 
  (file-size uint) 
  (encryption-key (buff 64))
)
  (begin
    ;; Validate inputs
    (asserts! (is-valid-file-id file-id) err-invalid-input)
    (asserts! (is-valid-encryption-key encryption-key) err-invalid-input)
    
    ;; Validate file size
    (asserts! (<= file-size max-file-size) err-file-too-large)
    
    ;; Check if file already exists
    (asserts! 
      (is-none (map-get? storage-files { file-id: file-id, owner: tx-sender })) 
      err-file-exists
    )
    
    ;; Calculate storage fee
    (let ((required-fee (* file-size storage-fee)))
      (asserts! (>= (stx-get-balance tx-sender) required-fee) err-insufficient-fee)
      
      ;; Transfer storage fee
      (try! (stx-transfer? required-fee tx-sender contract-owner))
      
      ;; Store file metadata
      (map-set storage-files 
        { file-id: file-id, owner: tx-sender }
        {
          file-size: file-size,
          encryption-key: encryption-key,
          stored-timestamp: block-height,
          total-replicas: u1
        }
      )
      
      (ok true)
    )
  )
)

;; Retrieve file metadata (accessible only by file owner)
(define-read-only (get-file-metadata (file-id (buff 32)))
  (begin
    (asserts! (is-valid-file-id file-id) none)
    (map-get? storage-files { file-id: file-id, owner: tx-sender })
  )
)

;; Register as a storage provider
(define-public (register-storage-provider)
  (begin
    ;; Check if provider is already registered
    (asserts! 
      (is-none (map-get? storage-providers tx-sender)) 
      err-unauthorized
    )
    
    (map-set storage-providers 
      tx-sender 
      {
        total-storage: u0,
        successful-storage-ops: u0,
        reputation-score: initial-reputation
      }
    )
    (ok true)
  )
)

;; Reward mechanism for storage providers
(define-public (reward-storage-provider 
  (provider principal) 
  (file-id (buff 32))
)
  (begin
    ;; Validate inputs
    (asserts! (is-valid-file-id file-id) err-invalid-input)
    
    ;; Ensure provider is registered
    (asserts! (is-registered-provider provider) err-provider-not-registered)
    
    ;; Check file existence and ownership
    (let ((file-entry 
            (map-get? storage-files { file-id: file-id, owner: tx-sender })))
      ;; Ensure file exists
      (asserts! (is-some file-entry) err-file-not-found)
      
      ;; Ensure the caller is authorized (could be contract owner or file owner)
      (asserts! 
        (or 
          (is-eq tx-sender contract-owner)
          (is-eq tx-sender contract-owner)
        ) 
        err-unauthorized
      )
    )
    
    ;; Get current provider stats with additional safety checks
    (let ((current-provider-stats 
            (unwrap! 
              (map-get? storage-providers provider) 
              err-provider-not-registered
            )))
      (map-set storage-providers 
        provider
        (merge current-provider-stats {
          successful-storage-ops: (+ (get successful-storage-ops current-provider-stats) u1),
          reputation-score: (+ (get reputation-score current-provider-stats) reward-increment)
        })
      )
      (ok true)
    )
  )
)

;; Bonus: Function to check provider reputation
(define-read-only (get-provider-reputation (provider principal))
  (map-get? storage-providers provider)
)

;; Optional: File deletion function
(define-public (delete-file (file-id (buff 32)))
  (begin
    ;; Validate file ID
    (asserts! (is-valid-file-id file-id) err-invalid-input)
    
    ;; Ensure file exists and is owned by sender
    (asserts! 
      (is-some (map-get? storage-files { file-id: file-id, owner: tx-sender })) 
      err-unauthorized
    )
    
    ;; Remove file metadata
    (map-delete storage-files { file-id: file-id, owner: tx-sender })
    
    (ok true)
  )
)