;;; math-preview.el --- Preview TeX math equations inline -*- lexical-binding: t -*-

;; Author: Matsievskiy S.V.
;; Maintainer: Matsievskiy S.V.
;; Version: 5.1.2
;; Package-Requires: ((emacs "26.1") (json "1.4") (dash "2.18.0") (s "1.12.0"))
;; Homepage: https://gitlab.com/matsievskiysv/math-preview
;; Keywords: convenience


;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.


;;; Commentary:

;; Preview TeX math equations inline using MathJax
;; This package requires external program math-preview.
;; Installation instructions are available in README.md file.

;;; Code:

(require 'json)
(require 'dash)
(require 's)
(require 'xml)


;; {{{ Customization
(defgroup math-preview nil
  "Preview math inline."
  :group  'text
  :tag    "Math Preview"
  :prefix "math-preview-"
  :link   '(url-link :tag "GitLab" "https://gitlab.com/matsievskiysv/math-preview"))

(defface math-preview-face
  '((t :inherit default))
  "Face for equation.")

(defface math-preview-processing-face
  '((t :inherit highlight))
  "Face for equation processing.")

(defcustom math-preview-command "math-preview"
  "TeX conversion program name."
  :tag "Command name"
  :type '(choice (string :tag "Command name")
                 (repeat :tag "Command arguments" (string :tag "Argument")))
  :safe (lambda (n) (or (stringp n)
                   (and (listp n)
                        (-all-p #'stringp n)))))

(defcustom math-preview-raise 0.4
  "Adjust vertical position of inline images.
This depends on `math-preview-raise-enable'."
  :tag "Image vertical position"
  :type 'number
  :safe (lambda (n) (and (numberp n)
                    (> n 0)
                    (< n 1))))

(defcustom math-preview-raise-enable nil
  "Enable vertical position adjustment for inline images.
When set to nil (the default), inline images are auto-positioned
according to their \\=`vertical-align\\=` properties.  For any other
value, their position is controlled by `math-preview-raise'."
  ;; If the default of auto-positioning proves sufficient, then `math-preview-raise` and `-raise-enable`
  ;; might eventually be deprecated.
  :tag "Image vertical position enable"
  :type 'boolean
  :safe t)

(defcustom math-preview-margin '(5 . 5)
  "Adjust image margin."
  :tag "Image margin"
  :type '(cons :tag "Configure margins" (integer :tag "Horizontal") (integer :tag "Vertical"))
  :safe (lambda (l) (and (consp l)
                    (integerp (car l))
                    (> (car l) 0)
                    (integerp (cdr l))
                    (> (cdr l) 0))))

(defcustom math-preview-relief 0
  "Adjust image relief."
  :tag "Image relief"
  :type 'integer
  :safe (lambda (n) (and (integerp n)
                    (> n 0))))

(defcustom math-preview-scale 1
  "Adjust image scale."
  :tag "Image scale"
  :type 'number
  :safe (lambda (n) (and (numberp n)
                    (> n 0))))

(defcustom math-preview-svg-postprocess-functions
  '((lambda (x) (puthash 'string (s-replace "width=\"100%\""
                                       (format "width=\"%dem\""
                                               (/ (window-max-chars-per-line) 2))
                                       (gethash 'string x))
                    x)))
  "Functions to call on resulting SVG string before rendering.
Functions are applied in chain from left to right (or from top to bottom, when
in `customize').  Each function accepts one arguments which is a hash table
with field `string'.  User may modify `string' in place to edit resulting image."
  :tag "Postprocess SVG functions"
  :type '(repeat function)
  :safe (lambda (n) (and (listp n)
                    (-all? #'functionp n))))

(defcustom math-preview-scale-increment 0.1
  "Image scale interactive increment value."
  :tag "Image scale increment"
  :type 'number
  :safe (lambda (n) (and (numberp n)
                    (> n 0))))

(defcustom math-preview-preprocess-functions (list)
  "Functions to call on each matched string.
Functions are applied in chain from left to right (or from top to bottom, when
in `customize').  Each function accepts one arguments which is a hash table
with fields: `match' matched string including marks; `string' matched string
without marks; `type' equation type (`tex', `mathml' or `asciimath');
`inline' equation inline flag; `lmark' and `rmark' are left and right marks
respectively.  User may modify `string', `inline' and `type' fields in place to
influence further equation processing (although the intended purpose of these
functions is to edit only `string' field).
These functions are evaluated after `math-preview-tex-preprocess-functions',
`math-preview-mathml-preprocess-functions' and
`math-preview-asciimath-preprocess-functions' functions."
  :tag "Preprocess functions"
  :type '(repeat function)
  :safe (lambda (n) (and (listp n)
                    (-all? #'functionp n))))

(defgroup math-preview-tex nil
  "TeX options."
  :group  'math-preview
  :prefix "math-preview-tex-")

(defcustom math-preview-tex-marks
  '(("\\begin{equation}" "\\end{equation}" 0 nil nil)
    ("\\begin{equation*}" "\\end{equation*}" 0 nil nil)
    ("\\[" "\\]" 0 nil nil)
    ("$$" "$$" 0 nil nil))
  "Strings marking beginning and end of TeX equation. By default, when searching for equation marks,
the largest match has the priority."
  :tag "TeX equation marks"
  :type '(repeat :tag "Mark pairs" (list :tag "Mark pair"
                                         (string :tag "Left  mark")
                                         (string :tag "Right mark")
                                         (integer :tag "Priority")
                                         (boolean :tag "Left  regexp")
                                         (boolean :tag "Right regexp")))
  :safe #'math-preview--check-marks)

(defcustom math-preview-tex-marks-inline
  '(("\\(" "\\)" 0 nil nil)
    ("$" "$" 0 nil nil)
    ("`$" "`$" 0 nil nil))
  "Strings marking beginning and end of TeX inline equation."
  :tag "TeX equation inline marks"
  :type '(repeat :tag "Mark pairs" (list :tag "Mark pair"
                                         (string :tag "Left  mark")
                                         (string :tag "Right mark")
                                         (integer :tag "Priority")
                                         (boolean :tag "Left  regexp")
                                         (boolean :tag "Right regexp")))
  :safe #'math-preview--check-marks)

(defcustom math-preview-tex-preprocess-functions
  '((lambda (x) (when (and (s-prefix? "\\begin" (gethash 'lmark x))
                      (s-prefix? "\\end" (gethash 'rmark x)))
             (puthash 'string (gethash 'match x) x))))
  "Functions to call on each TeX string.
Functions are applied in chain from left to right (or from top to bottom, when
in `customize').  Each function accepts one arguments which is a hash table
with fields: `match' matched string including marks; `string' matched string
without marks; `type' equation type (`tex', `mathml' or `asciimath');
`inline' equation inline flag; `lmark' and `rmark' are left and right marks
respectively.  User may modify `string', `inline' and `type' fields in place to
influence further equation processing (although the intended purpose of these
functions is to edit only `string' field).
These functions are evaluated before `math-preview-preprocess-functions'
functions."
  :tag "Preprocess TeX functions"
  :type '(repeat function)
  :safe (lambda (n) (and (listp n)
                    (-all? #'functionp n))))

(defcustom math-preview-tex-macros
  `(("ddx" . ("\\frac{d#2}{d#1}" 2 "t")))
  "List of predefined macros.
`\\' in the name of the macro must be omitted.  If macro does not have any
arguments, then macro definition is a string.  If macro have arguments, then
macro definition is a list, where first item is a definition string, second
item is a number of macro arguments and third argument is the optional default
value for the first argument.  More information at the page
http://docs.mathjax.org/en/latest/input/tex/macros.html#tex-macros and
http://docs.mathjax.org/en/latest/input/tex/extensions/configmacros.html."
  :tag "Macro list"
  :type '(alist :key-type (string :tag "Name")
                :value-type (choice :tag "Definition"
                                    (string :tag "Without arguments")
                                    (list :tag "With arguments"
                                          (string :tag "Definition")
                                          (integer :tag "Number of arguments")
                                          (choice :tag "Default value"
                                                  (const :tag "None" nil)
                                                  (string :tag "Default value")))
                                    (list :tag "Template based"
                                          (string :tag "Definition")
                                          (integer :tag "Number of arguments")
                                          (repeat :tag "Templates"
                                                  (string :tag "Template")))))
  :safe (lambda (n) (and (listp n)
                    (-all? (lambda (x) (and (stringp (car x))
			               (or (stringp (cdr x))
			                   (listp (cdr x)))))
                           n))))

(defcustom math-preview-tex-environments
  `(("braced" . ("\\left\\{" "\\right\\}")))
  "List of predefined environments.
`\\' in the name of the macro must be omitted.  If environment does not have
any arguments, then environment definition is a pair of strings.  If environment
have arguments, then environment definition is a list, where first two items
are pair of definition strings, third item is a number of environment
arguments and fourth argument is the optional default value for the first
argument.  More information at the page
http://docs.mathjax.org/en/latest/input/tex/environments.html#tex-environments
and
http://docs.mathjax.org/en/latest/input/tex/extensions/configenvironments.html."
  :tag "Environment list"
  :type '(alist :key-type (string :tag "Name")
                :value-type (choice :tag "Definition"
                                    (list :tag "Without arguments"
                                          (string :tag "Before")
                                          (string :tag "After "))
                                    (list :tag "With arguments"
                                          (string :tag "Before")
                                          (string :tag "After ")
                                          (integer :tag "Number of arguments")
                                          (choice :tag "Default value"
                                                  (const :tag "None" nil)
                                                  (string :tag "Default value")))))
  :safe (lambda (n) (and (listp n)
                    (-all? (lambda (x) (and (stringp (car x))
			               (listp (cdr x))))
                           n))))

(defgroup math-preview-tex-packages nil
  "TeX package options."
  :group  'math-preview-tex
  :prefix "math-preview-tex-package-")

(defcustom math-preview-tex-default-packages '("autoload" "ams" "cancel" "color")
  "List of default `TeX' packages to load.
This array lists the names of the packages (extensions) that should be
initialized by the `TeX' input processor.  Packages not in this list must
be loaded using `\\require{}' macro or via `autoload' mechanism.
Extension list is available at the page
http://docs.mathjax.org/en/latest/input/tex/extensions/index.html.
`base', `require', `newcommand' and `configmacros' are always loaded."
  :tag "Default TeX packages"
  :type '(repeat string)
  :safe (lambda (l) (-all? 'stringp l)))

(defgroup math-preview-tex-packages-ams nil
  "TeX ams package options.
http://docs.mathjax.org/en/latest/input/tex/extensions/ams.html"
  :group  'math-preview-tex-packages
  :prefix "math-preview-tex-package-ams-")

(defcustom math-preview-tex-packages-ams-multline-width "100%"
  "The width to use for multline environments."
  :tag "Multline width"
  :type 'string
  :safe #'stringp)

(defcustom math-preview-tex-packages-ams-multline-indent "1em"
  "The margin to use on both sides of multline environments."
  :tag "Multline indent"
  :type 'string
  :safe #'stringp)

(defgroup math-preview-tex-packages-amscd nil
  "TeX amscd package options.
http://docs.mathjax.org/en/latest/input/tex/extensions/amscd.html"
  :group  'math-preview-tex-packages
  :prefix "math-preview-tex-package-amscd-")

(defcustom math-preview-tex-packages-amsdc-colspace "5pt"
  "Column space.
This gives the amount of space to use between columns in the commutative
diagram."
  :tag "Column space"
  :type 'string
  :safe #'stringp)

(defcustom math-preview-tex-packages-amsdc-rowspace "5pt"
  "Row space.
This gives the amount of space to use between rows in the commutative
diagram."
  :tag "Row space"
  :type 'string
  :safe #'stringp)

(defcustom math-preview-tex-packages-amsdc-harrowsize "2.75em"
  "Horizontal arrow size.
This gives the minimum size for horizontal arrows in the commutative
diagram."
  :tag "Horizontal arrow size"
  :type 'string
  :safe #'stringp)

(defcustom math-preview-tex-packages-amsdc-varrowsize "2.75em"
  "Vertical arrow size.
This gives the minimum size for vertical arrows in the commutative
diagram."
  :tag "Vertical arrow size"
  :type 'string
  :safe #'stringp)

(defcustom math-preview-tex-packages-amsdc-hide-horizontal-labels nil
  "Hide horizontal labels.
This determines whether horizontal arrows with labels above or below
will use `\\smash' in order to hide the height of the labels.
\(Labels above or below horizontal arrows can cause excess space between rows,
so setting this to true can improve the look of the diagram.)"
  :tag "Hide horizontal labels"
  :type 'boolean
  :safe t)

(defgroup math-preview-tex-packages-autoload nil
  "TeX autoload package options.
http://docs.mathjax.org/en/latest/input/tex/extensions/autoload.html"
  :group  'math-preview-tex-packages
  :prefix "math-preview-tex-package-autoload-")

(defcustom math-preview-tex-packages-autoload-packages
  '(("action" . ("toggle" "mathtip" "texttip"))
    ("amscd" . (() ("CD")))
    ("bbox" . ("bbox"))
    ("boldsymbol" . ("boldsymbol"))
    ("braket" . ("bra" "ket" "braket" "set" "Bra" "Ket" "Braket" "Set" "ketbra" "Ketbra"))
    ("cancel" . ("cancel" "bcancel" "xcancel" "cancelto"))
    ("color" . ("color" "definecolor" "textcolor" "colorbox" "fcolorbox"))
    ("enclose" . ("enclose"))
    ("extpfeil" . ("xtwoheadrightarrow" "xtwoheadleftarrow" "xmapsto"
                   "xlongequal" "xtofrom" "Newextarrow"))
    ("html" . ("href" "class" "style" "cssId"))
    ("mhchem" . ("ce" "pu"))
    ("unicode" . ("unicode"))
    ("upgreek" . ("upalpha" "upbeta" "upchi" "updelta" "Updelta" "upepsilon"
                "upeta" "upgamma" "Upgamma" "upiota" "upkappa" "uplambda"
                "Uplambda" "upmu" "upnu" "upomega" "Upomega" "upomicron"
                "upphi" "Upphi" "uppi" "Uppi" "uppsi" "Uppsi" "uprho"
                "upsigma" "Upsigma" "uptau" "uptheta" "Uptheta" "upupsilon"
                "Upupsilon" "upvarepsilon" "upvarphi" "upvarpi" "upvarrho"
                "upvarsigma" "upvartheta" "upxi" "Upxi" "upzeta"))
    ("verb" . ("verb")))
  "Auto-loading macros and environments.
Adding the autoload extension to the packages array defines an
auto-load sub-block to the `TeX' configuration block.  This block
contains key: value pairs where the key is a `TeX' package name,
and the value is an array of macros that cause that package to be loaded,
or an array consisting of two arrays, the first giving names of macros and
the second names of environments; the first time any of them are used,
the extension will be loaded automatically."
  :tag "Packages"
  :type '(alist :tag "Package"
                :key-type (string :tag "Name")
                :value-type (choice (repeat :tag "Macros"
                                            (string :tag "Macro"))
                                    (list :tag "Macros and Environments"
                                          (repeat :tag "Macros"
                                                  (string :tag "Macro"))
                                          (repeat :tag "Environments"
                                                  (string :tag "Environment")))))
  :safe (lambda (n) (and (listp n)
                    (-all? (lambda (x) (and (stringp (car x))
			               (listp (cdr x))
			               (or (-all? #'stringp (cdr x))
			                   (and (listp (-first-item (cdr x)))
				                (listp (-second-item (cdr x)))
				                (-all? #'stringp (-first-item (cdr x)))
				                (-all? #'stringp (-second-item (cdr x)))))))
                           n))))

(defgroup math-preview-tex-packages-physics nil
  "TeX physics package options.
http://docs.mathjax.org/en/latest/input/tex/extensions/physics.html"
  :group  'math-preview-tex-packages
  :prefix "math-preview-tex-package-physics-")

(defcustom math-preview-tex-packages-physics-italicdiff nil
  "Italic diff.
This corresponds to the `italicdiff' option of the `physics'
`LaTeX' package to use italic form for the `d' in the `\differential' and
`\derivative' commands."
  :tag "Italic diff"
  :type 'boolean
  :safe t)

(defcustom math-preview-tex-packages-physics-arrowdel nil
  "Arrow del.
This corresponds to the `arrowdel' option of the `physics'
`LaTeX' package to use vector notation over the `nabla' symbol."
  :tag "Arrow del"
  :type 'boolean
  :safe t)

(defgroup math-preview-mathml nil
  "MathML options."
  :group  'math-preview
  :prefix "math-preview-mathml-")

(defcustom math-preview-mathml-marks
  '(("<math" "</math>" 0 nil nil))
  "Strings marking beginning and end of MathML equation."
  :tag "MathML equation marks"
  :type '(repeat :tag "Mark pairs" (list :tag "Mark pair"
                                         (string :tag "Left  mark")
                                         (string :tag "Right mark")
                                         (integer :tag "Priority")
                                         (boolean :tag "Left  regexp")
                                         (boolean :tag "Right regexp")))
  :safe #'math-preview--check-marks)

(defcustom math-preview-mathml-marks-inline (list)
  "Strings marking beginning and end of MathML inline equation."
  :tag "MathML equation inline marks"
  :type '(repeat :tag "Mark pairs" (list :tag "Mark pair"
                                         (string :tag "Left  mark")
                                         (string :tag "Right mark")
                                         (integer :tag "Priority")
                                         (boolean :tag "Left  regexp")
                                         (boolean :tag "Right regexp")))
  :safe #'math-preview--check-marks)

(defcustom math-preview-mathml-preprocess-functions '((lambda (x) (puthash 'string (gethash 'match x) x)))
  "Functions to call on each MathML string.
Functions are applied in chain from left to right (or from top to bottom, when
in `customize').  Each function accepts one arguments which is a hash table
with fields: `match' matched string including marks; `string' matched string
without marks; `type' equation type (`tex', `mathml' or `asciimath');
`inline' equation inline flag; `lmark' and `rmark' are left and right marks
respectively.  User may modify `string', `inline' and `type' fields in place to
influence further equation processing (although the intended purpose of these
functions is to edit only `string' field).
These functions are evaluated before `math-preview-preprocess-functions'
functions."
  :tag "Preprocess MathML functions"
  :type '(repeat function)
  :safe (lambda (n) (and (listp n)
                    (-all? #'functionp n))))

(defgroup math-preview-asciimath nil
  "AsciiDoc options."
  :group  'math-preview
  :prefix "math-preview-asciimath-")

(defcustom math-preview-asciimath-marks (list)
  "Strings marking beginning and end of AsciiMath equation."
  :tag "AsciiMath equation marks"
  :type '(repeat :tag "Mark pairs" (list :tag "Mark pair"
                                         (string :tag "Left  mark")
                                         (string :tag "Right mark")
                                         (integer :tag "Priority")
                                         (boolean :tag "Left  regexp")
                                         (boolean :tag "Right regexp")))
  :safe #'math-preview--check-marks)

(defcustom math-preview-asciimath-marks-inline (list)
  "Strings marking beginning and end of AsciiMath inline equation."
  :tag "AsciiMath equation inline marks"
  :type '(repeat :tag "Mark pairs" (list :tag "Mark pair"
                                         (string :tag "Left  mark")
                                         (string :tag "Right mark")
                                         (integer :tag "Priority")
                                         (boolean :tag "Left  regexp")
                                         (boolean :tag "Right regexp")))
  :safe #'math-preview--check-marks)

(defcustom math-preview-asciimath-preprocess-functions (list)
  "Functions to call on each AsciiMath string.
Functions are applied in chain from left to right (or from top to bottom, when
in `customize').  Each function accepts one arguments which is a hash table
with fields: `match' matched string including marks; `string' matched string
without marks; `type' equation type (`tex', `mathml' or `asciimath');
`inline' equation inline flag; `lmark' and `rmark' are left and right marks
respectively.  User may modify `string', `inline' and `type' fields in place to
influence further equation processing (although the intended purpose of these
functions is to edit only `string' field).
These functions are evaluated before `math-preview-preprocess-functions'
functions."
  :tag "Preprocess AsciiMath functions"
  :type '(repeat function)
  :safe (lambda (n) (and (listp n)
                    (-all? #'functionp n))))

(defgroup math-preview-mathjax nil
  "MathJax options."
  :group  'math-preview
  :prefix "math-preview-mathjax-")

(defcustom math-preview-mathjax-em #'window-font-width
  "Number giving the number of pixels in an `em' for the surrounding font."
  :tag "Em size"
  :type '(choice (integer :tag "Constant value")
                 (function :tag "Calculate using function"))
  :safe (lambda (n) (or (functionp n)
                   (and (numberp n)
                        (> n 0)))))

(defcustom math-preview-mathjax-ex #'window-font-height
  "Number giving the number of pixels in an `ex' for the surrounding font."
  :tag "Ex size"
  :type '(choice (integer :tag "Constant value")
                 (function :tag "Calculate using function"))
  :safe (lambda (n) (or (functionp n)
                   (and (numberp n)
                        (> n 0)))))

(defcustom math-preview-mathjax-container-width #'window-pixel-width
  "Number giving the width of the container, in pixels."
  :tag "Container width"
  :type '(choice (integer :tag "Constant value")
                 (function :tag "Calculate using function"))
  :safe (lambda (n) (or (functionp n)
                   (and (numberp n)
                        (> n 0)))))

(defcustom math-preview-mathjax-line-width #'window-max-chars-per-line
  "Number giving the line-breaking width in `em' units."
  :tag "Max width"
  :type '(choice (integer :tag "Constant value")
                 (function :tag "Calculate using function"))
  :safe (lambda (n) (or (functionp n)
                   (and (numberp n)
                        (> n 0)))))

(defcustom math-preview-mathjax-scale 1
  "Number giving a scaling factor to apply to the resulting conversion."
  :tag "Scale"
  :type 'number
  :safe (lambda (n) (and (numberp n)
                    (> n 0))))

(defgroup math-preview-mathjax-loader nil
  "MathJax loader options.
http://docs.mathjax.org/en/latest/options/startup/loader.html"
  :group  'math-preview-mathjax
  :prefix "math-preview-mathjax-loader-")

(defcustom math-preview-mathjax-loader-load (list "input/tex-full" "input/mml" "input/asciimath" "output/svg")
  "This array lists the components that you want to load."
  :tag "Load list"
  :type '(repeat string)
  :safe (lambda (l) (-all? 'stringp l)))

(defgroup math-preview-mathjax-tex nil
  "MathJax `TeX' configuration options.
The options below control the operation of the TeX input processor that
is run when you include `input/tex', `input/tex-full', or `input/tex-base'
in the load array of the loader block of your MathJax configuration.
http://docs.mathjax.org/en/latest/options/input/tex.html"
  :group  'math-preview-mathjax
  :prefix "math-preview-mathjax-tex-")

(defcustom math-preview-mathjax-tex-process-escapes t
  "Process escapes.
When set to true, you may use `\\$' to represent a literal dollar sign,
rather than using it as a math delimiter, and `\\\\' to represent a literal
backslash."
  :tag "Process escapes"
  :type 'boolean
  :safe t)

(defcustom math-preview-mathjax-tex-digits "/^(?:[0-9]+(?:\\{,\\}[0-9]*)?|\\{,\\}[0-9]+)/"
  "Digit regular expression.
This gives a regular expression that is used to identify numbers
during the parsing of your TeX expressions.  By default, the decimal point
is `.' and you can use `,' between every three digits before that.
If you want to use `,' as the decimal indicator, use
`/^(?:[0-9]+(?:\\{,\\}[0-9]*)?|\\{,\\}[0-9]+)/'"
  :tag "Digits"
  :type 'string
  :safe 'stringp)

(defcustom math-preview-mathjax-tags "none"
  "Auto-numbering tags.
This controls whether equations are numbered and how.
By default it is set to `none' to be compatible with earlier versions of MathJax where auto-numbering
was not performed (so pages will not change their appearance).
You can change this to `ams' for equations numbered as the AMSmath package would do,
or `all' to get an equation number for every displayed equation."
  :tag "Tags"
  :type '(choice (const :tag "None" "none")
                 (const :tag "AMS math" "ams")
                 (const :tag "All" "all"))
  :safe 'stringp)

(defcustom math-preview-mathjax-tags-side "right"
  "Tags side.
This specifies the side on which `\\tag{}' macros will place the tags,
and on which automatic equation numbers will appear.
Set it to `left' to place the tags on the left-hand side."
  :tag "Tags side"
  :type '(choice (const :tag "Left" "left")
                 (const :tag "Right" "right"))
  :safe 'stringp)

(defcustom math-preview-mathjax-tag-indent "0.8em"
  "Tag indent.
This is the amount of indentation (from the right or left) for the tags
produced by the `\\tag{}' macro."
  :tag "Tag indent"
  :type 'string
  :safe 'stringp)

(defgroup math-preview-mathjax-svg nil
  "MathJax SVG configuration options.
The options below control the operation of the SVG output processor that
is run when you include `output/svg' in the load array of the loader block.
http://docs.mathjax.org/en/latest/options/output/svg.html#svg-options"
  :group  'math-preview-mathjax
  :prefix "math-preview-mathjax-svg-")

(defcustom math-preview-mathjax-svg-scale 1
  "Global scaling factor for all expressions."
  :tag "Scale"
  :type 'number
  :safe (lambda (n) (and (numberp n)
                    (> n 0))))

(defcustom math-preview-mathjax-svg-min-scale 0.5
  "Smallest scaling factor to use."
  :tag "Min scale"
  :type 'number
  :safe (lambda (n) (and (numberp n)
                    (> n 0))))

(defcustom math-preview-mathjax-svg-mathml-spacing nil
  "Spacing rules.
True for `MathML' spacing rules, false for `TeX' rules."
  :tag "MathML spacing"
  :type 'boolean
  :safe t)

(defcustom math-preview-mathjax-svg-ex-factor 0.5
  "Default size of `ex' in `em' units."
  :tag "Ex factor"
  :type 'number
  :safe (lambda (n) (and (numberp n)
                    (> n 0))))

(defcustom math-preview-mathjax-svg-display-align "left"
  "Default for `indentalign' when set to `auto'."
  :tag "Display align"
  :type '(choice (const :tag "Left" "left")
                 (const :tag "Center" "center")
                 (const :tag "Right" "right")))

(defcustom math-preview-mathjax-svg-display-indent "0"
  "Default for `indentshift' when set to `auto'."
  :tag "Display indent"
  :type 'string
  :safe 'stringp)
;; }}}

;; {{{ Variables
(defvar math-preview--schema-version 5 "`math-preview' json schema version.")

(defvar math-preview--queue nil "Job queue.")

(defvar math-preview--reset-numbering nil "MathJax reset numbering flag. Number to start new numbering from or `nil'.")

(defvar math-preview-map (let ((keymap (make-keymap)))
                           (suppress-keymap keymap t)
                           (define-key keymap (kbd "<delete>")		#'math-preview-clear-at-point)
                           (define-key keymap (kbd "<backspace>")	#'math-preview-clear-at-point)
                           (define-key keymap (kbd "SPC")		#'math-preview-clear-at-point)
                           (define-key keymap (kbd "RET")		#'math-preview-clear-at-point)
                           (define-key keymap (kbd "<mouse-1>")		#'math-preview-clear-at-point)
                           (define-key keymap (kbd "<C-delete>")	#'math-preview-clear-all)
                           (define-key keymap (kbd "<C-backspace>")	#'math-preview-clear-all)
                           (define-key keymap (kbd "<C-mouse-1>")	#'math-preview-clear-all)
                           (define-key keymap (kbd "+")			#'math-preview-increment-scale)
                           (define-key keymap (kbd "p")			#'math-preview-increment-scale)
                           (define-key keymap (kbd "-")			#'math-preview-decrement-scale)
                           (define-key keymap (kbd "n")			#'math-preview-decrement-scale)
                           (define-key keymap (kbd "<C-return>")	#'math-preview-copy-svg)
                           (define-key keymap (kbd "C-SPC")		#'math-preview-copy-svg)
                           keymap)
  "Key map for math-preview image overlays.")

(defvar math-preview--input-buffer ""
  "Buffer holds input message.")

(defvar math-preview--debug-json nil
  "Switch for enabling JSON dump into `math-preview--output-buffer'.")

(defvar math-preview--newline-replacement-string " "
  "String that replaces `\n' character before the regexp matching.")

(defvar math-preview--vertical-align-pattern (concat "\\(?:\\`\\|[; ]\\)vertical-align: *\\([^; ]+\\)")
  "The pattern of a CSS \\=`vertical-align\\=` property.
It captures group (1) the property value.")

(put 'math-preview 'face 'math-preview-face)
(put 'math-preview 'keymap math-preview-map)
(put 'math-preview 'evaporate t)
(put 'math-preview 'help-echo "mouse-1 to remove")
(put 'math-preview 'mouse-face 'math-preview-processing-face)
(put 'math-preview-processing 'face 'math-preview-processing-face)
;; }}}

;; {{{ Process
(defun math-preview--json-bool (arg)
  "Convert boolean `ARG' to `JSON'.
JSON encoder cannot distinguish `null' and `false', therefore we need to
use `json-false' to encode `false'."
  (if arg arg json-false))

(defun math-preview--number-or-function (f)
  "Get number from field `F' which can be number of a function."
  (if (functionp f) (funcall f) f))

(defun math-preview--encode-arguments ()
  "Encode program arguments in JSON strings."
  (let* ((loader (list (cons "loader" (list (cons "load" math-preview-mathjax-loader-load)))))
         (svg (list (cons "svg" (list
                                 (cons "scale" math-preview-mathjax-svg-scale)
                                 (cons "minScale" math-preview-mathjax-svg-min-scale)
                                 (cons "mathmlSpacing" (math-preview--json-bool math-preview-mathjax-svg-mathml-spacing))
                                 (cons "exFactor" math-preview-mathjax-svg-ex-factor)
                                 (cons "displayAlign" math-preview-mathjax-svg-display-align)
                                 (cons "displayIndent" math-preview-mathjax-svg-display-indent)))))
         (tex (list (cons "tex" (list
                                 (cons"processEscapes" (math-preview--json-bool math-preview-mathjax-svg-mathml-spacing))
                                 (cons "digits" math-preview-mathjax-tex-digits)
                                 (cons "tags" math-preview-mathjax-tags)
                                 (cons "tagSide" math-preview-mathjax-tags-side)
                                 (cons "tagIndent" math-preview-mathjax-tag-indent)))))
         (tex-macros (list (cons "tex/macros" math-preview-tex-macros)))
         (tex-environments (list (cons "tex/environments" math-preview-tex-environments)))
         (ams (list (cons "multlineWidth" math-preview-tex-packages-ams-multline-width)
                    (cons "multlineIndent" math-preview-tex-packages-ams-multline-indent)))
         (amscd (list (cons "colspace" math-preview-tex-packages-amsdc-colspace)
                      (cons "rowspace" math-preview-tex-packages-amsdc-rowspace)
                      (cons "harrowsize" math-preview-tex-packages-amsdc-harrowsize)
                      (cons "varrowsize" math-preview-tex-packages-amsdc-varrowsize)
                      (cons "hideHorizontalLabels" (math-preview--json-bool
                                              math-preview-tex-packages-amsdc-hide-horizontal-labels))))
         (autoload math-preview-tex-packages-autoload-packages)
         (physics (list (cons "italicdiff" (math-preview--json-bool math-preview-tex-packages-physics-italicdiff))
                        (cons "arrowdel" (math-preview--json-bool math-preview-tex-packages-physics-arrowdel))))
         (tex-packages (list (cons "tex/packages" (list (cons "tex/packages/list" math-preview-tex-default-packages)
                                                        (cons "ams" ams)
                                                        (cons "amscd" amscd)
                                                        (cons "autoload" autoload)
                                                        (cons "physics" physics))))))
    ;; assume all nulls are wrongfully encoded empty lists
    (--map (s-replace "null" "[]" it) (list
                                       (json-encode-alist loader)
                                       (json-encode-alist svg)
                                       (json-encode-alist tex)
                                       (json-encode-alist tex-macros)
                                       (json-encode-alist tex-environments)
                                       (json-encode-alist tex-packages)))))

;;;###autoload
(defun math-preview-start-process ()
  "Start math-preview process."
  (interactive)
  (let ((proc (get-process "math-preview"))
        (process-connection-type nil))
    (unless proc
      (math-preview-stop-process) ; clear garbage from previous session
      (let* ((command (if (listp math-preview-command)
                          math-preview-command
                        (list math-preview-command)))
             (executable (car command))
             (p (executable-find executable)))
        (unless p
          (error "%s is not an executable" executable))
        (setq proc (make-process :name "math-preview"
                                 :command (-concat command
                                                   (math-preview--encode-arguments))
                                 :coding 'utf-8
                                 :noquery t
                                 :connection-type 'pipe
                                 :filter #'math-preview--process-filter))
        (unless (process-live-p proc)
          (error "Cannot start process"))))
    proc))

;;;###autoload
(defun math-preview-stop-process ()
  "Stop math-preview process."
  (interactive)
  (let ((proc (get-process "math-preview")))
    (setq math-preview--queue nil)
    (math-preview--overlays-remove-processing)
    (when proc
      (kill-process proc))))

(defun math-preview--svg-element (svg-src)
  "The parsed SVG document element of SVG-SRC, or nil if parsing fails."
  (with-temp-buffer
    (insert svg-src)
    (goto-char 1)
    (xml-parse-tag))); Here avoiding the foreign library dependency of `libxml-parse-xml-region`.

(defun math-preview--make-image (svg-src ascent)
  (create-image svg-src 'svg t
                :scale math-preview-scale
                :ascent ascent
                :pointer 'hand
                :margin math-preview-margin
                :relief math-preview-relief))

(defun math-preview--process-filter (_process message)
  "Handle `MESSAGE' from math-preview `PROCESS'.
Call `math-preview--process-input' for strings with carriage return."
  (setq message
        (s-replace "" ""
                   (s-concat math-preview--input-buffer message))) ; ignore carriage return
  ;; buffer incomplete input
  (let ((lines (s-lines message)))
    (setq math-preview--input-buffer (-first-item (-take-last 1 lines)))
    (->> lines
         (-drop-last 1)
         (-map #'math-preview--process-input))))

(defun math-preview--process-input (message)
  "Process input MESSAGE line."
  (when math-preview--debug-json
    (with-current-buffer (get-buffer-create "*math-preview*")
      (goto-char (point-max))
      (insert "Incoming:")
      (insert message)
      (insert "\n")))
  (when (and (string-prefix-p "{" message) (string-suffix-p "}" message)
             (string-search "\"id\":" message 1))
    (let* ((msg (json-read-from-string message))
           (id (cdr (assoc 'id msg)))
           (type (cdr (assoc 'type msg)))
           (payload (cdr (assoc 'payload msg)))
           inline target-overlay)
      (unless (= id -1)
        (let ((p (--first (= (car it) id) math-preview--queue)))
          (setq target-overlay (nth 1 p)
                inline (nth 2 p)))
        (setq math-preview--queue (--remove (= (car it) id) math-preview--queue)))
      (cond
       ((string= "error" type) (message "%s" payload) (when target-overlay (delete-overlay target-overlay)))
       ((string= "svg" type)
        (let ((table (make-hash-table :size 1)))
          (puthash 'string payload table)
          (run-hook-with-args 'math-preview-svg-postprocess-functions table)
          (setq payload (gethash 'string table)))
        (let (image ascent; The image and its `ascent` property.
              raise; Display `raise` factor.
              svg-el va rh)
          (if (not inline)

              ;; Block-form image
              ;; ────────────────
              (setq ascent 'center; Centered on the vertical centerline.  This generally looks better
                          ;;; than 50% (the default) or 100%.  The difference is slight when block
                          ;;; math is written as an actual block (isolated from other text lines),
                    raise 0); but large when written inline (then the alternatives look screwy).

            ;; Inline image
            ;; ────────────
            (setq svg-el (math-preview--svg-element payload)
                  ascent 50; Centered on the baseline (default).  These two settings establish a default
                  raise math-preview-raise); alignment in case auto-positioning (below) either gets
            (when (and (not math-preview-raise-enable); disabled by `math-preview-raise-enable` or fails.
                       svg-el
                       (setq rh (xml-get-attribute-or-nil svg-el 'height))
                       (let ((style (xml-get-attribute svg-el 'style)))
                         (when (string-match math-preview--vertical-align-pattern style)
                           (setq va (match-string 1 style)))))
              (let ((is-ex-va (string-suffix-p "ex" va))
                    (is-ex-rh (string-suffix-p "ex" rh))
                    ah; Absolute height of the realized image, in pixels.
                    px-per-ex; Consequent ex-to-pixel conversion factor.
                    hb)
                (setq va (string-to-number va); Numeric part of CSS `vertical-align` property.
                      rh (string-to-number rh)); Numeric part of `height` attribute.
                (when (and (or is-ex-va (zerop va)); Requiring that both `va` and `rh` be expressed
                           (or is-ex-rh (zerop rh))); relatively, in ex units, as expected.

                  ;; Auto-position the inline image by applying its `vertical-align` property
                  ;; ─────────────
                  (setq ascent 100; Sit the image on the baseline from which `vertical-align`
                          ;;; is defined as an offset. [VA]
                        image (math-preview--make-image payload ascent)
                        ah (cdr (image-size image :pixels))); Height of image plus any decoration.
                  (let ((m (image-property image :margin))  ; Now subtract the decoration, leaving
                        (r (image-property image :relief))) ; just the height of the bare image:
                    (when m
                      (when (consp m) (setq m (cdr m)))
                      (cl-assert (natnump m))
                      (setq ah (- ah (* m 2))))
                    (when r
                      (cl-assert (integerp r))
                      (setq ah (- ah (* (abs r) 2)))))
                  (let ((hf (frame-char-height))); Height of the frame default font, in pixels.
                    (setq hb (default-font-height)); Height of the buffer default font, in pixels. [BDF]
                    (when (/= hf hb); Then a different font size was set on the buffer, and Emacs will
                      (setq ah (round (* ah (/ hb (float hf))))))); scale the image accordingly. [SBF]
                  (setq rh (float rh); Likely a no-op.  Regardless it ensures that
                        px-per-ex (/ ah rh); this division uses floating-point math.
                        ;;
                        ;; The calculation here is basically a conversion from the units of MathJax’s
                        ;; `vertical-align` CSS property (ex) to those of Emacs’s `raise` factor
                        ;; (font-heights) via the intermediary of display pixels (px).
                        ;;
                        ;;               px  =  ex ⋅ px/ex + rounding-correction    (1, 2)
                        ;;     font-heights  =  px ⋅ font-heights/px                (3)
                        ;;
                        va (* va px-per-ex);         (1) Convert from ex units to pixels.
                        va (+ va (copysign 0.5 va)); (2) Extend by ½ pixel, because something
                          ;;; in the `raise` implementation is truncating at pixel
                          ;;; granularity where instead it should be rounding.
                        raise (/ va hb)))))); (3) Convert from pixels to ‘affected text’ heights. [HAT]
                          ;;; No matter how accurate our `raise` factor, Emacs is going to snap the image
                          ;;; to a pixel grid.  If the fractional part of `va` is close to ½ pixel and
                          ;;; the font size small, then the image will look misaligned (too high or low)
                          ;;; regardless of the direction in which Emacs snaps it. [MPG]
          (unless image (setq image (math-preview--make-image payload ascent)))
          (overlay-put target-overlay 'category 'math-preview)
          (overlay-put target-overlay 'display (list (list 'raise raise) image))))))))

(defun math-preview--submit (beg end string type inline)
  "Submit equation processing job.
`BEG' and `END' are the positions of the overlay region.
`STRING' is an equation.
`TYPE' is `tex' or `mathml' or `asciimath'.
`INLINE' is a display style flag."
  (unless (math-preview--overlays beg end)
    (let ((proc (math-preview-start-process))
          (target-overlay (make-overlay beg end))
          (id (1+ (or (-> math-preview--queue (-first-item) (car)) 0)))
          msg)
      (overlay-put target-overlay 'category 'math-preview-processing)
      (setq math-preview--queue (-insert-at 0 (list id target-overlay inline) math-preview--queue))
      (setq msg (concat
                 (json-encode
                  (list :version math-preview--schema-version
                        :id id
                        :em (math-preview--number-or-function math-preview-mathjax-em)
                        :ex (math-preview--number-or-function math-preview-mathjax-ex)
                        :scale math-preview-mathjax-scale
                        :inline (math-preview--json-bool inline)
                        :containerWidth (math-preview--number-or-function math-preview-mathjax-container-width)
                        :lineWidth (math-preview--number-or-function math-preview-mathjax-line-width)
                        :payload string
                        :from type
                        :to "svg"
                        :reset_numbering (math-preview--json-bool (not (null math-preview--reset-numbering)))
                        :reset_from (- (or math-preview--reset-numbering 1) 1)))
                 "\n"))
      (setq math-preview--reset-numbering nil)
      (when math-preview--debug-json
        (with-current-buffer (get-buffer-create "*math-preview*")
          (goto-char (point-max))
          (insert "Outgoing:")
          (insert msg)))
      (process-send-string proc msg))))
;; }}}

;; {{{ Search
(defun math-preview--overlays (beg end)
  "Get math-preview overlays in region between `BEG' and `END'."
  (->> (if (= beg end) (overlays-at beg) (overlays-in beg end))
       (--filter (let ((cat (overlay-get it 'category)))
                   (or (eq cat 'math-preview)
                       (eq cat 'math-preview-processing))))))

(defun math-preview--overlays-remove-processing ()
  "Get math-preview overlays in region."
  (->> (overlays-in (point-min) (point-max))
       (--filter (eq (overlay-get it 'category) 'math-preview-processing))
       (--map (delete-overlay it))))

(defun math-preview--check-marks (arg)
  "Check that ARG is a valid `math-preview-marks' value."
  (and (listp arg)
       (not (-filter 'null (--map (and
	                           (listp it)
	                           (stringp (-first-item it))
                                   (not (s-matches? "^\s*$" (-first-item it)))
	                           (stringp (-second-item it))
	                           (not (s-matches? "^\s*$" (-second-item it)))
                                   (integerp (-third-item it))
                                   (booleanp (-fourth-item it))
                                   (booleanp (-fifth-item it)))
			          arg)))))

(defun math-preview--find-gaps (beg end)
  "Find gaps in math-preview overlays in region between `BEG' and `END'."
  (let ((o (math-preview--overlays beg end)))
    (->> (-zip-pair (-concat (list beg) (-sort #'< (-map #'overlay-end o)))
                    (-concat (-sort #'< (-map #'overlay-start o)) (list end)))
         (--filter (> (cdr it) beg))
         (--filter (< (car it) end)))))

(defun math-preview--search (beg end)
  "Search for equations in region between `BEG' and `END'."
  (let ((text (buffer-substring beg end))
        (regex (concat "\\(?:"
                       (s-join "\\|"
                               (--map
                                (s-join ".+?"
                                        (list (if (nth 5 it)
                                                  (-second-item it)
                                                (regexp-quote (-second-item it)))
                                              (if (nth 6 it)
                                                  (-third-item it)
                                                (regexp-quote (-third-item it)))))
                                (math-preview--create-mark-list)))
                       "\\)")))
    (->> (s-matched-positions-all
          regex
          (s-replace-all `(("\n" . ,math-preview--newline-replacement-string)) text))
         (-filter #'identity)
         (-flatten)
         (--map (cons (+ beg (car it))
                      (+ beg (cdr it)))))))

(defun math-preview--create-mark-list ()
  "Concatenate and reformat mark lists.
Output list format `(type left right inline? priority regexp?)'"
  (->> (-concat
        (--map (list "asciimath" (-first-item it) (-second-item it) t
                     (or (-third-item it) 0) (-fourth-item it) (-fifth-item it))
               math-preview-asciimath-marks-inline)
        (--map (list "asciimath" (-first-item it) (-second-item it) nil
                     (or (-third-item it) 0) (-fourth-item it) (-fifth-item it))
               math-preview-asciimath-marks)
        (--map (list "mathml" (-first-item it) (-second-item it) t
                     (or (-third-item it) 0) (-fourth-item it) (-fifth-item it))
               math-preview-mathml-marks-inline)
        (--map (list "mathml" (-first-item it) (-second-item it) nil
                     (or (-third-item it) 0) (-fourth-item it) (-fifth-item it))
               math-preview-mathml-marks)
        (--map (list "tex" (-first-item it) (-second-item it) t
                     (or (-third-item it) 0) (-fourth-item it) (-fifth-item it))
               math-preview-tex-marks-inline)
        (--map (list "tex" (-first-item it) (-second-item it) nil
                     (or (-third-item it) 0) (-fourth-item it) (-fifth-item it))
               math-preview-tex-marks))
       (--sort (cond
                ((not (= (-fifth-item it) (-fifth-item other)))
                 (> (-fifth-item it) (-fifth-item other)))
                ((not (= (length (-second-item it)) (length (-second-item other))))
                 (> (length (-second-item it)) (length (-second-item other))))
                ((not (= (length (-third-item it)) (length (-third-item other))))
                 (> (length (-third-item it)) (length (-third-item other))))
                (t t)))))

(defun math-preview--extract-match (string)
  "Extract match data from given `STRING'.
Return hash table containing original string, string with stripped marks,
type of equation, left and right marks."
  (let* ((string-no-newlines (s-replace-all `(("\n" . ,math-preview--newline-replacement-string)) string))
         (match (->> (math-preview--create-mark-list)
                     (--first (s-matches-p
                               (s-concat "^"
                                         (if (nth 5 it)
                                             (-second-item it)
                                           (regexp-quote (-second-item it)))
                                         ".+?"
                                         (if (nth 6 it)
                                             (-third-item it)
                                           (regexp-quote (-third-item it)))
                                         "$")
                               string-no-newlines))))
         (lmark (-second-item match))
         (rmark (-third-item match))
         (marks (cons lmark rmark))
         (lregexp (nth 5 match))
         (rregexp (nth 6 match))
         (regexp (cons lregexp rregexp))
         (prefix (if lregexp (s-left
                              (cdr (-first-item
                                    (s-matched-positions-all
                                     (s-concat "^" lmark) string-no-newlines)))
                              string)
                   lmark))
         (suffix (if rregexp (s-right
                              (- (length string)
                                 (car (-first-item
                                       (s-matched-positions-all
                                        (s-concat rmark "$") string-no-newlines))))
                              string)
                   rmark))
         (stripped (substring string (length prefix) (* -1 (length suffix))))
         (table (make-hash-table :size 15)))
    (puthash 'match string table)
    (puthash 'string stripped table)
    (puthash 'type (-first-item match) table)
    (puthash 'inline (-fourth-item match) table)
    (puthash 'priority (-fifth-item match) table)
    (puthash 'lmark lmark table)
    (puthash 'rmark rmark table)
    (puthash 'marks marks table)
    (puthash 'prefix prefix table)
    (puthash 'suffix suffix table)
    (puthash 'rregexp rregexp table)
    (puthash 'lregexp lregexp table)
    (puthash 'regexp regexp table)
    table))
;; }}}

;; {{{ User interface
(defun math-preview--submit-region (region)
  "Submit `REGION' to processing program."
  (let* ((beg (car region))
         (end (cdr region))
         (match (math-preview--extract-match
                 (buffer-substring beg end)))
         (type (gethash 'type match)))
    (cond ((string= type "tex") (run-hook-with-args 'math-preview-tex-preprocess-functions match))
          ((string= type "mathml") (run-hook-with-args 'math-preview-mathml-preprocess-functions match))
          ((string= type "asciimath") (run-hook-with-args 'math-preview-asciimath-preprocess-functions match)))
    (run-hook-with-args 'math-preview-preprocess-functions match)
    (math-preview--submit beg end (gethash 'string match) (gethash 'type match) (gethash 'inline match))))

(defun math-preview--region (beg end)
  "Preview equations in region between `BEG' and `END'."
  (->> (math-preview--find-gaps beg end)
       (--map (math-preview--search (car it) (cdr it)))
       (-flatten)
       (-map #'math-preview--submit-region)))

;;;###autoload
(defun math-preview-region (beg end)
  "Preview equations in region between `BEG' and `END'."
  (interactive "r")
  (deactivate-mark)
  (math-preview--region beg end))

;;;###autoload
(defun math-preview-all ()
  "Preview equations in buffer."
  (interactive)
  (math-preview--region (point-min) (point-max)))

;;;###autoload
(defun math-preview-at-point ()
  "Preview equations at point."
  (interactive)
  (->> (math-preview--find-gaps (point-min) (point-max))
     (--filter (and (>= (point) (car it))
                    (< (point) (cdr it))))
     (--map (math-preview--search (car it) (cdr it)))
     (-flatten)
     (--filter (and (>= (point) (car it))
                    (< (point) (cdr it))))
     (-map #'math-preview--submit-region)))

(defun math-preview--clear-region (beg end)
  "Remove all preview overlays in region between `BEG' and `END'."
  (--map (delete-overlay it) (math-preview--overlays beg end)))

;;;###autoload
(defun math-preview-clear-region (beg end)
  "Remove all preview overlays in region between `BEG' and `END'."
  (interactive "r")
  (deactivate-mark)
  (math-preview--clear-region beg end))

;;;###autoload
(defun math-preview-clear-at-point ()
  "Remove all preview overlays."
  (interactive)
  (math-preview--clear-region (point) (point)))

;;;###autoload
(defun math-preview-clear-all ()
  "Remove all preview overlays."
  (interactive)
  (math-preview--clear-region (point-min) (point-max)))

(defun math-preview--set-scale (n)
  "Adjust image size.
Scale is changed by `N' times `math-preview-scale-increment'"
  (let ((o (-first-item (math-preview--overlays (point) (point)))))
    (when o
      (let* ((display (overlay-get o 'display))
             (list (cdr (car (cdr display))))
             (scale (plist-get list ':scale))
             (increment (* math-preview-scale-increment n))
             (new-scale (+ scale increment))
             (new-scale-clipped (if (<= new-scale 0) increment new-scale)))
        (plist-put list ':scale new-scale-clipped)
        (move-overlay o (overlay-start o) (overlay-end o))))))

;;;###autoload
(defun math-preview-increment-scale (n)
  "Increment image size.
Scale is changed by `N' times `math-preview-scale-increment'"
  (interactive "p")
  (math-preview--set-scale (if (or (null n) (<= n 0)) 1 n)))

;;;###autoload
(defun math-preview-decrement-scale (n)
  "Decrement image size.
Scale is changed by `N' times `math-preview-scale-increment'"
  (interactive "p")
  (math-preview--set-scale (if (or (null n) (<= n 0)) -1 (* n -1))))

;;;###autoload
(defun math-preview-copy-svg ()
  "Copy SVG image to clipboard."
  (interactive)
  (let ((o (-first-item (math-preview--overlays (point) (point)))))
    (when o
      (let* ((display (overlay-get o 'display))
             (list (cdr (car (cdr display)))))
        (kill-new (plist-get list ':data))
        (message "Image copied to clipboard")))))

;;;###autoload
(defun math-preview-reset-numbering (num)
  "Reset MathJax equation numbering from `NUM'."
  (interactive "p")
  (setq math-preview--reset-numbering num))
;; }}}


(provide 'math-preview)

;; NOTES
;; ─────
;;   BDF  Buffer default font.  Set by the likes of `(buffer-face-set :family "Noto Sans" :height 180)`,
;;        for instance, subsequently toggled on/off by the command `buffer-face-mode`.
;;
;;   HAT  Height of ‘affected text’ for the display `raise` factor.  The manual says the `raise` factor
;;        ‘is interpreted as a multiple of the height of the affected text.’
;;        https://www.gnu.org/software/emacs/manual/html_node/elisp/Image-Descriptors.html
;;
;;        In our case, that appears to mean the height the buffer default font.  Setting a larger font
;;        across multiple lines (using Font Lock) does not affect the consequent size of math images
;;        generated within those lines.  (It should, of course, but that’s a separate matter.)
;;
;;   MPG  Misalignment owing to pixel granularity.  Maybe it will pass for now.  Possible corrections
;;        include pre-shifting the image internally through SVG just enough to eliminate any fractional
;;        part in the resulting `va`, thus pre-aligning it with the pixel raster.  But this would
;;        complicate the code, not least by making the image dependent on the font size.
;;
;;   SBF  Scaling of images in response to buffer-font changes.  The calculation here is inexact.
;;        Emacs resizes the images a bit differently, at least with Linux, which may affect
;;        the resulting alignment.  Code inspection should reveal the correct algorithm.  TODO
;;
;;   VA · CSS `vertical-align` property.  “Raise (positive value) or lower (negative value)
;;        the box by this distance.  The value `0cm` means the same as `baseline`.”
;;        https://www.w3.org/TR/2011/REC-CSS2-20110607/visudet.html#line-height

;;; math-preview.el ends here
