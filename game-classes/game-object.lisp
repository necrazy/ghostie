(in-package :ghostie)

(defclass game-object ()
  ((name :accessor game-object-name :initarg :name :initform "game-object")
   (position :accessor game-object-position :initarg :position :initform '(0 0 0))
   (rotation :accessor game-object-rotation :initarg :rotation :initform 0.0)
   (gl-objects :accessor game-object-gl-objects :initarg :gl-objects :initform nil)
   (physics-body :accessor game-object-physics-body :initform nil)
   (meta :accessor game-object-meta :initarg :meta :initform nil)
   (display :accessor game-object-display :initarg :display :initform t)
   (render-ref :accessor game-object-render-ref :initarg :render-ref :initform nil)))

(defun make-game-object (&key (type 'game-object) gl-objects physics (position '(0 0 0)) (rotation 0.0))
  (let ((obj (make-instance type :position position :rotation rotation)))
    (setf (game-object-gl-objects obj) gl-objects
          (game-object-physics-body obj) physics)
    obj))

(defun destroy-game-object (game-object)
  "Clear out a game object, and free all its non-lisp data (gl objects and
  physics)."
  (let ((body (game-object-physics-body game-object)))
    (when body
      (cpw:destroy (game-object-physics-body game-object))))
  (dolist (gl-object (game-object-gl-objects game-object))
    (free-gl-object gl-object)))

(defmethod draw ((object game-object))
  (dolist (gl-object (game-object-gl-objects object))
    (unless (getf (gl-object-shape-meta gl-object) :disconnected)
      (draw-gl-object gl-object
                      :color (when (getf (game-object-meta object) :sleeping) (hex-to-rgb "#444444"))
                      :position (game-object-position object)
                      :rotation (list 0 0 1 (game-object-rotation object))))))

(defun sync-game-object-to-physics (game-object)
  "Sync an object's position/rotation with its physics body."
  (let ((body (game-object-physics-body game-object)))
    (when body
      (cpw:sync-body body)
      (let ((position (list (cpw:body-x body)
                            (cpw:body-y body)
                            0))
            (rotation (- (cpw:body-angle body)))
            (sleeping (cpw:body-sleeping-p body)))
        (unless (and (equal position (game-object-position game-object))
                     (equal rotation (game-object-rotation game-object))
                     (eq sleeping (getf (game-object-meta game-object) :sleeping)))
          (setf (game-object-position game-object) position
                (game-object-rotation game-object) rotation
                (getf (game-object-meta game-object) :sleeping) sleeping)
          (let ((render-game-object (game-object-render-ref game-object)))
            (when (and (game-object-display game-object) render-game-object)
              (enqueue (lambda (render-world)
                         (declare (ignore render-world))
                         (setf (game-object-position render-game-object) position
                               (game-object-rotation render-game-object) rotation
                               (getf (game-object-meta render-game-object) :sleeping) sleeping)))))))))
  game-object)

