#lang racket/base

(require "helpers.rkt"
         "blame.rkt"
         "prop.rkt"
         "rand.rkt"
         "generate-base.rkt"
         racket/pretty
         racket/list
         (for-syntax racket/base
                     "helpers.rkt"))

(provide coerce-contract
         coerce-contracts
         coerce-flat-contract
         coerce-flat-contracts
         coerce-chaperone-contract
         coerce-chaperone-contracts
         coerce-contract/f
         
         build-compound-type-name
         
         contract-stronger?
         list-contract?
         
         contract-first-order
         contract-first-order-passes?
         
         prop:contracted prop:blame
         impersonator-prop:contracted impersonator-prop:blame
         has-contract? value-contract
         has-blame? value-blame
         
         ;; for opters
         check-flat-contract
         check-flat-named-contract
         
         ;; helpers for adding properties that check syntax uses
         define/final-prop
         define/subexpression-pos-prop
         
         make-predicate-contract
         
         eq-contract?
         eq-contract-val
         equal-contract?
         equal-contract-val
         char-in/c

         contract-continuation-mark-key
         
         (struct-out wrapped-extra-arg-arrow)
         contract-custom-write-property-proc
         (rename-out [contract-custom-write-property-proc custom-write-property-proc])
         
         set-some-basic-contracts!)

(define (contract-custom-write-property-proc stct port display?)
  (write-string "#<" port)
  (cond
    [(flat-contract-struct? stct) (write-string "flat-" port)]
    [(chaperone-contract-struct? stct) (write-string "chaperone-" port)])
  (write-string "contract: " port)
  (write-string (format "~.s" (contract-struct-name stct)) port)
  (write-string ">" port))

(define (has-contract? v)
  (or (has-prop:contracted? v)
      (has-impersonator-prop:contracted? v)))

