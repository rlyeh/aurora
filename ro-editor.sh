#!/bin/bash
[[ -z "$_RO_ENV" ]] && source aurora.sh && ro-env
ro-emacs -a vi "$@"
