(in-package :game-level)

(defparameter *world-position* '(0 0 -1))
(defparameter *perspective-matrix* nil)
(defparameter *view-matrix* nil)

(defun create-world ()
  (setf *world-position* '(0 0 -1)))

(defun step-world (world)
  (declare (ignore world)))

(defvar *game-data* nil)

(defun load-assets ()
  (format t "Starting asset load.~%")
  (free-assets)
  (let ((assets '((:ground #P"resources/ground.ai" 0)
                  (:ground-background #P"resources/ground-background.ai" -25)
                  (:tree1 #P"resources/tree1.ai" -100)
                  (:tree2 #P"resources/tree2.ai" -70)
                  (:tree3 #P"resources/tree3.ai" -80)
                  (:tree4 #P"resources/tree4.ai" -160))))
    (loop for (key file z-offset) in assets do
          (format t "Loading ~a...~%" file)
          (setf (getf *game-data* key)
                (multiple-value-bind (vertices offset) (load-points-from-ai file :precision 2 :center t)
                  (make-gl-object :data (cl-triangulation:triangulate (coerce vertices 'vector)) :position (append (mapcar #'- offset) (list z-offset)))))))
  (setf (getf *game-data* :triangle) (make-gl-object :data '(((-1.0 -1.0  0.0) ( 1.0 -1.0  0.0) ( 0.0  1.0  0.0))) :position '(0 0 -1)))
  (setf (getf *game-data* :prism1) (make-gl-object :data '(((-1.0 -1.0  0.0) ( 1.0 -1.0  0.0) ( 0.0  1.0  0.0))
                                                           ((-1.0 -1.0  0.0) ( 0.0  0.0 -1.0) ( 1.0 -1.0  0.0))
                                                           ((-1.0 -1.0  0.0) ( 0.0  1.0  0.0) ( 0.0  0.0 -1.0))
                                                           (( 0.0  1.0  0.0) ( 1.0 -1.0  0.0) ( 0.0  0.0 -1.0))) :position '(3 6 -20)))
  (setf (getf *game-data* :prism2) (make-gl-object :data '(((-1.0 -1.0  0.0) ( 1.0 -1.0  0.0) ( 0.0  1.0  0.0))
                                                           ((-1.0 -1.0  0.0) ( 0.0  0.0 -1.0) ( 1.0 -1.0  0.0))
                                                           ((-1.0 -1.0  0.0) ( 0.0  1.0  0.0) ( 0.0  0.0 -1.0))
                                                           (( 0.0  1.0  0.0) ( 1.0 -1.0  0.0) ( 0.0  0.0 -1.0))) :position '(-3 4 -30)))
  (setf (getf *game-data* :prism3) (make-gl-object :data '(((-1.0 -1.0  0.0) ( 1.0 -1.0  0.0) ( 0.0  1.0  0.0))
                                                           ((-1.0 -1.0  0.0) ( 0.0  0.0 -1.0) ( 1.0 -1.0  0.0))
                                                           ((-1.0 -1.0  0.0) ( 0.0  1.0  0.0) ( 0.0  0.0 -1.0))
                                                           (( 0.0  1.0  0.0) ( 1.0 -1.0  0.0) ( 0.0  0.0 -1.0))) :position '(-1 -4 -25)))
  (format t "Finished asset load.~%"))

(defun free-assets ()
  (loop for (nil obj) on *game-data* by #'cddr do
    (when (subtypep (type-of obj) 'gl-object)
      (free-gl-object obj))))

(defun draw-world (world)
  (declare (ignore world))
  (gl:clear :color-buffer-bit :depth-buffer)
  (gl:use-program *shader-program*)
  (setf *view-matrix* (apply #'m-translate *world-position*))
  (gl:uniform-matrix *camera-to-clip-matrix-unif* 4 (vector *perspective-matrix*))
  (draw (getf *game-data* :prism1))
  (draw (getf *game-data* :prism2))
  (draw (getf *game-data* :prism3))
  ;(draw (getf *game-data* :ground))
  ;(draw (getf *game-data* :tree4))
  (gl:use-program 0))

(defun test-gl-funcs ()
  (format t "Running test func..~%")
  (format t "OpenGL version: ~a~%" (gl:get-string :version))
  (format t "Shader version: ~a~%" (gl:get-string :shading-language-version)))
