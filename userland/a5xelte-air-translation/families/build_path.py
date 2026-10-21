#!/usr/bin/env python3
"""Build the path/stroke host compiler using an existing Mesa26.2.4 build."""
import pathlib, shlex, subprocess, sys

def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: build_path.py MESA_BUILD OUTPUT')
    build=pathlib.Path(sys.argv[1]).resolve(); output=pathlib.Path(sys.argv[2]).resolve()
    source=pathlib.Path(__file__).with_name('path_pair_midgard.c').resolve()
    lines=subprocess.check_output(['ninja','-t','commands','src/panfrost/a5_t720_copy_shader'],cwd=build,text=True).splitlines()
    cc=shlex.split(next(x for x in lines if ' -c ../mesa-26.2.4/src/panfrost/a5_t720_copy_shader.c' in x))
    cc.append('-Werror'); cc[cc.index('-c')+1]=str(source); obj=output.with_suffix('.o');cc[cc.index('-o')+1]=str(obj)
    for flag in ('-MD','-MQ','-MF'):
        if flag in cc:
            index=cc.index(flag);del cc[index:index+(1 if flag=='-MD' else 2)]
    subprocess.run(cc,cwd=build,check=True)
    ld=shlex.split(lines[-1]);ld[ld.index('-o')+1]=str(output)
    ld[ld.index('src/panfrost/a5_t720_copy_shader.p/a5_t720_copy_shader.c.o')]=str(obj)
    subprocess.run(['ninja','src/compiler/spirv/libvtn.a'],cwd=build,check=True)
    ld.insert(ld.index('src/compiler/nir/libnir.a'),'src/compiler/spirv/libvtn.a')
    subprocess.run(ld,cwd=build,check=True)

if __name__=='__main__':main()
