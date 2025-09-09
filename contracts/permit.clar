;; Smart Hawker License Permit Contract
;; A comprehensive daily permit management system for street vendors and hawkers
;; Provides transparent, automated permit issuance with location-based allocation

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-location (err u103))
(define-constant err-location-full (err u104))
(define-constant err-insufficient-payment (err u105))
(define-constant err-permit-expired (err u106))
(define-constant err-permit-exists (err u107))
(define-constant err-invalid-date (err u108))

;; Permit status constants
(define-constant status-active u1)
(define-constant status-expired u2)
(define-constant status-revoked u3)

;; Location type constants  
(define-constant location-street u1)
(define-constant location-market u2)
(define-constant location-plaza u3)
(define-constant location-park u4)

;; Data Variables
(define-data-var next-permit-id uint u1)
(define-data-var next-location-id uint u1)
(define-data-var daily-permit-fee uint u1000000) ;; 1 STX in microSTX
(define-data-var total-permits-issued uint u0)
(define-data-var total-revenue uint u0)
(define-data-var system-active bool true)

;; Data Maps

;; Hawker daily permits
(define-map permits
    { permit-id: uint }
    {
        vendor: principal,
        location-id: uint,
        issue-date: uint,
        expiry-date: uint,
        permit-status: uint,
        fee-paid: uint,
        issue-block: uint,
        vendor-name: (string-ascii 50),
        business-type: (string-ascii 30)
    }
)

;; Hawking locations registry
(define-map locations
    { location-id: uint }
    {
        location-name: (string-ascii 100),
        location-type: uint,
        max-capacity: uint,
        current-occupancy: uint,
        daily-fee: uint,
        active: bool,
        coordinates: (string-ascii 50),
        regulations: (string-ascii 200)
    }
)

;; Vendor profiles
(define-map vendors
    { vendor: principal }
    {
        vendor-name: (string-ascii 50),
        business-type: (string-ascii 30),
        total-permits: uint,
        compliance-score: uint,
        registration-date: uint,
        active-permits: uint,
        violations: uint
    }
)

;; Daily location occupancy tracking
(define-map daily-occupancy
    { location-id: uint, date: uint }
    { occupied-slots: uint, permit-ids: (list 50 uint) }
)

;; Municipal authorities
(define-map authorities
    { authority: principal }
    { authorized: bool, department: (string-ascii 50) }
)

;; Revenue tracking by date
(define-map daily-revenue
    { date: uint }
    { amount: uint, permits-count: uint }
)

;; Location statistics
(define-map location-stats
    { location-id: uint }
    {
        total-permits: uint,
        total-revenue: uint,
        avg-occupancy: uint,
        last-updated: uint
    }
)

;; Private Functions

;; Check if caller is contract owner
(define-private (is-owner (caller principal))
    (is-eq caller contract-owner)
)

;; Check if caller is authorized authority
(define-private (is-authority (caller principal))
    (default-to false (get authorized (map-get? authorities { authority: caller })))
)

;; Check if permit is valid for current date
(define-private (is-permit-valid (permit-id uint))
    (match (map-get? permits { permit-id: permit-id })
        permit
        (and
            (is-eq (get permit-status permit) status-active)
            (<= (get issue-date permit) stacks-block-height)
            (> (get expiry-date permit) stacks-block-height)
        )
        false
    )
)

;; Calculate permit expiry date (24 hours from issue)
(define-private (calculate-expiry-date (issue-date uint))
    (+ issue-date u144) ;; Approximately 24 hours in blocks (10 min blocks)
)

;; Update location occupancy
(define-private (update-location-occupancy (location-id uint) (increment bool))
    (match (map-get? locations { location-id: location-id })
        location
        (let
            (
                (current-occupancy (get current-occupancy location))
                (new-occupancy 
                    (if increment
                        (+ current-occupancy u1)
                        (if (> current-occupancy u0)
                            (- current-occupancy u1)
                            u0
                        )
                    )
                )
            )
            (begin
                (map-set locations
                    { location-id: location-id }
                    (merge location { current-occupancy: new-occupancy })
                )
                (ok new-occupancy)
            )
        )
        (err err-invalid-location)
    )
)

