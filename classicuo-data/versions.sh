#!/bin/sh

prod_url="http://patch.uo.eamythic.com/uopatch-sa/legacyrelease/uo/manifest/uo-legacyrelease.prod"

gen=""
if command -v curl >/dev/null 2>&1; then
  gen=$(curl -sL "${prod_url}" 2>/dev/null | grep -o 'uopatch-sa/[0-9]*/' | head -n 1 | cut -d'/' -f2)
elif command -v wget >/dev/null 2>&1; then
  gen=$(wget -qO- "${prod_url}" 2>/dev/null | grep -o 'uopatch-sa/[0-9]*/' | head -n 1 | cut -d'/' -f2)
fi

if [ -n "${gen}" ]; then
  printf '7.0.%s.0\n' "${gen}"
else
  printf '7.0.255.0\n'
fi
