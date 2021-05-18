{ makeInitrd
, writeScript
, runCommandCC, nukeReferences, busybox, dhcpcd, glibc
, kata-agent
}:

let
  extraUtils = runCommandCC "extra-utils"
  {
    buildInputs = [ nukeReferences ];
    allowedReferences = [ "out" ];
  } ''
    set +o pipefail
    mkdir -p $out/bin $out/lib
    ln -s $out/bin $out/sbin
    copy_bin_and_libs() {
      [ -f "$out/bin/$(basename $1)" ] && rm "$out/bin/$(basename $1)"
      cp -pd $1 $out/bin
    }
    # Copy Busybox
    for BIN in ${busybox}/{s,}bin/*; do
      copy_bin_and_libs $BIN
    done
    copy_bin_and_libs ${dhcpcd}/bin/dhcpcd
    # Copy ld manually since it isn't detected correctly
    cp -pv ${glibc.out}/lib/ld*.so.? $out/lib
    # Copy all of the needed libraries
    find $out/bin $out/lib -type f | while read BIN; do
      echo "Copying libs for executable $BIN"
      LDD="$(ldd $BIN)" || continue
      LIBS="$(echo "$LDD" | awk '{print $3}' | sed '/^$/d')"
      for LIB in $LIBS; do
        TGT="$out/lib/$(basename $LIB)"
        if [ ! -f "$TGT" ]; then
          SRC="$(readlink -e $LIB)"
          cp -pdv "$SRC" "$TGT"
        fi
      done
    done
    # Strip binaries further than normal.
    chmod -R u+w $out
    stripDirs "lib bin" "-s"
    # Run patchelf to make the programs refer to the copied libraries.
    find $out/bin $out/lib -type f | while read i; do
      if ! test -L $i; then
        nuke-refs -e $out $i
      fi
    done
    find $out/bin -type f | while read i; do
      if ! test -L $i; then
        echo "patching $i..."
        patchelf --set-interpreter $out/lib/ld*.so.? --set-rpath $out/lib $i || true
      fi
    done
    # Make sure that the patchelf'ed binaries still work.
    echo "testing patched programs..."
    $out/bin/ash -c 'echo hello world' | grep "hello world"
    export LD_LIBRARY_PATH=$out/lib
    $out/bin/mount --help 2>&1 | grep -q "BusyBox"
  '';
  shell = "${extraUtils}/bin/ash";

  init = writeScript "kata-agent" ''
    $!${shell}
    exec ${kata-agent}/bin/kata-agent
  '';
in 
makeInitrd {
  name = "initrd-kata";
  contents = [
    { object = init;
      symlink = "/init"; }
  ];
}
