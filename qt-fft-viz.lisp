;;;; qt-fft-viz.lisp
;;;;
;;;; Copyright (c) 2016 Jeremiah LaRocco <jeremiah.larocco@gmail.com>

(in-package #:qt-fft-viz)
(named-readtables:in-readtable :qtools)

(declaim (otpimize (speed 3) (safety 1) (size 0) (debug 0)))

(defparameter *fps* 90)

(define-widget main-window (QMainWindow)
  ((mixer :initform (mixalot:create-mixer))
   (current-stream :initform nil)))

(define-override (main-window close-event) (ev)
  (mixalot:mixer-remove-all-streamers mixer)
  (mixalot:destroy-mixer mixer)
  (q+:accept ev))


(define-menu (main-window File)
  (:item ("Open" (ctrl o))
         (open-file main-window))
  (:separator)
  (:item ("Quit" (ctrl alt q))
         (q+:close main-window)))

(define-menu (main-window Help)
  (:item "About"
         (q+:qmessagebox-information
          main-window "About"
          "Interactively view and manipulate FFT data.")))


(define-widget fft-drawer (QWidget)
               ((the-mp3 :initform nil)
                (current-location :initform 0)
                (song-duration :initform 0)
                (total-frames :initform 0))
  (:documentation "Draw "))


(define-subwidget (fft-drawer timer) (q+:make-qtimer fft-drawer)
  (setf (q+:single-shot timer) nil))

(define-initializer (fft-drawer setup)
  (q+:start timer (round (/ 1000 *fps*))))

(define-slot (fft-drawer tick) ()
  (declare (connected timer (timeout)))
  (if the-mp3
      (incf current-location))
  (q+:update fft-drawer))

(define-override (fft-drawer paint-event paint) (ev)
  "Handle paint events."
  ;; (declare (ignore ev))
  (with-finalizing 
      ;; Create a painter object to draw on
      ((painter (q+:make-qpainter fft-drawer))
       (pen (q+:make-qpen )))

    ;; Clear the background
    (q+:fill-rect painter (q+:rect fft-drawer) (q+:qt.black))
    (q+:set-color pen (q+:make-qcolor 0 205 0))
    (q+:set-pen painter pen)

    (when (and the-mp3 (< current-location total-frames))

      (let* ((height (q+:height fft-drawer))
             (width (q+:width fft-drawer))

             (x-aspect-ratio (if (< height width)
                                 (/ height width 1.0)
                                 1.0))
             (y-aspect-ratio (if (< height width)
                                 1.0
                                 (/ width height 1.0)))
             
             (fft-window-size (* 4096 4))
             (win-center (ceiling (max 0 (- (* 44100 (interpolate 0.0 song-duration current-location total-frames))
                                            (round (/ fft-window-size 2))))))

             (left-fft-data (bordeaux-fft:windowed-fft (mp3-file-left-channel the-mp3) win-center fft-window-size))
             (right-fft-data (bordeaux-fft:windowed-fft (mp3-file-right-channel the-mp3) win-center fft-window-size)))
        
        ;; Local functions for mapping logical coordinates to physical coordinates
        (flet (
               ;; xmapper maps logical x coordinates in the range x-min to x-max to
               ;; screen coordinates in the range 0 to width
               (xmapper (x) (map-val (* x-aspect-ratio x) -300.0 300.0 0 width))

               ;; ymapper does the same thing, but for y coordinates
               (ymapper (y) (map-val (* y-aspect-ratio y) 0.0 200.0 0 height)))

          ;; Actual drawing goes here.  In this case, just a line.
          (loop
             for lft across left-fft-data
             for rgt across right-fft-data
             for idx below height
             do
               (q+:draw-line painter
                             (truncate (xmapper (- (abs lft)))) idx
                             (truncate (xmapper (abs rgt))) idx)))))))


;; Create all of the controls

(define-subwidget (main-window viz-widget) (make-instance 'fft-drawer)
  "The fft-drawer itself.")

(define-slot (main-window open open-file) ()
  (let ((filename (q+:qfiledialog-get-open-file-name main-window "Select File"
                                                     (q+:qdesktopservices-storage-location 
                                                      (q+:qdesktopservices.music-location))
                                                     "*.mp3")))
    (if filename
        (let* ((new-mp3-file (read-mp3-file filename))
               (sduration (mp3-file-duration-in-seconds new-mp3-file))
               (tframes (ceiling (* sduration *fps*))))
          (setf (slot-value viz-widget 'current-location) 0)
          (setf (slot-value viz-widget 'the-mp3) (copy-mp3-file new-mp3-file))
          (setf (slot-value viz-widget 'song-duration) sduration)
          (setf (slot-value viz-widget 'total-frames) tframes)
          (when current-stream (mixalot:mixer-remove-streamer mixer current-stream))
          (setf current-stream (mixalot-mp3:make-mp3-streamer filename))
          (mixalot:mixer-add-streamer mixer current-stream)))))

(define-initializer (main-window setup)
  "Set the window title and set the fft-controls to be the central widget."
  (setf (q+:window-title main-window) "Interactive FFT Explorer")
  (setf (q+:central-widget main-window) viz-widget))

(defun main ()
  "Create the main window."
  (with-main-window (window (make-instance 'main-window))))


;; (define-subwidget (main-window window-spin) (q+:make-qspinbox main-window)
;;   "The FFT window size spinbox."
;;   (q+:set-single-step hval-spin 0.01)
;;   (q+:set-maximum hval-spin 1000.0)
;;   (q+:set-minimum hval-spin 0.01)
;;   (q+:set-value hval-spin (slot-value sviewer 'h-val)))