(define (value-contract v)
  (cond
    [(has-prop:contracted? v)
     (get-prop:contracted v)]
    [(has-impersonator-prop:contracted? v)
     (get-impersonator-prop:contracted v)]
    [else #f]))

(define (has-blame? v)
  (or (has-prop:blame? v)
      (has-impersonator-prop:blame? v)))

(define (value-blame v)
  (cond
    [(has-prop:blame? v)
     (get-prop:blame v)]
    [(has-impersonator-prop:blame? v)
     (get-impersonator-prop:blame v)]
    [else #f]))

(define-values (prop:contracted has-prop:contracted? get-prop:contracted)
  (let-values ([(prop pred get)
                (make-struct-type-property
                 'prop:contracted
                 (lambda (v si)
                   (if (number? v)
                       (let ([ref (cadddr si)])
                         (lambda (s) (ref s v)))
                       (lambda (s) v))))])
    (values prop pred (λ (v) ((get v) v)))))

(define-values (prop:blame has-prop:blame? get-prop:blame)
  (let-values ([(prop pred get)
                (make-struct-type-property
                 'prop:blame
                 (lambda (v si)
                   (if (number? v)
                       (let ([ref (cadddr si)])
                         (lambda (s) (ref s v)))
                       (lambda (s) v))))])
    (values prop pred (λ (v) ((get v) v)))))

(define-values (impersonator-prop:contracted 
                has-impersonator-prop:contracted? 
                get-impersonator-prop:contracted)
  (make-impersonator-property 'impersonator-prop:contracted))

(define-values (impersonator-prop:blame
                has-impersonator-prop:blame? 
                get-impersonator-prop:blame)
  (make-impersonator-property 'impersonator-prop:blame))

(define (contract-first-order c)
  (contract-struct-first-order
   (coerce-contract 'contract-first-order c)))

(define (contract-first-order-passes? c v)
  ((contract-struct-first-order
    (coerce-contract 'contract-first-order-passes? c))
   v))

(define (list-contract? raw-c)
  (define c (coerce-contract/f raw-c))
  (and c (contract-struct-list-contract? c)))

;; contract-stronger? : contract contract -> boolean
;; indicates if one contract is stronger (ie, likes fewer values) than another
;; this is not a total order.
(define (contract-stronger? a b)
  (contract-struct-stronger? (coerce-contract 'contract-stronger? a)
                             (coerce-contract 'contract-stronger? b)))

;; coerce-flat-contract : symbol any/c -> contract
(define (coerce-flat-contract name x)
  (define ctc (coerce-contract/f x))
  (unless (flat-contract-struct? ctc)
    (raise-argument-error name "flat-contract?" x))
  ctc)

;; coerce-flat-contacts : symbol (listof any/c) -> (listof flat-contract)
;; like coerce-contracts, but insists on flat-contracts
(define (coerce-flat-contracts name xs) 
  (for/list ([x (in-list xs)]
             [i (in-naturals)])
    (define ctc (coerce-contract/f x))
    (unless (flat-contract-struct? ctc)
      (raise-argument-error name
                            "flat-contract?"
                            i 
                            xs))
    ctc))

;; coerce-chaperone-contract : symbol any/c -> contract
(define (coerce-chaperone-contract name x)
  (define ctc (coerce-contract/f x))
  (unless (chaperone-contract-struct? ctc)
    (raise-argument-error
     name
     "chaperone-contract?"
     x))
  ctc)

;; coerce-chaperone-contacts : symbol (listof any/c) -> (listof flat-contract)
;; like coerce-contracts, but insists on chaperone-contracts
(define (coerce-chaperone-contracts name xs)
  (for/list ([x (in-list xs)]
             [i (in-naturals)])
    (define ctc (coerce-contract/f x))
    (unless (chaperone-contract-struct? ctc)
      (apply raise-argument-error
             name
             "chaperone-contract?"
             i
             xs))
    ctc))

;; coerce-contract : symbol any/c -> contract
(define (coerce-contract name x)
  (or (coerce-contract/f x)
      (raise-argument-error name
                            "contract?"
                            x)))

;; coerce-contracts : symbol (listof any) -> (listof contract)
;; turns all of the arguments in 'xs' into contracts
;; the error messages assume that the function named by 'name'
;; got 'xs' as it argument directly
(define (coerce-contracts name xs)
  (for/list ([x (in-list xs)]
             [i (in-naturals)])
    (define ctc (coerce-contract/f x))
    (unless ctc
      (apply raise-argument-error
             name
             "contract?"
             i
             xs))
    ctc))

;; coerce-contract/f : any -> (or/c #f contract?)
;; returns #f if the argument could not be coerced to a contract
(define-values (name-default name-default?)
  (let ()
    (struct name-default ())
    (values (name-default) name-default?)))

;; these two definitions work around a cyclic
;; dependency. When we coerce a value to a contract,
;; we want to use (listof any/c) for list?, but
;; the files are not set up for that, so we just
;; bang it in here and use it only after it's been banged in.
(define listof-any #f)
(define consc-anyany #f)
(define list/c-empty #f)
(define (set-some-basic-contracts! l p mt)
  (set! listof-any l)
  (set! consc-anyany p)
  (set! list/c-empty mt))

(define (coerce-contract/f x [name name-default])
  (define (coerce-simple-value x)
    (cond
      [(contract-struct? x) #f] ;; this has to come first, since some of these are procedure?.
      [(and (procedure? x) (procedure-arity-includes? x 1))
       (cond
         [(eq? x null?) list/c-empty]
         [(and (eq? x list?) listof-any) listof-any]
         [(and (eq? x pair?) consc-anyany) consc-anyany]
         [else
          (make-predicate-contract (if (name-default? name)
                                       (or (object-name x) '???)
                                       name)
                                   x
                                   #f
                                   (memq x the-known-good-contracts))])]
      [(null? x) list/c-empty]
      [(or (symbol? x) (boolean? x) (keyword? x))
       (make-eq-contract x
                         (if (name-default? name)
                             (if (or (null? x)
                                     (symbol? x))
                                 `',x
                                 x)
                             name))]
      [(char? x) (make-char-in/c x x)]
      [(or (bytes? x) (string? x) (equal? +nan.0 x) (equal? +nan.f x))
       (make-equal-contract x (if (name-default? name) x name))]
      [(number? x)
       (make-=-contract x (if (name-default? name) x name))]
      [(or (regexp? x) (byte-regexp? x)) (make-regexp/c x (if (name-default? name) x name))]
      [else #f]))
  (cond
    [(coerce-simple-value x) => values]
    [(name-default? name) (and (contract-struct? x) x)]
    [(predicate-contract? x)
     (struct-copy predicate-contract x [name name])]
    [(eq-contract? x) (make-eq-contract (eq-contract-val x) name)]
    [(equal-contract? x) (make-eq-contract (equal-contract-val x) name)]
    [(=-contract? x) (make-=-contract (=-contract-val x) name)]
    [(regexp/c? x) (make-regexp/c (regexp/c-reg x) name)]
    [else #f]))

(define the-known-good-contracts
  (let-syntax ([m (λ (x) #`(list #,@(known-good-contracts)))])
    (m)))

(struct wrapped-extra-arg-arrow (real-func extra-neg-party-argument)
  #:property prop:procedure 0)

(define-syntax (define/final-prop stx)
  (syntax-case stx ()
    [(_ header bodies ...)
     (with-syntax ([ctc 
                    (syntax-case #'header ()
                      [id
                       (identifier? #'id)
                       #'id]
                      [(id1 . rest)
                       (identifier? #'id1)
                       #'id1]
                      [_ 
                       (raise-syntax-error #f 
                                           "malformed header position"
                                           stx 
                                           #'header)])])
       (with-syntax ([ctc/proc (string->symbol (format "~a/proc" (syntax-e #'ctc)))])
         #'(begin
             (define ctc/proc
               (let ()
                 (define header bodies ...)
                 ctc))
             (define-syntax (ctc stx)
               (syntax-case stx ()
                 [x
                  (identifier? #'x)
                  (syntax-property 
                   #'ctc/proc
                   'racket/contract:contract 
                   (vector (gensym 'ctc) 
                           (list stx)
                           '()))]
                 [(_ margs (... ...))
                  (with-syntax ([app (datum->syntax stx '#%app)])
                    (syntax-property 
                     #'(app ctc/proc margs (... ...))
                     'racket/contract:contract 
                     (vector (gensym 'ctc) 
                             (list (car (syntax-e stx)))
                             '())))])))))]))

(define-syntax (define/subexpression-pos-prop stx)
  (syntax-case stx ()
    [(_ header bodies ...)
     (with-syntax ([ctc (if (identifier? #'header)
                            #'header
                            (car (syntax-e #'header)))])
       (with-syntax ([ctc/proc (string->symbol (format "~a/proc" (syntax-e #'ctc)))])
         #'(begin
             (define ctc/proc
               (let ()
                 (define header bodies ...)
                 ctc))
             (define-syntax (ctc stx)
               (syntax-case stx ()
                 [x
                  (identifier? #'x)
                  (syntax-property 
                   #'ctc/proc
                   'racket/contract:contract 
                   (vector (gensym 'ctc) 
                           (list stx)
                           '()))]
                 [(_ margs (... ...))
                  (let ([this-one (gensym 'ctc)])
                    (with-syntax ([(margs (... ...)) 
                                   (map (λ (x) (syntax-property x
                                                                'racket/contract:positive-position
                                                                this-one))
                                        (syntax->list #'(margs (... ...))))]
                                  [app (datum->syntax stx '#%app)])
                      (syntax-property 
                       #'(app ctc/proc margs (... ...))
                       'racket/contract:contract 
                       (vector this-one 
                               (list (car (syntax-e stx)))
                               '()))))])))))]))

;; build-compound-type-name : (union contract symbol) ... -> (-> sexp)
(define (build-compound-type-name . fs)
  (for/list ([sub (in-list fs)])
    (if (contract-struct? sub) (contract-struct-name sub) sub)))


;
;
;            ;                      ;;;
;          ;;;
;   ;;;;; ;;;;;   ;;;   ;;; ;; ;;;  ;;;   ;;;
;  ;;;;;;;;;;;;  ;;;;;  ;;;;;;;;;;; ;;;  ;;;;;
;  ;;  ;;; ;;;  ;;; ;;; ;;; ;;; ;;; ;;; ;;;  ;;
;    ;;;;; ;;;  ;;; ;;; ;;; ;;; ;;; ;;; ;;;
;  ;;; ;;; ;;;  ;;; ;;; ;;; ;;; ;;; ;;; ;;;  ;;
;  ;;; ;;; ;;;;  ;;;;;  ;;; ;;; ;;; ;;;  ;;;;;
;   ;;;;;;  ;;;   ;;;   ;;; ;;; ;;; ;;;   ;;;
;
;
;
;
;
;                            ;                         ;
;                          ;;;                       ;;;
;    ;;;     ;;;   ;;; ;;  ;;;; ;;; ;;;;;;;    ;;;   ;;;;  ;;;;
;   ;;;;;   ;;;;;  ;;;;;;; ;;;; ;;;;;;;;;;;;  ;;;;;  ;;;; ;;; ;;
;  ;;;  ;; ;;; ;;; ;;; ;;; ;;;  ;;;  ;;  ;;; ;;;  ;; ;;;  ;;;
;  ;;;     ;;; ;;; ;;; ;;; ;;;  ;;;    ;;;;; ;;;     ;;;   ;;;;
;  ;;;  ;; ;;; ;;; ;;; ;;; ;;;  ;;;  ;;; ;;; ;;;  ;; ;;;     ;;;
;   ;;;;;   ;;;;;  ;;; ;;; ;;;; ;;;  ;;; ;;;  ;;;;;  ;;;; ;; ;;;
;    ;;;     ;;;   ;;; ;;;  ;;; ;;;   ;;;;;;   ;;;    ;;;  ;;;;
;
;
;
;

(define-struct eq-contract (val name)
  #:property prop:custom-write contract-custom-write-property-proc
  #:property prop:flat-contract
  (build-flat-contract-property
   #:first-order (λ (ctc) (λ (x) (eq? (eq-contract-val ctc) x)))
   #:name (λ (ctc) (eq-contract-name ctc))
   #:generate
   (λ (ctc) 
     (define v (eq-contract-val ctc))
     (λ (fuel) (λ () v)))
   #:stronger
   (λ (this that)
     (define this-val (eq-contract-val this))
     (or (and (eq-contract? that)
              (eq? this-val (eq-contract-val that)))
         (and (predicate-contract? that)
              (predicate-contract-sane? that)
              ((predicate-contract-pred that) this-val))))
   #:list-contract? (λ (c) (null? (eq-contract-val c)))))

(define-struct equal-contract (val name)
  #:property prop:custom-write contract-custom-write-property-proc
  #:property prop:flat-contract
  (build-flat-contract-property
   #:first-order (λ (ctc) (λ (x) (equal? (equal-contract-val ctc) x)))
   #:name (λ (ctc) (equal-contract-name ctc))
   #:stronger
   (λ (this that)
     (define this-val (equal-contract-val this))
     (or (and (equal-contract? that)
              (equal? this-val (equal-contract-val that)))
         (and (predicate-contract? that)
              (predicate-contract-sane? that)
              ((predicate-contract-pred that) this-val))))
   #:generate
   (λ (ctc) 
     (define v (equal-contract-val ctc))
     (λ (fuel) (λ () v)))))

(define-struct =-contract (val name)
  #:property prop:custom-write contract-custom-write-property-proc
  #:property prop:flat-contract
  (build-flat-contract-property
   #:first-order (λ (ctc) (λ (x) (and (number? x) (= (=-contract-val ctc) x))))
   #:name (λ (ctc) (=-contract-name ctc))
   #:stronger
   (λ (this that)
     (define this-val (=-contract-val this))
     (or (and (=-contract? that)
              (= this-val (=-contract-val that)))
         (and (predicate-contract? that)
              (predicate-contract-sane? that)
              ((predicate-contract-pred that) this-val))))
   #:generate
   (λ (ctc) 
     (define v (=-contract-val ctc))
     (λ (fuel)
       (cond
         [(zero? v)
          ;; zero has a whole bunch of different numbers that
          ;; it could be, so just pick one of them at random
          (λ ()
            (oneof '(0
                     -0.0 0.0 0.0f0 -0.0f0
                     0.0+0.0i 0.0f0+0.0f0i 0+0.0i 0.0+0i)))]
         [else
          (λ ()
            (case (random 10)
              [(0)
               (define inf/nan '(+inf.0 -inf.0 +inf.f -inf.f +nan.0 +nan.f))
               ;; try the inexact/exact variant (if there is one)
               (cond
                 [(exact? v)
                  (define iv (exact->inexact v))
                  (if (= iv v) iv v)]
                 [(and (inexact? v) (not (memv v inf/nan)))
                  (define ev (inexact->exact v))
                  (if (= ev v) ev v)]
                 [else v])]
              [(1)
               ;; try to add an inexact imaginary part
               (define c (+ v 0+0.0i))
               (if (= c v) c v)]
              [else
               ;; otherwise, just stick with the original number (80% of the time)
               v]))])))))

(define-struct char-in/c (low high)
  #:property prop:custom-write contract-custom-write-property-proc
  #:property prop:flat-contract
  (build-flat-contract-property
   #:first-order
   (λ (ctc)
     (define low (char-in/c-low ctc))
     (define high (char-in/c-high ctc))
     (λ (x)
         (and (char? x)
              (char<=? low x high))))
   #:name (λ (ctc)
            (define low (char-in/c-low ctc))
            (define high (char-in/c-high ctc))
            (if (equal? low high)
                low
                `(char-in ,low ,high)))
   #:stronger
   (λ (this that)
     (cond
       [(char-in/c? that)
        (define this-low (char-in/c-low this))
        (define this-high (char-in/c-high this))
        (define that-low (char-in/c-low that))
        (define that-high (char-in/c-high that))
        (and (char<=? that-low this-low)
             (char<=? this-high that-high))]
       [else #f]))
   #:generate
   (λ (ctc)
     (define low (char->integer (char-in/c-low ctc)))
     (define high (char->integer (char-in/c-high ctc)))
     (define delta (+ (- high low) 1))
     (λ (fuel)
       (λ ()
         (integer->char (+ low (random delta))))))))

(define-struct regexp/c (reg name)
  #:property prop:custom-write contract-custom-write-property-proc
  #:property prop:flat-contract
  (build-flat-contract-property
   #:first-order
   (λ (ctc)
     (define reg (regexp/c-reg ctc))
      (λ (x)
         (and (or (string? x) (bytes? x))
              (regexp-match? reg x))))
   #:name (λ (ctc) (regexp/c-reg ctc))
   #:stronger
   (λ (this that)
      (and (regexp/c? that) (equal? (regexp/c-reg this) (regexp/c-reg that))))))


;; sane? : boolean -- indicates if we know that the predicate is well behaved
;; (for now, basically amounts to trusting primitive procedures)
(define-struct predicate-contract (name pred generate sane?)
  #:property prop:custom-write contract-custom-write-property-proc
  #:property prop:flat-contract
  (build-flat-contract-property
   #:stronger
   (λ (this that) 
     (and (predicate-contract? that)
          (procedure-closure-contents-eq? (predicate-contract-pred this)
                                          (predicate-contract-pred that))))
   #:name (λ (ctc) (predicate-contract-name ctc))
   #:first-order (λ (ctc) (predicate-contract-pred ctc))
   #:late-neg-projection
   (λ (ctc)
     (define p? (predicate-contract-pred ctc))
     (define name (predicate-contract-name ctc))
     (λ (blame)
       (λ (v neg-party)
         (if (p? v)
             v
             (raise-blame-error blame v #:missing-party neg-party
                                '(expected: "~s" given: "~e")
                                name 
                                v)))))
   #:generate (λ (ctc)
                 (let ([generate (predicate-contract-generate ctc)])
                   (cond
                     [generate generate]
                     [else
                      (define built-in-generator
                        (find-generate (predicate-contract-pred ctc)
                                       (predicate-contract-name ctc)))
                      (λ (fuel)
                        (and built-in-generator
                             (λ () (built-in-generator fuel))))])))
   #:list-contract? (λ (ctc) (or (equal? (predicate-contract-pred ctc) null?)
                                 (equal? (predicate-contract-pred ctc) empty?)))))

(define (check-flat-named-contract predicate) (coerce-flat-contract 'flat-named-contract predicate))
(define (check-flat-contract predicate) (coerce-flat-contract 'flat-contract predicate))
(define (build-flat-contract name pred [generate #f])
  (make-predicate-contract name pred generate #f))


;; Key used by the continuation mark that holds blame information for the current contract.
;; That information is consumed by the contract profiler.
(define contract-continuation-mark-key
  (make-continuation-mark-key 'contract))