(defun parse-svg-styles (styles &key fill opacity)
  (let ((fill (if (stringp fill) fill "#000000"))
        (opacity (if (stringp opacity) (read-from-string opacity) 1.0)))
    (let ((directives (split-sequence:split-sequence #\; styles)))
      (dolist (directive directives)
        (let* ((parts (split-sequence:split-sequence #\: directive))
               (name (string-downcase (remove-if (lambda (c) (eq c #\space)) (car parts))))
               (value (remove-if (lambda (c) (eq c #\space)) (cadr parts))))
          (when (equal name "opacity")
            (setf opacity value))
          (when (equal name "fill")
            (setf fill value)))))
    (list :fill fill :opacity opacity)))

(defun sync-game-objects-to-render (game-objects)
  (dolist (game-object game-objects)
    (enqueue (lambda (world)
               (let ((level (world-level world))
                     (gl-objects (loop for fake-gl-object in (game-object-gl-objects game-object)
                                       for gl-object = (make-gl-object-from-fake fake-gl-object)
                                       collect gl-object)))
                 (dbg :info "Initializing game object in render.~%")
                 (let ((render-game-object (make-instance 'game-object
                                                          :gl-objects gl-objects
                                                          :name (game-object-name game-object)
                                                          :position (game-object-position game-object)
                                                          :rotation (game-object-rotation game-object))))
                   (push render-game-object (level-objects level))
                   (setf (game-object-render-ref game-object) render-game-object))))
    :render)))

(defun svg-to-game-objects (svg-objects objects-meta &key (object-type 'game-object) (scale '(1 1 1)) center-objects)
  (let ((obj-hash (make-hash-table :test #'equal))
        (game-objects nil)
        (scale (if scale scale '(1 1 1))))
    (loop for i from 0
          for obj in svg-objects do
      (when (< 0 (length (getf obj :point-data)))
        (let* ((styles (parse-svg-styles (getf obj :style)
                                         :fill (getf obj :fill)
                                         :opacity (getf obj :opacity)))
               (opacity (getf styles :opacity))
               (color (if (getf styles :fill)
                          (hex-to-rgb (getf styles :fill) :opacity opacity)
                          (vector 0 0 0 opacity)))
               (triangles (glu-tessellate:tessellate (getf obj :point-data) :holes (getf obj :holes)))
               (group-name (car (getf obj :group)))
               (meta (getf obj :meta))
               (disconnected (getf meta :disconnected)))
          (when (or (< 0 (length triangles)) disconnected)
            (push (make-fake-gl-object :data triangles :color color :scale scale :shape-meta meta :shape-points (getf obj :point-data))
                  (gethash group-name obj-hash))))))
    (loop for group-name being the hash-keys of obj-hash
          for gl-objects being the hash-values of obj-hash do
      (let* ((meta (find-if (lambda (p) (equal (getf p :name) group-name)) (getf objects-meta :object-properties)))
             (depth (getf meta :layer-depth)))
        (let ((game-object (make-game-object :type object-type
                                             :gl-objects gl-objects
                                             :position (list 0 0 (if depth depth 0)))))
          (when center-objects
            (center-game-object game-object))
          (push game-object game-objects))))
    (sync-game-objects-to-render game-objects)
    game-objects))

(defun center-game-object (game-object)
  "Center a game object's gl objects based on the min/max sums of all of their
  coords, then take that difference and apply it to the object's position. This
  effectively centers the game object around 0,0 and applies a position to it
  that puts it in its original place."
  (let ((min-x 0)
        (min-y 0)
        (min-z 0)
        (max-x 0)
        (max-y 0)
        (max-z 0))
    (dolist (gl-object (game-object-gl-objects game-object))
      (loop for (x y z)
            on (coerce (gl-object-vertex-data gl-object) 'list)
            by #'cdddr do
        (setf min-x (min x min-x)
              min-y (min y min-y)
              min-z (min z min-z)
              max-x (max x max-x)
              max-y (max y max-y)
              max-z (max z max-z))))
    (let ((diff-x (- (- min-x) (/ (- max-x min-x) 2)))
          (diff-y (- (- min-y) (/ (- max-y min-y) 2)))
          (diff-z (- (- min-z) (/ (- max-z min-z) 2))))
      (dolist (gl-object (game-object-gl-objects game-object))
        (let ((disconnected (getf (gl-object-shape-meta gl-object) :disconnected)))
          (unless disconnected
            (let ((vertex-data (gl-object-vertex-data gl-object)))
              (dotimes (i (/ (length vertex-data) 3))
                (let ((i (* i 3)))
                  (setf (aref vertex-data i) (+ (aref vertex-data i) diff-x)
                        (aref vertex-data (+ i 1)) (+ (aref vertex-data (+ i 1)) diff-y)
                        (aref vertex-data (+ i 2)) (+ (aref vertex-data (+ i 2)) diff-z))))
              (update-gl-object-vertex-data gl-object vertex-data)))))
      (setf (game-object-position game-object) (list (- diff-x)
                                                     (- diff-y)
                                                     (caddr (game-object-position game-object))))))
  game-object)

