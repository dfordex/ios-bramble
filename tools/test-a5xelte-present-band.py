#!/usr/bin/env python3
"""Compile the actual staged band planner with released Mesa descriptor headers."""
import argparse
import sys
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'userland/a5xelte-air-translation/families'))
from build_runtime_encoder import compile_runtime
p=argparse.ArgumentParser()
p.add_argument('--mesa-build',type=Path,required=True)
p.add_argument('--kernel-source',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
header=a.kernel_source/'iokit/Kernel/arm/A5XELTEPresentBand.h'
source=(ROOT/'tests/a5xelte-present-band.c').read_text().replace(
 '#include A5_PRESENT_BAND_HEADER','#include "'+str(header)+'"')
test=a.output/'test.c';test.write_text(source)
# Instrument the same compiler command used by the released Mesa build.
original=subprocess.run
def run(args,**kw):
 if '-c' in args and str(test) in args:args=[*args,'-fsanitize=address,undefined','-fno-omit-frame-pointer']
 return original(args,**kw)
subprocess.run=run
obj=a.output/'test.o';compile_runtime(a.mesa_build.resolve(),obj,'host',test)
subprocess.run=original
binary=a.output/'test';original(['cc',obj,'-fsanitize=address,undefined','-o',binary],check=True)
original([binary],check=True)
