#!/usr/bin/env bash

EMACS=${EMACS:-emacs}
$EMACS -q -L . --batch --load ert --load tests/math-preview-test.el --funcall ert-run-tests-batch-and-exit