;; Update daily revenue tracking
(define-private (update-daily-revenue (date uint) (amount uint))
    (let
        (
            (current-data (default-to { amount: u0, permits-count: u0 }
                (map-get? daily-revenue { date: date })))
        )
        (begin
            (map-set daily-revenue
                { date: date }
                {
                    amount: (+ (get amount current-data) amount),
                    permits-count: (+ (get permits-count current-data) u1)
                }
            )
            (ok true)
        )
    )
)

;; Public Functions

;; Initialize system (owner only)
(define-public (initialize)
    (begin
        (asserts! (is-owner tx-sender) err-owner-only)
        (map-set authorities { authority: contract-owner } { authorized: true, department: "Administration" })
        (ok true)
    )
)

;; Add municipal authority (owner only)
(define-public (add-authority (authority principal) (department (string-ascii 50)))
    (begin
        (asserts! (is-owner tx-sender) err-owner-only)
        (ok (map-set authorities { authority: authority } { authorized: true, department: department }))
    )
)

;; Register hawking location (authority only)
(define-public (register-location
    (location-name (string-ascii 100))
    (location-type uint)
    (max-capacity uint)
    (daily-fee uint)
    (coordinates (string-ascii 50))
    (regulations (string-ascii 200))
)
    (begin
        (asserts! (or (is-owner tx-sender) (is-authority tx-sender)) err-unauthorized)
        
        (let
            (
                (location-id (var-get next-location-id))
            )
            (map-set locations
                { location-id: location-id }
                {
                    location-name: location-name,
                    location-type: location-type,
                    max-capacity: max-capacity,
                    current-occupancy: u0,
                    daily-fee: daily-fee,
                    active: true,
                    coordinates: coordinates,
                    regulations: regulations
                }
            )
            
            ;; Initialize location statistics
            (map-set location-stats
                { location-id: location-id }
                {
                    total-permits: u0,
                    total-revenue: u0,
                    avg-occupancy: u0,
                    last-updated: stacks-block-height
                }
            )
            
            (var-set next-location-id (+ location-id u1))
            (ok location-id)
        )
    )
)

;; Apply for daily hawking permit
(define-public (apply-for-permit
    (location-id uint)
    (vendor-name (string-ascii 50))
    (business-type (string-ascii 30))
)
    (let
        (
            (permit-id (var-get next-permit-id))
            (issue-date stacks-block-height)
            (expiry-date (calculate-expiry-date issue-date))
            (location (unwrap! (map-get? locations { location-id: location-id }) err-invalid-location))
            (permit-fee (get daily-fee location))
        )
        
        ;; Verify system is active
        (asserts! (var-get system-active) err-unauthorized)
        
        ;; Verify location is active
        (asserts! (get active location) err-invalid-location)
        
        ;; Check location capacity
        (asserts! (< (get current-occupancy location) (get max-capacity location)) err-location-full)
        
        ;; Create permit record
        (map-set permits
            { permit-id: permit-id }
            {
                vendor: tx-sender,
                location-id: location-id,
                issue-date: issue-date,
                expiry-date: expiry-date,
                permit-status: status-active,
                fee-paid: permit-fee,
                issue-block: stacks-block-height,
                vendor-name: vendor-name,
                business-type: business-type
            }
        )
        
        ;; Update location occupancy
        (unwrap! (update-location-occupancy location-id true) err-invalid-location)
        
        ;; Update vendor profile
        (let
            (
                (vendor-profile (default-to
                    {
                        vendor-name: vendor-name,
                        business-type: business-type,
                        total-permits: u0,
                        compliance-score: u100,
                        registration-date: stacks-block-height,
                        active-permits: u0,
                        violations: u0
                    }
                    (map-get? vendors { vendor: tx-sender })
                ))
            )
            (map-set vendors
                { vendor: tx-sender }
                (merge vendor-profile {
                    total-permits: (+ (get total-permits vendor-profile) u1),
                    active-permits: (+ (get active-permits vendor-profile) u1)
                })
            )
        )
        
        ;; Update system statistics
        (var-set next-permit-id (+ permit-id u1))
        (var-set total-permits-issued (+ (var-get total-permits-issued) u1))
        (var-set total-revenue (+ (var-get total-revenue) permit-fee))
        
        ;; Update daily revenue
        (unwrap-panic (update-daily-revenue issue-date permit-fee))
        
        ;; Update location statistics
        (let
            (
                (location-stat (default-to
                    {
                        total-permits: u0,
                        total-revenue: u0,
                        avg-occupancy: u0,
                        last-updated: stacks-block-height
                    }
                    (map-get? location-stats { location-id: location-id })
                ))
            )
            (map-set location-stats
                { location-id: location-id }
                (merge location-stat {
                    total-permits: (+ (get total-permits location-stat) u1),
                    total-revenue: (+ (get total-revenue location-stat) permit-fee),
                    last-updated: stacks-block-height
                })
            )
        )
        
        (ok permit-id)
    )
)

