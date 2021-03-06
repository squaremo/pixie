(__ns__ pixie.stdlib)

(def reset! -reset!)

(def load-paths (atom ["./"]))
(def program-arguments [])


(def map (fn ^{:doc "map - creates a transducer that applies f to every input element" :added "0.1"}
             map [f]
             (fn [xf]
                 (fn
                  ([] (xf))
                  ([result] (xf result))
                  ([result item] (xf result (f item)))))))

(def conj (fn conj
           ([] [])
           ([result] result)
           ([result item] (-conj result item))))

(def conj! (fn conj!
             ([] (-transient []))
             ([result] (-persistent! result))
             ([result item] (-conj! result item))))


(def transduce (fn transduce
              ([f coll]
                (let [result (-reduce coll f (f))]
                      (f result)))

              ([xform rf coll]
                (let [f (xform rf)
                      result (-reduce coll f (f))]
                      (f result)))
              ([xform rf init coll]
                (let [f (xform rf)
                      result (-reduce coll f init)]
                      (f result)))))

(def reduce (fn [rf init col]
              (-reduce col rf init)))


(def interpose
     (fn interpose [val]
       (fn [xf]
           (let [first? (atom true)]
                (fn
                 ([] (xf))
                 ([result] (xf result))
                 ([result item] (if @first?
                                    (do (reset! first? false)
                                        (xf result item))
                                  (xf (xf result val) item))))))))


(def preserving-reduced
  (fn [rf]
    (fn [a b]
      (let [ret (rf a b)]
        (if (reduced? ret)
          (reduced ret)
          ret)))))

(def cat
  (fn cat [rf]
    (let [rrf (preserving-reduced rf)]
      (fn cat-inner
        ([] (rf))
        ([result] (rf result))
        ([result input]
           (reduce rrf result input))))))


(def seq-reduce (fn seq-reduce
                  [coll f init]
                  (loop [init init
                         coll (seq coll)]
                    (if (reduced? init)
                      @init
                      (if (seq coll)
                        (recur (f init (first coll))
                               (seq (next coll)))
                        init)))))

(def indexed-reduce (fn indexed-reduce
                      [coll f init]
                      (let [max (count coll)]
                      (loop [init init
                             i 0]
                        (if (reduced? init)
                          @init
                          (if (-eq i max)
                            init
                            (recur (f init (nth coll i)) (+ i 1))))))))


(extend -reduce Cons seq-reduce)
(extend -reduce PersistentList seq-reduce)
(extend -reduce LazySeq seq-reduce)

(comment (extend -reduce Array indexed-reduce))

(extend -str Bool
  (fn [x]
    (if (identical? x true)
      "true"
      "false")))

(extend -str Nil (fn [x] "nil"))
(extend -reduce Nil (fn [self f init] init))
(extend -hash Nil (fn [self] 100000))

(extend -hash Integer hash-int)

(extend -eq Integer -num-eq)
(extend -eq Float -num-eq)
(extend -eq Ratio -num-eq)

(def ordered-hash-reducing-fn
  (fn ordered-hash-reducing-fn
    ([] (new-hash-state))
    ([state] (finish-hash-state state))
    ([state itm] (update-hash-ordered! state itm))))

(def unordered-hash-reducing-fn
  (fn unordered-hash-reducing-fn
    ([] (new-hash-state))
    ([state] (finish-hash-state state))
    ([state itm] (update-hash-unordered! state itm))))


(extend -str PersistentVector
  (fn [v]
    (apply str "[" (conj (transduce (interpose ", ") conj v) "]"))))




(extend -str Cons
  (fn [v]
    (apply str "(" (conj (transduce (interpose ", ") conj v) ")"))))

(extend -hash Cons
        (fn [v]
          (transduce ordered-hash-reducing-fn v)))

(extend -str PersistentList
  (fn [v]
    (apply str "(" (conj (transduce (interpose ", ") conj v) ")"))))

(extend -str LazySeq
  (fn [v]
    (apply str "(" (conj (transduce (interpose ", ") conj v) ")"))))

(extend -hash PersistentVector
  (fn [v]
    (transduce ordered-hash-reducing-fn v)))


