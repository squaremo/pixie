(ns pixie.test)

(def tests (atom {}))


(def ^:dynamic *stats*)

(def ^:dynamic *current-test*)


(defmacro deftest [nm & body]
  `(do (defn ~nm []
           (print ".")
           (try
             ~@body
             (swap! *stats* update-in [:pass] (fnil inc 0))
             (catch ex
               (swap! *stats* update-in [:fail] (fnil inc 0))
               (swap! *stats* update-in [:errors] (fnil conj []) ex))))
       (swap! tests assoc (symbol (str (namespace (var ~nm)) "/" (name (var ~nm)))) ~nm)))



(defn run-tests []
  (push-binding-frame!)
  (set! (var *stats*) (atom {:fail 0 :pass 0}))

  (reduce
   (fn
     ([_ f]
        ((val f))
        nil)
     ([_] nil))
   nil
   @tests)
  (let [stats @*stats*]
    (print stats)
    (pop-binding-frame!)
    stats))


(defn load-all-tests []
  (print "Looking for tests...")
  (foreach [path @load-paths]
    (print "Looking for tests in: " path)
           (foreach [desc (pixie.path/file-list path)]
                    (if (= (nth desc 1) :file)
                      (let [filename (nth desc 2)]
                        (if (pixie.string/starts-with filename "test-")
                          (if (pixie.string/ends-with filename ".lisp")
                            (let [fullpath (str (nth desc 0) "/" filename)]
                              (print "Loading " fullpath)
                              (load-file fullpath)))))))))


(defn assert= [x y]
  (assert (= x y) (str x " != " y)))