;; Revoke permit (authority only)
(define-public (revoke-permit (permit-id uint))
    (let
        (
            (permit (unwrap! (map-get? permits { permit-id: permit-id }) err-not-found))
        )
        (asserts! (or (is-owner tx-sender) (is-authority tx-sender)) err-unauthorized)
        
        ;; Update permit status
        (map-set permits
            { permit-id: permit-id }
            (merge permit { permit-status: status-revoked })
        )
        
        ;; Update location occupancy
        (unwrap! (update-location-occupancy (get location-id permit) false) err-invalid-location)
        
        ;; Update vendor violations if profile exists
        (match (map-get? vendors { vendor: (get vendor permit) })
            vendor-profile
            (map-set vendors
                { vendor: (get vendor permit) }
                (merge vendor-profile {
                    violations: (+ (get violations vendor-profile) u1),
                    active-permits: (if (> (get active-permits vendor-profile) u0)
                        (- (get active-permits vendor-profile) u1)
                        u0
                    )
                })
            )
            false ;; Do nothing if no vendor profile
        )
        
        (ok true)
    )
)

;; Update location status (authority only)
(define-public (update-location-status (location-id uint) (active bool))
    (let
        (
            (location (unwrap! (map-get? locations { location-id: location-id }) err-invalid-location))
        )
        (asserts! (or (is-owner tx-sender) (is-authority tx-sender)) err-unauthorized)
        
        (map-set locations
            { location-id: location-id }
            (merge location { active: active })
        )
        
        (ok true)
    )
)

;; Set daily permit fee (authority only)
(define-public (set-daily-fee (new-fee uint))
    (begin
        (asserts! (or (is-owner tx-sender) (is-authority tx-sender)) err-unauthorized)
        (var-set daily-permit-fee new-fee)
        (ok true)
    )
)

;; Read-only Functions

;; Get permit details
(define-read-only (get-permit (permit-id uint))
    (map-get? permits { permit-id: permit-id })
)

;; Get location details
(define-read-only (get-location (location-id uint))
    (map-get? locations { location-id: location-id })
)

;; Get vendor profile
(define-read-only (get-vendor (vendor principal))
    (map-get? vendors { vendor: vendor })
)

;; Check if permit is currently valid
(define-read-only (check-permit-validity (permit-id uint))
    (is-permit-valid permit-id)
)

;; Get system statistics
(define-read-only (get-system-stats)
    {
        total-permits: (var-get total-permits-issued),
        total-revenue: (var-get total-revenue),
        daily-fee: (var-get daily-permit-fee),
        next-permit-id: (var-get next-permit-id),
        next-location-id: (var-get next-location-id),
        system-active: (var-get system-active)
    }
)

;; Get location statistics
(define-read-only (get-location-stats (location-id uint))
    (map-get? location-stats { location-id: location-id })
)

;; Get daily revenue
(define-read-only (get-daily-revenue (date uint))
    (map-get? daily-revenue { date: date })
)

;; Check authority status
(define-read-only (check-authority (authority principal))
    (is-authority authority)
)