(def stacklet->lazy-seq
  (fn [f]
    (let [val (f nil)]
      (if (identical? val :end)
        nil
        (cons val (lazy-seq* (fn [] (stacklet->lazy-seq f))))))))

(def sequence
  (fn
    ([data]
       (let [f (create-stacklet
                 (fn [h]
                   (reduce (fn ([h item] (h item) h)) h data)
                   (h :end)))]
          (stacklet->lazy-seq f)))
    ([xform data]
        (let [f (create-stacklet
                 (fn [h]
                   (transduce xform
                              (fn ([] h)
                                ([h item] (h item) h)
                                ([h] (h :end)))
                              data)))]
          (stacklet->lazy-seq f)))))

(extend -seq PersistentVector sequence)
(extend -seq Array sequence)



(def concat (fn [& args] (transduce cat conj args)))

(def defn (fn [nm & rest] `(def ~nm (fn ~nm ~@rest))))
(set-macro! defn)

(defn defmacro [nm & rest]
  `(do (defn ~nm ~@rest)
       (set-macro! ~nm)
       ~nm))

(set-macro! defmacro)

(defn +
  [& args]
  (reduce -add 0 args))


(defn -
  ([] 0)
  ([x] (-sub 0 x))
  ([x & args]
     (reduce -sub x args)))

(defn =
  ([x] true)
  ([x y] (eq x y))
  ([x y & rest] (if (eq x y)
                  (apply = y rest)
                  false)))

(def inc (fn [x] (+ x 1)))

(def dec (fn [x] (- x 1)))


(defn assoc
  ([m] m)
  ([m k v]
     (-assoc m k v))
  ([m k v & rest]
     (apply assoc (-assoc m k v) rest)))

(def slot-tp (create-type :slot [:val]))

(defn ->Slot [x]
  (let [inst (new slot-tp)]
    (set-field! inst :val x)))

(defn get-val [inst]
  (get-field inst :val))

(defn comp
  ([f] f)
  ([f1 f2]
     (fn [& args]
       (f1 (apply f2 args))))
  ([f1 f2 f3]
     (fn [& args]
       (f1 (f2 (apply f3 args))))))


(defn not [x]
  (if x false true))

(defmacro cond
  ([] nil)
  ([test then & clauses]
      `(if ~test
         ~then
         (cond ~@clauses))))


(defmacro try [& body]
  (loop [catch nil
         catch-sym nil
         body-items []
         finally nil
         body (seq body)]
    (let [form (first body)]
      (if form
        (if (not (seq? form))
          (recur catch catch-sym (conj body-items form) finally (next body))
          (let [head (first form)]
            (cond
             (= head 'catch) (if catch
                               (throw "Can only have one catch clause per try")
                               (recur (next (next form)) (first (next form)) body-items finally (next body)))
             (= head 'finally) (if finally
                                 (throw "Can only have one finally clause per try")
                                 (recur catch catch-sym body-items (next form) (next body)))
             :else (recur catch catch-sym (conj body-items form) finally (next body)))))
        `(-try-catch
          (fn [] ~@body-items)
          ~(if catch
             `(fn [~catch-sym] ~@catch)
             `(fn [] nil))

          (fn [] ~@finally))))))

(defn .
  ([obj sym]
     (get-field obj sym))
  ([obj sym & args]
     (apply (get-field obj sym) args)))


(extend -count MapEntry (fn [self] 2))
(extend -nth MapEntry (fn [self idx not-found]
                          (cond (= idx 0) (-key self)
                                (= idx 1) (-val self)
                                :else not-found)))

(defn key [x]
  (-key x))

(defn val [x]
  (-val x))

(extend -reduce MapEntry indexed-reduce)

(extend -str MapEntry
        (fn [v]
            (apply str "[" (conj (transduce (interpose ", ") conj v) "]"))))

(extend -hash MapEntry
  (fn [v]
    (transduce ordered-hash-reducing-fn v)))

(extend -str PersistentHashMap
        (fn [v]
            (apply str "{" (conj (transduce (comp cat (interpose " ")) conj v) "}"))))

(extend -hash PersistentHashMap
        (fn [v]
          (transduce cat unordered-hash-reducing-fn v)))

