#!/bin/sh

IFS=$'\n'
for item in $(cat items.in); do
  TYPE=$(echo "$item" | awk {'print $1'})
  NUM=$(echo "$item" | awk {'print $2'})
  if [ $TYPE = a ]; then
    a="${a},${NUM}"
  elif [ $TYPE = c ]; then
    c="${c},${NUM}"
  elif [ $TYPE = g ]; then
    g="${g},${NUM}"
  elif [ $TYPE = h ]; then
    h="${h},${NUM}"
  elif [ $TYPE = s ]; then
    s="${s},${NUM}"
  elif [ $TYPE = u ]; then
    u="${u},${NUM}"
  elif [ $TYPE = v ]; then
    v="${v},${NUM}"
  elif [ $TYPE = x ]; then
    continue
  fi
done

a="new const achievements[] = {${a:1}}"
c="new const crafts[] = {${c:1}}"
g="new const genuines[] = {${g:1}}"
h="new const haunteds[] = {${h:1}}"
s="new const stranges[] = {${s:1}}"
u="new const uniques[] = {${u:1}}"
v="new const vintages[] = {${v:1}}"

echo -e "\n$a"
echo -e "\n$c"
echo -e "\n$g"
echo -e "\n$h"
echo -e "\n$s"
echo -e "\n$u"
echo -e "\n$v"
