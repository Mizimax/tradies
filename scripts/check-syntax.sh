#!/bin/bash
cd mt5/Experts/GoldScalper
echo "Checking GoldScalper.mq5"
echo -e "typedef char* string; typedef double datetime; typedef bool color; \n#define input" > test.cpp
cat GoldScalper.mq5 | grep -v '#property' | grep -v '#include <Trade/Trade.mqh>' | sed 's/#include <GoldScalper\/\(.*\)>/#include "..\/..\/Include\/GoldScalper\/\1"/g' >> test.cpp
g++ -x c++ -fsyntax-only -I../../Include test.cpp 2>&1 | head -n 40
rm test.cpp