(extend -str Keyword
  (fn [k]
    (if (namespace k)
      (str ":" (namespace k) "/" (name k))
      (str ":" (name k)))))

(defn get
  ([mp k]
     (get mp k nil))
  ([mp k not-found]
     (-val-at mp k not-found)))

(defmacro assert
  ([test]
     `(if ~test
        nil
        (throw "Assert failed")))
  ([test msg]
     `(if ~test
        nil
        (throw (str "Assert failed " ~msg)))))

(defmacro resolve [sym]
  `(resolve-in (this-ns-name) ~sym))

(defmacro with-bindings [binds & body]
  `(do (push-binding-frame!)
       (reduce (fn [_ map-entry]
                 (set! (resolve (key map-entry)) (val map-entry)))
               nil
               (apply hashmap ~@binds))
       (let [ret (do ~@body)]
         (pop-binding-frame!)
         ret)))

(def foo 42)
(set-dynamic! (resolve 'pixie.stdlib/foo))

(defmacro require [ns kw as-nm]
  (assert (= kw :as) "Require expects :as as the second argument")
  `(do (load-file (quote ~ns))
       (refer (this-ns-name) (the-ns (quote ~ns)) (quote ~as-nm))))

(defmacro ns [nm & body]
  `(do (__ns__ ~nm)
       ~@body))


(defn symbol? [x]
  (identical? Symbol (type x)))


(defmacro lazy-seq [& body]
  `(lazy-seq* (fn [] ~@body)))

(defmacro deftype [nm fields & body]
  (let [ctor-name (symbol (str "->" (name nm)))
        type-decl `(def ~nm (create-type ~(keyword (name nm)) ~fields))
        field-syms (transduce (map (comp symbol name)) conj fields)
        inst (gensym)
        ctor `(defn ~ctor-name ~field-syms
                (let [~inst (new ~nm)]
                  ~@(transduce
                     (map (fn [field]
                            `(set-field! ~inst ~field ~(symbol (name field)))))
                     conj
                     fields)
                  ~inst))
        proto-bodies (transduce
                      (map (fn [body]
                             (cond
                              (symbol? body) `(satisfy ~body ~nm)
                              (seq? body) `(extend ~(first body) ~nm (fn ~@body))
                              :else (assert false "Unknown body element in deftype, expected symbol or seq"))))
                      conj
                      body)]
    `(do ~type-decl
         ~ctor
         ~@proto-bodies)))


 (def libc (ffi-library pixie.platform/lib-c-name))
 (def exit (ffi-fn libc "exit" [Integer] Integer))
 (def puts (ffi-fn libc "puts" [String] Integer))
 (def printf (ffi-fn libc "printf" [String] Integer))

(defn print [& args]
  (puts (apply str args)))


(defn doc [x]
  (get (meta x) :doc))

(defn swap! [a f & args]
  (reset! a (apply f @a args)))

(def update-inner-f (fn inner-f
                  ([m f k]
                   (assoc m k (f (get m k))))
                  ([m f k & ks]
                    (assoc m k (apply update-inner-f m f ks)))))

(defn update-in
  [m ks f & args]
  (let [f (fn [m] (apply f m args))]
    (apply update-inner-f m f ks)))

(defn nil? [x]
  (identical? x nil))

(defn fnil [f else]
  (fn [x & args]
    (apply f (if (nil? x) else x) args)))

(defmacro foreach [binding & body]
  (assert (= 2 (count binding)) "binding and collection required")
  `(reduce
    (fn [_ ~ (nth binding 0)]
        ~@body
        nil)
    nil
    ~(nth binding 1)))


(defmacro dotimes [bind & body]
  (let [b (nth bind 0)]
    `(let [max# ~(nth bind 1)]
       (loop [~b 0]
         (if (= ~b max#)
           nil
           (do ~@body
               (recur (inc ~b))))))))


(defmacro and
  ([x] x)
  ([x y] `(if ~x ~y nil))
  ([x y & more] `(if ~x (and ~y ~@more))))

(defmacro or
  ([x] x)
  ([x y] `(let [r# ~x]
            (if r# r# ~y)))
  ([x y & more] `(let [r# ~x]
                   (if r# r# (or ~y ~@more)))))
