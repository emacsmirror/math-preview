`math-preview` uses [MathJax](https://www.mathjax.org/) for displaying [TeX](https://tug.org/), [MathML](https://www.w3.org/Math/) and [AsciiMath](http://asciimath.org/) math inline in Emacs buffers.

![demo](./demo.gif)

## Installation

*NOTE: it's recommended to use the latest Emacs version with this package. See [this issue](https://gitlab.com/matsievskiysv/math-preview/-/issues/1).*
*NOTE: In case of Schema errors update elisp library and nodejs program to the latest version.*

[`math-preview`](./math-preview.el) requires external nodejs program [`math-preview`](./math-preview.js).

It may be installed by issuing the command:

```bash
> npm install -g git+https://gitlab.com/matsievskiysv/math-preview
```

If you don't have `npm` installed, get it from [`asdf`](https://github.com/asdf-vm/asdf-nodejs) or [`nvm`](https://github.com/nvm-sh/nvm).

Make sure that `math-preview` is in you `PATH`.

Install companion package in Emacs:

<kbd>M-x</kbd>+<kbd>package-install</kbd>+<kbd>math-preview</kbd>

If `math-preview` is not in your path, then you need to set variable `math-preview-command` to the location of the program: <kbd>M-x</kbd>+<kbd>customize-variable</kbd>+<kbd>math-preview-command</kbd>.

Or if you use `use-package`, just add the following command:

```elisp
(use-package math-preview
  :custom (math-preview-command "/path/to/math-preview"))
```

## Functions

|   |   |
|:--|:--|
| `math-preview-all` | Preview equations in buffer |
| `math-preview-region` | Preview equations in selected region |
| `math-preview-at-point` | Preview equation at current position |
| `math-preview-clear-all` | Clear equation images in buffer |
| `math-preview-clear-region` | Clear equation images in selected region |
| `math-preview-clear-at-point` | Clear equation image at current position |
| `math-preview-increment-scale` | Enlarge equation image at point |
| `math-preview-decrement-scale` | Shrink equation image at point |
| `math-preview-copy-svg` | Copy SVG code to clipboard |
| `math-preview-start-process` | Start child process (Not required. However, calling this function early would reduce first render time) |
| `math-preview-stop-process` | Stop child process |
| `math-preview-math-preview-reset-numbering` | Reset automatic equation numbering |

## Key bindings

`math-preview` does not add any keybindings to global keymap. However, it adds a number of keybindings to the image overlay, which become active when your cursor is on the image.

|   |   |
|:--|:--|
| `math-preview-clear-at-point` | <kbd>Del</kbd>; <kbd>Backspace</kbd>; <kbd>Space</kbd>; <kbd>Enter</kbd>; <kbd>mouse-1</kbd> |
| `math-preview-clear-all` | <kbd>Ctrl</kbd>+<kbd>Del</kbd>; <kbd>Ctrl</kbd>+<kbd>Backspace</kbd>; <kbd>Ctrl</kbd>+<kbd>mouse-1</kbd> |
| `math-preview-increment-scale` | <kbd>+</kbd>; <kbd>p</kbd> |
| `math-preview-decrement-scale` | <kbd>-</kbd>; <kbd>n</kbd> |
| `math-preview-copy-svg` | <kbd>Ctrl</kbd>+<kbd>Backspace</kbd>; <kbd>Ctrl</kbd>+<kbd>Space</kbd> |

## Equation preprocessing

It might be useful to preprocess equation strings before passing them to MathJax. For this you may use `math-preview-preprocess-functions`, `math-preview-tex-preprocess-functions`, `math-preview-mathml-preprocess-functions` and `math-preview-asciimath-preprocess-functions` customization options. Each equation would be modified by functions in these lists, chained from left to right.

`math-preview-preprocess-functions` are applied to all equations after type specific functions `math-preview-preprocess-functions`, `math-preview-tex-preprocess-functions`, `math-preview-mathml-preprocess-functions` and `math-preview-asciimath-preprocess-functions`. In Emacs terminology, these variables are [abnormal hooks](https://www.gnu.org/software/emacs/manual/html_node/elisp/Hooks.html). Each of them takes one argument that is a hash table with fields:
- `match`: matched string including marks;
- `string`: matched string without marks;
- `type`: equation type (`tex`, `mathml` or `asciimath`);
- `inline`: equation inline flag;
- `priority`: priority value;
- `lmark` and `rmark`: left and right marks respectively;
- `marks`: cons pair of `lmark` and `rmark`;
- `lregexp` and `rregexp`: left and right regexp flags respectively;
- `regexp`: cons pair of `lregexp` and `lregexp`;
- `prefix` and `suffix`: left and right matched marks. Equal to `lmark` and `rmark` is regexp is not used.
You may modify `string` field in place to influence further equation processing.
For example, you might want to replace some variable with another in your equations:
```elisp
(lambda (x)
  (puthash 'string
	   (s-replace "\\phi" "\\varphi"
		      (gethash 'string x))
	   x))
```

Another practical example of equation preprocessing is a standard MathML hook
```elisp
(lambda (x) (puthash 'string (gethash 'match x) x))
```
which replaces stripped equation `string` with the unstripped version `match` in order to preserve `<math></math>` tags.

## SVG postprocessing

Similarly, SVG string may be edited before rendering. `math-preview-svg-postprocess-functions` abnormal hook functions take one argument that is a hash table with single field `string`. You may modify `string` field in place to influence image rendering.

## Configuration

Configuration of the package is done using [`customize`](https://www.gnu.org/software/emacs/manual/html_node/emacs/Easy-Customization.html) framework. To open customization menu type <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview</kbd>.

Note, that most of the configuration options are passed to companion java-script program at startup, so in order to apply new configurations you need to stop currently running program via `math-preview-stop-process` command.

### Debug configuration
Sometimes it's necessary to debug configuration. In order to enable debug buffer, issue the command <kbd>M-:</kbd>+<kbd>(setq math-preview--debug-json t)</kbd>. This will create a `*math-preview*` buffer, where JSON communication between programs will be echoed. Additionally, at startup of java-script program full MathJax configuration will appear in this buffer.

### Set equation marks
Package has 6 variables for equation marks configuration: for TeX, MathML and AsciiMath, each having inline and display versions. Currently only TeX equations distinguish between inline and display modes.

Configuration menus:
* TeX: <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-tex</kbd>
* MathML: <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-mathml</kbd>
* AsciiMath: <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-asciimath</kbd>

### Set preprocess and postprocess functions
These abnormal hooks are described in detail above.

Configuration menus:
* Common: <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview</kbd>
* SVG: <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview</kbd>
* TeX: <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-tex</kbd>
* MathML: <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-mathml</kbd>
* AsciiMath: <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-asciimath</kbd>

### Predefine TeX macros and environments
This package allows adding custom macros and environments globally. This is done in configuration menu <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-tex</kbd>. Following are predefined examples of macro and environment:
$$\ddx[y]{x}$$
$$\begin{braced}A\end{braced}$$

### Preload packages
MathJax allows preload frequently used packages. This is done by adding package to the list in menu <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-tex-packages</kbd>. Under that menu there are sub-menus with configuration options for some of the packages.

Note that some packages require loader to be added. This is done by adding loader to the list in menu <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-mathjax-loader</kbd>.

### Autoload packages
It is possible to automatically load packages when certain macros are invoked. For this you should add `autoload` package to default packages list in <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-tex-packages</kbd> (added by default) and then assign macro and environment names to packages in <kbd>M-x</kbd>+<kbd>customize-group</kbd>+<kbd>math-preview-tex-packages-autoload</kbd>.

### Equation labels
MathJax keeps track of equation labels. Due to this, second conversion of the equation will produce an error `<label> multiply defined`. There are three possible solutions to this problem:
1. Use TeX preprocessing to remove labels from the equations. For this, in the customize menu <kbd>M-x customize-group math-preview-tex</kbd>->Preprocess TeX functions add the following function
   ```emacs
   (lambda (x)(puthash 'string (s-replace-regexp "\\label{.+?}" "" (gethash 'string x)) x))
   ```
2. Reset MathJax my issuing command `math-preview-reset-numbering`
3. Restart `math-preview` process by issuing command `math-preview-stop-process`

### Equation automatic numbering
MathJax may automatically number equations. To enable this feature set `Tags` field in <kbd>M-x customize-group math-preview-mathjax-tex</kbd> customize menu to `AMS math` or `All`. After `math-preview` process reset equations will be automatically numbered. In order to reset equation numbers issue command `math-preview-reset-numbering`. Numerical argument to this function (<kbd>C-u <num></kbd>) selects the first equation number. Note, that this function also resets the equation labels.

It may be desired to reset equation numbers each time the certain command is called. It may be achieved by using `advice-add` function. For example, the following command resets numbering from `1` each time `math-preview-all` function is called.
```emacs
(advice-add #'math-preview-all :before (lambda () (math-preview-reset-numbering 1)))
```

### Regexp equation marks
It is possible to use regexp equation marks. This feature is enabled for each tag individually via `Left regexp` and `Right regexp` checkboxes. This may lead to unexpected results and should be used with caution.

Equation marks use Emacs style regexp. It's recommended to use <kbd>regexp-builder</kbd> to create valid regexp patterns.

#### Equation mark priority
Internally, equation marks are sorted by length to find the best match (for example, to prioritize `$$` over `$`). When using regexp equation marks, this mechanism no longer applies. The `Priority` field lets user adjust equation mark priority.

### Debug mode
In order to trace possible problems with the package it is recommended to start Emacs using command
```elisp
emacs -Q --eval '(progn (package-initialize)(math-preview-start-process))'
```

---

# MATHJAX examples

All equations are displayed inline: $\sqrt[3]{\frac xy}$ $$\frac{n!}{k!(n-k)!} = \binom{n}{k}$$ \(\sqrt[n]{1+x+x^2+x^3+\dots+x^n}\) \[\int_0^\infty \mathrm{e}^{-x}\,\mathrm{d}x\]

$\TeX$ errors are shown in minibuffer: $\frac{x{y}$

Make image bigger or smaller:
\[
S_{12} =
	\begin{cases}
		\sqrt{1 - |S_{11}|^2 - \exp{\left(
			-2 \pi f\displaystyle\sum_{n=1}^N{\frac{D_n}{v_{gr} Q_n}}
		\right)}} \times &                                                        \\
		\times \exp{\left(
			j \displaystyle\sum_{n=1}^N{
			\arccos{\left(\frac{f_{0n}^2-f^2}{f^2 K^H_n + f_{0n}^2 K^E_n}\right)}
		}\right)}        & , \frac{f_0^2-f^2}{f^2 K^H + f_0^2 K^E} \in [-1,1];    \\[30pt]
		\sqrt{1 - |S_{11}|^2}
		\exp{\left(
				j \left[\angle{S_{11}} + \frac{\pi}{2} \right]
		\right)}         & , \frac{f_0^2-f^2}{f^2 K^H + f_0^2 K^E} \notin [-1,1].
	\end{cases}
\]

Use colors:
\(\color{red}\int_{\color{magenta}0}^{\color{yellow}\infty}{\color{cyan}x}\)

Use environments:
$$
\begin{array}{ccccccccc}
0 & \xrightarrow{i} & A & \xrightarrow{f} & B & \xrightarrow{q} & C & \xrightarrow{d} & 0 \\
\downarrow & \searrow & \downarrow & \nearrow & \downarrow & \searrow & \downarrow & \nearrow & \downarrow \\
0 & \xrightarrow{j} & D & \xrightarrow{g} & E & \xrightarrow{r} & F & \xrightarrow{e} & 0
\end{array}
$$

Use MathJax extensions:
$$
\begin{CD}
A @<<< B @>>> C\\
@. @| @AAA\\
@. D @= E
\end{CD}$$

\[\ce{Zn^2+  <=>[+ 2OH-][+ 2H+]
$\underset{\text{zinc hydroxide}}{\ce{Zn(OH)2 v}}
$  <=>[+ 2OH-][+ 2H+]
$\underset{\text{tetrahydroxozincate(II)}}{\ce{[Zn(OH)4]^2-}}$}\]

Copy SVG to kill-ring: $x^2$

MathML:
<math xmlns="http://www.w3.org/1998/Math/MathML">
  <mrow>
    <mi>a</mi> <mo>&InvisibleTimes;</mo> <msup><mi>x</mi><mn>2</mn></msup>
    <mo>+</mo><mi>b</mi><mo>&InvisibleTimes;</mo><mi>x</mi>
    <mo>+</mo><mi>c</mi>
  </mrow>
</math>
